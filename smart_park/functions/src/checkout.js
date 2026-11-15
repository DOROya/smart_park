// Parking checkout: the server prices what the driver picked and opens the
// PayMongo checkout (at the gate, see gate_pass.js), and only the server
// marks it paid. Transactions, payments,
// payment_splits and the daily stats are written here and nowhere else.

const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

const {
  PricingError,
  computeAmount,
  platformFeeCentavosFor,
  estimateProcessorFeeCentavos,
} = require("./pricing");
const paymongo = require("./paymongo");
const { dayKeyManila, dayStartManila } = require("./dates");

const CHECKOUTS = "parking_checkouts";

function asString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function requireVerifiedUser(auth) {
  if (!auth) throw new HttpsError("unauthenticated", "Please sign in again.");
  if (auth.token.email_verified !== true) {
    throw new HttpsError("permission-denied", "Verify your email first.");
  }
  return auth.uid;
}

/** Establishment + details merged the way the app shows them. */
async function loadEstablishment(db, establishmentId) {
  const [base, details] = await Promise.all([
    db.collection("establishments").doc(establishmentId).get(),
    db.collection("establishment_details").doc(establishmentId).get(),
  ]);
  if (!base.exists && !details.exists) return null;
  return { ...(base.data() || {}), ...(details.data() || {}) };
}

/**
 * Validates what the driver picked and prices it from the establishment's
 * own rates. Returns the checkout record to store (no PayMongo session yet).
 */
async function priceCheckout(db, driverId, data) {
  const establishmentId = asString(data.establishmentId);
  const vehicleType = asString(data.vehicleType);
  const plan = asString(data.plan);
  const plateNumber = asString(data.plateNumber).toUpperCase();
  const paymentMethod = asString(data.paymentMethod);
  const duration = Number(data.duration);

  if (!establishmentId || !vehicleType || !plan) {
    throw new HttpsError("invalid-argument", "Missing parking details.");
  }
  if (!plateNumber || plateNumber.length > 20) {
    throw new HttpsError("invalid-argument", "Enter a valid plate number.");
  }

  const establishment = await loadEstablishment(db, establishmentId);
  if (!establishment) {
    throw new HttpsError("not-found", "Parking establishment not found.");
  }
  if (String(establishment.status || "").toLowerCase() !== "approved") {
    throw new HttpsError(
      "failed-precondition",
      "This establishment is not accepting drivers right now.",
    );
  }

  let priced;
  try {
    priced = computeAmount({
      ratesByType: establishment.ratesByType,
      vehicleType,
      plan,
      duration,
    });
  } catch (error) {
    if (error instanceof PricingError) {
      throw new HttpsError("invalid-argument", error.message);
    }
    throw error;
  }

  const amountCentavos = Math.round(priced.amount * 100);
  if (amountCentavos < 2000) {
    // PayMongo's minimum checkout amount is PHP 20.
    throw new HttpsError(
      "failed-precondition",
      "This package is below the PHP 20 online payment minimum.",
    );
  }

  const platformFeeCentavos = platformFeeCentavosFor(amountCentavos);
  const estimatedProcessorFeeCentavos = estimateProcessorFeeCentavos(
    amountCentavos,
    paymentMethod,
  );
  return {
    driverId,
    establishmentId,
    establishmentName: asString(establishment.name) || "Parking Establishment",
    ownerId: asString(establishment.ownerId),
    vehicleType,
    vehiclePlate: plateNumber,
    plan,
    duration: priced.duration,
    paymentMethod,
    amount: priced.amount,
    amountCentavos,
    platformFeeCentavos,
    estimatedProcessorFeeCentavos,
    netToOwnerCentavos:
      amountCentavos - platformFeeCentavos - estimatedProcessorFeeCentavos,
    destinationAccountId: asString(establishment.ownerId) || establishmentId,
    slotSnapshot: establishment.slotCounts || {},
  };
}

/** The QR payload; the ticket keeps the checkout's id, so it never changes. */
function buildQrCode(checkoutId, c, generatedAt = new Date()) {
  return JSON.stringify({
    transactionId: checkoutId,
    driverId: c.driverId,
    establishmentId: c.establishmentId,
    vehicleType: c.vehicleType,
    plan: c.plan,
    duration: c.duration,
    vehiclePlate: c.vehiclePlate,
    generatedAt: generatedAt.toISOString(),
  });
}

