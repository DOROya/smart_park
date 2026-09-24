// Parking checkout: the driver app asks the server to open a PayMongo
// checkout, and only the server marks it paid. Transactions, payments,
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

async function createParkingCheckout(request, secretKey) {
  const driverId = requireVerifiedUser(request.auth);
  const data = request.data || {};
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

  const db = getFirestore();
  const establishment = await loadEstablishment(db, establishmentId);
  if (!establishment) {
    throw new HttpsError("not-found", "Parking establishment not found.");
  }
  if (String(establishment.status || "").toLowerCase() !== "approved") {
    throw new HttpsError(
      "failed-precondition",
      "This establishment is not accepting bookings yet.",
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
  const destinationAccountId = asString(establishment.ownerId) || establishmentId;
  const establishmentName = asString(establishment.name) || "Parking Establishment";

  const checkoutRef = db.collection(CHECKOUTS).doc();
  // The ticket keeps the checkout's id so a retry can never create two.
  const transactionId = checkoutRef.id;
  const qrCode = JSON.stringify({
    transactionId,
    driverId,
    establishmentId,
    vehicleType,
    plan,
    duration: priced.duration,
    vehiclePlate: plateNumber,
    generatedAt: new Date().toISOString(),
  });

  const session = await paymongo.createCheckoutSession(
    secretKey,
    paymongo.buildCheckoutPayload({
      amountCentavos,
      platformFeeCentavos,
      description: `SmartPark ${establishmentName} - ${plan.toUpperCase()} ${vehicleType.toUpperCase()}`,
      remarks: "SmartPark parking checkout",
      destinationAccountId,
      paymentMethod,
      metadata: {
        checkoutId: checkoutRef.id,
        driverId,
        establishmentId,
        vehicleType,
        plan,
        duration: priced.duration,
        amount: priced.amount,
      },
    }),
  );

  await checkoutRef.set({
    driverId,
    establishmentId,
    establishmentName,
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
    destinationAccountId,
    slotSnapshot: establishment.slotCounts || {},
    transactionId,
    qrCode,
    paymongo: {
      sessionId: session.id,
      checkoutUrl: session.checkoutUrl,
      referenceNumber: session.referenceNumber,
      status: session.status,
    },
    status: "pending",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return {
    checkoutId: checkoutRef.id,
    checkoutUrl: session.checkoutUrl,
    amount: priced.amount,
    establishmentName,
  };
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
  if (checkout.status === "pending") {
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
  for (const doc of pending.docs) {
    const c = doc.data();
    try {
      const session = await paymongo.getCheckoutSession(
        secretKey,
        c.paymongo.sessionId,
      );
      if (paymongo.isSessionPaid(session)) {
        await finalizePaidCheckout(db, doc.ref, session);
        paid++;
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
  logger.info(`Reconciled checkouts: ${paid} paid, ${expired} expired.`);
}

module.exports = {
  createParkingCheckout,
  confirmParkingCheckout,
  reconcilePendingCheckouts,
  finalizePaidCheckout,
};