/** The driver's name and email from their account, for the payment page. */
async function driverBilling(db, driverId) {
  try {
    const user = (await db.collection("users").doc(driverId).get()).data() || {};
    const name = `${asString(user.firstName)} ${asString(user.lastName)}`.trim();
    return { name, email: asString(user.email) };
  } catch (error) {
    logger.warn(`Could not load billing details for ${driverId}`, error);
    return null;
  }
}

/**
 * Opens the PayMongo checkout for a stored checkout record, with the
 * driver's details pre-filled. If PayMongo rejects those details, it opens
 * without them rather than not at all.
 */
async function openPaymongoSession(secretKey, checkoutId, c, db = getFirestore()) {
  const payload = (billing) =>
    paymongo.buildCheckoutPayload({
      amountCentavos: c.amountCentavos,
      platformFeeCentavos: c.platformFeeCentavos,
      description: `SmartPark ${c.establishmentName} - ${c.plan.toUpperCase()} ${c.vehicleType.toUpperCase()}`,
      remarks: "SmartPark parking checkout",
      destinationAccountId: c.destinationAccountId,
      paymentMethod: c.paymentMethod,
      billing,
      metadata: {
        checkoutId,
        driverId: c.driverId,
        establishmentId: c.establishmentId,
        vehicleType: c.vehicleType,
        plan: c.plan,
        duration: c.duration,
        amount: c.amount,
      },
    });
  const billing = await driverBilling(db, c.driverId);
  if (!billing?.name || !billing?.email) {
    return paymongo.createCheckoutSession(secretKey, payload(null));
  }
  try {
    return await paymongo.createCheckoutSession(secretKey, payload(billing));
  } catch (error) {
    logger.warn(`Checkout ${checkoutId}: billing pre-fill rejected, retrying without`, error);
    return paymongo.createCheckoutSession(secretKey, payload(null));
  }
}

/**
 * Marks a checkout paid and writes the ticket, payment, split and stats in
 * one Firestore transaction. Safe to call repeatedly: a checkout that is
 * already paid is left as it is.
 */
async function finalizePaidCheckout(db, checkoutRef, session) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(checkoutRef);
    if (!snap.exists) throw new Error(`Checkout ${checkoutRef.id} vanished.`);
    const c = snap.data();
    if (c.status === "paid") return c;

    const driverSnap = await tx.get(db.collection("users").doc(c.driverId));
    const driver = driverSnap.data() || {};

    const now = Timestamp.now();
    const dayKey = dayKeyManila(now.toDate());
    const txId = c.transactionId;
    const paymongoInfo = {
      linkId: c.paymongo.sessionId,
      checkoutUrl: c.paymongo.checkoutUrl,
      referenceNumber: c.paymongo.referenceNumber,
      status: "paid",
    };
    const paymentMethod = paymongo.paidPaymentMethod(session) || c.paymentMethod;

    tx.set(db.collection("transactions").doc(txId), {
      driverId: c.driverId,
      driverName: `${driver.firstName || ""} ${driver.lastName || ""}`.trim(),
      driverEmail: driver.email || "",
      establishmentId: c.establishmentId,
      establishmentName: c.establishmentName,
      ownerId: c.ownerId,
      amount: c.amount,
      vehiclePlate: c.vehiclePlate,
      qrCode: c.qrCode,
      status: "paid",
      entryStatus: "not_checked_in",
      paymentStatus: "paid",
      paymentMethod,
      paymongo: paymongoInfo,
      vehicleType: c.vehicleType,
      plan: c.plan,
      duration: c.duration,
      slotSnapshot: c.slotSnapshot || {},
      checkoutId: checkoutRef.id,
      paidAtGate: c.kind === "gate_pass",
      createdAtClient: now,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(db.collection("payments").doc(txId), {
      transactionId: txId,
      driverId: c.driverId,
      establishmentId: c.establishmentId,
      ownerId: c.ownerId,
      amount: c.amount,
      status: "paid",
      paymentProvider: "paymongo",
      paymentMethod,
      paymongo: paymongoInfo,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(db.collection("payment_splits").doc(txId), {
      transactionId: txId,
      paymentId: txId,
      establishmentId: c.establishmentId,
      driverId: c.driverId,
      grossAmountCentavos: c.amountCentavos,
      platformFeeCentavos: c.platformFeeCentavos,
      estimatedProcessorFeeCentavos: c.estimatedProcessorFeeCentavos,
      netToOwnerCentavos: c.netToOwnerCentavos,
      destinationAccountId: c.destinationAccountId,
      paymentMethod,
      status: "paid",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(
      db.collection("stats_daily").doc(dayKey),
      {
        date: dayKey,
        dayStart: Timestamp.fromDate(dayStartManila(dayKey)),
        grossCentavos: FieldValue.increment(c.amountCentavos),
        commissionCentavos: FieldValue.increment(c.platformFeeCentavos),
        paymentCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.set(
      db.collection("stats").doc("platform"),
      {
        grossCentavos: FieldValue.increment(c.amountCentavos),
        commissionCentavos: FieldValue.increment(c.platformFeeCentavos),
        paymentCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.update(checkoutRef, {
      status: "paid",
      paidAt: FieldValue.serverTimestamp(),
      // Paid checkouts are kept; only unused temporary QRs are auto-deleted.
      deleteAt: FieldValue.delete(),
      "paymongo.status": "paid",
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { ...c, status: "paid" };
  });
}

async function confirmParkingCheckout(request, secretKey) {
  const uid = requireVerifiedUser(request.auth);
  const checkoutId = asString(request.data?.checkoutId);
  if (!checkoutId) throw new HttpsError("invalid-argument", "Missing checkout.");

  const db = getFirestore();
  const checkoutRef = db.collection(CHECKOUTS).doc(checkoutId);
  const snap = await checkoutRef.get();
  if (!snap.exists || snap.data().driverId !== uid) {
    throw new HttpsError("not-found", "Checkout not found.");
  }

  let checkout = snap.data();
  // A temporary QR is pending without a session for a moment while staff
  // open the payment.
  if (checkout.status === "pending" && checkout.paymongo?.sessionId) {
    const session = await paymongo.getCheckoutSession(
      secretKey,
      checkout.paymongo.sessionId,
    );
    if (paymongo.isSessionPaid(session)) {
      checkout = await finalizePaidCheckout(db, checkoutRef, session);
    }
  }

  return {
    status: checkout.status,
    transactionId: checkout.transactionId,
    qrCode: checkout.status === "paid" ? checkout.qrCode : null,
    amount: checkout.amount,
    establishmentName: checkout.establishmentName,
  };
}

const RECONCILE_WINDOW_MS = 24 * 60 * 60 * 1000;

/**
 * Catches payments the app never confirmed (app closed mid-checkout, lost
 * connection): finalizes paid sessions and expires stale pending ones.
 */
async function reconcilePendingCheckouts(secretKey) {
  const db = getFirestore();
  const cutoff = Timestamp.fromMillis(Date.now() - RECONCILE_WINDOW_MS);
  const pending = await db
    .collection(CHECKOUTS)
    .where("status", "==", "pending")
    .orderBy("createdAt", "desc")
    .limit(100)
    .get();

  let paid = 0;
  let expired = 0;
  // Required here, not at the top: gate_pass.js builds on this module.
  const gatePass = require("./gate_pass");
  let reverted = 0;
  for (const doc of pending.docs) {
    const c = doc.data();
    try {
      if (gatePass.isPass(c) && !c.paymongo?.sessionId) {
        // Staff are still opening the payment, or it failed to open.
        if (await gatePass.reconcileGatePass(db, doc.ref, secretKey, c, Date.now())) reverted++;
        continue;
      }
      const session = await paymongo.getCheckoutSession(
        secretKey,
        c.paymongo.sessionId,
      );
      if (paymongo.isSessionPaid(session)) {
        await finalizePaidCheckout(db, doc.ref, session);
        paid++;
      } else if (gatePass.isPass(c)) {
        // Unfinished gate payment: back to waiting once it times out.
        const status = await gatePass.reconcileGatePass(db, doc.ref, secretKey, c, Date.now());
        if (status === "paid") paid++;
        else if (status) reverted++;
      } else if (c.createdAt && c.createdAt.toMillis() < cutoff.toMillis()) {
        await doc.ref.update({
          status: "expired",
          updatedAt: FieldValue.serverTimestamp(),
        });
        expired++;
      }
    } catch (error) {
      logger.warn(`Reconcile failed for checkout ${doc.id}`, error);
    }
  }
  logger.info(
    `Reconciled checkouts: ${paid} paid, ${expired} expired, ${reverted} gate payments ended.`,
  );
}

module.exports = {
  CHECKOUTS,
  asString,
  requireVerifiedUser,
  loadEstablishment,
  priceCheckout,
  buildQrCode,
  openPaymongoSession,
  confirmParkingCheckout,
  reconcilePendingCheckouts,
  finalizePaidCheckout,
};
