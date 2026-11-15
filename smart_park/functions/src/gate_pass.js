// Temporary QRs ("gate passes"): the driver picks a package in the app but
// pays only at the gate, after staff confirm there is space. The pass is a
// parking_checkouts record with kind "gate_pass" and no PayMongo session
// until staff start the payment. Once paid, finalizePaidCheckout turns it
// into a normal ticket with the same id, so the same QR keeps working.
//
// Statuses: awaiting_gate -> pending (paying at the gate) -> paid,
// or back to awaiting_gate if the payment is cancelled or times out;
// cancelled (by the driver) and expired are final.

const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

const paymongo = require("./paymongo");
const { reserveRecovery, releaseRecovery } = require("./refunds");
const {
  CHECKOUTS,
  asString,
  requireVerifiedUser,
  loadEstablishment,
  priceCheckout,
  buildQrCode,
  openPaymongoSession,
  finalizePaidCheckout,
} = require("./checkout");

const KIND = "gate_pass";
const PASS_LIFETIME_MS = 3 * 24 * 60 * 60 * 1000;
const MAX_ACTIVE_PASSES = 3;
/** An unfinished payment at the gate is abandoned after this long. */
const GATE_PAYMENT_TIMEOUT_MS = 5 * 60 * 1000;
/** Keeps a pass mid-payment from being TTL-deleted under the driver. */
const PAYING_KEEP_MS = 24 * 60 * 60 * 1000;

function millis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return typeof value === "number" ? value : null;
}

function isPass(c) {
  return Boolean(c) && c.kind === KIND;
}

function isExpired(c, nowMs) {
  const expiresAt = millis(c.expiresAt);
  return expiresAt !== null && nowMs >= expiresAt;
}

/** Still usable at the gate: waiting for, or in the middle of, payment. */
function isActivePass(c, nowMs) {
  if (!isPass(c)) return false;
  if (c.status === "pending") return true;
  return c.status === "awaiting_gate" && !isExpired(c, nowMs);
}

function gatePaymentTimedOut(c, nowMs) {
  const started = millis(c.gatePaymentStartedAt);
  return started !== null && nowMs - started >= GATE_PAYMENT_TIMEOUT_MS;
}

/** Why staff can't start a payment on this pass, or null when they can. */
function startDenial(c, facilityId, nowMs) {
  if (!isPass(c) || c.establishmentId !== facilityId) {
    return ["not-found", "Temporary QR not found for this facility."];
  }
  if (c.status === "paid") return ["failed-precondition", "Already paid. Scan it again to admit."];
  if (c.status === "cancelled") return ["failed-precondition", "The driver cancelled this QR."];
  if (c.status === "expired" || (c.status === "awaiting_gate" && isExpired(c, nowMs))) {
    return ["failed-precondition", "This temporary QR has expired."];
  }
  if (c.status !== "awaiting_gate" && c.status !== "pending") {
    return ["failed-precondition", "This temporary QR can't be used."];
  }
  return null;
}

/** What staff see about a pass. */
function passSummary(id, c, nowMs) {
  return {
    found: true,
    checkoutId: id,
    status: c.status === "awaiting_gate" && isExpired(c, nowMs) ? "expired" : c.status,
    plate: c.vehiclePlate || "",
    vehicleType: c.vehicleType || "",
    plan: c.plan || "",
    duration: c.duration || 0,
    amount: c.amount || 0,
    paymentMethod: c.paymentMethod || "",
    expiresAt: millis(c.expiresAt),
  };
}

/** The caller's active staff record: { uid, facilityId }. */
async function requireStaff(db, auth) {
  if (!auth) throw new HttpsError("unauthenticated", "Please sign in again.");
  const snap = await db.collection("staff_accounts").doc(auth.uid).get();
  const record = snap.data() || {};
  const facilityId = asString(record.facilityId);
  if (!snap.exists || record.active === false || !facilityId) {
    throw new HttpsError("permission-denied", "Only this facility's staff can do that.");
  }
  return { uid: auth.uid, facilityId };
}

async function expireSessionQuietly(secretKey, sessionId) {
  if (!sessionId) return;
  try {
    await paymongo.expireCheckoutSession(secretKey, sessionId);
  } catch (error) {
    // Already paid or already expired; the re-check below decides.
    logger.info(`Could not expire session ${sessionId}: ${error.message}`);
  }
}

/**
 * Ends an unfinished gate payment. The session is expired first and then
 * re-checked, so a payment that landed at the last second is finalized
 * instead of lost. Returns the new status.
 */
async function endGatePayment(db, ref, secretKey, c) {
  const fresh = (await ref.get()).data() || c;
  const sessionId = fresh.paymongo?.sessionId;
  if (sessionId) {
    await expireSessionQuietly(secretKey, sessionId);
    const session = await paymongo.getCheckoutSession(secretKey, sessionId);
    if (paymongo.isSessionPaid(session)) {
      await finalizePaidCheckout(db, ref, session);
      return "paid";
    }
  }
  const status = isExpired(c, Date.now()) ? "expired" : "awaiting_gate";
  // Unpaid: the owner's refund debt set aside for this sale goes back.
  await releaseRecovery(db, fresh.ownerId, fresh.refundRecoveryCentavos || 0);
  await ref.update({
    refundRecoveryCentavos: FieldValue.delete(),
    status,
    paymongo: FieldValue.delete(),
    gatePaymentStartedAt: FieldValue.delete(),
    gatePaymentStaffId: FieldValue.delete(),
    deleteAt: c.expiresAt || FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return status;
}

// ---- Driver ----------------------------------------------------------------

async function createParkingPass(request) {
  const driverId = requireVerifiedUser(request.auth);
  const db = getFirestore();
  const record = await priceCheckout(db, driverId, request.data || {});

  const nowMs = Date.now();
  const mine = await db
    .collection(CHECKOUTS)
    .where("driverId", "==", driverId)
    .where("kind", "==", KIND)
    .get();
  const active = mine.docs.filter((d) => isActivePass(d.data(), nowMs)).length;
  if (active >= MAX_ACTIVE_PASSES) {
    throw new HttpsError(
      "resource-exhausted",
      `You already have ${MAX_ACTIVE_PASSES} temporary QRs. Use or cancel one first.`,
    );
  }

  const ref = db.collection(CHECKOUTS).doc();
  const expiresAt = Timestamp.fromMillis(nowMs + PASS_LIFETIME_MS);
  const qrCode = buildQrCode(ref.id, record, new Date(nowMs));
  await ref.set({
    ...record,
    kind: KIND,
    transactionId: ref.id,
    qrCode,
    status: "awaiting_gate",
    expiresAt,
    // Firestore TTL policy field: unused passes are deleted after expiry.
    deleteAt: expiresAt,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return {
    checkoutId: ref.id,
    qrCode,
    amount: record.amount,
    establishmentName: record.establishmentName,
    expiresAt: expiresAt.toMillis(),
  };
}

async function cancelParkingPass(request) {
  const driverId = requireVerifiedUser(request.auth);
  const checkoutId = asString(request.data?.checkoutId);
  const db = getFirestore();
  const ref = db.collection(CHECKOUTS).doc(checkoutId || "-");
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const c = snap.data();
    if (!snap.exists || !isPass(c) || c.driverId !== driverId) {
      throw new HttpsError("not-found", "Temporary QR not found.");
    }
    if (c.status === "pending") {
      throw new HttpsError("failed-precondition", "Payment is in progress at the gate.");
    }
    if (c.status !== "awaiting_gate") return { status: c.status };
    tx.update(ref, { status: "cancelled", updatedAt: FieldValue.serverTimestamp() });
    return { status: "cancelled" };
  });
}

// ---- Staff -----------------------------------------------------------------

/** Finds a pass at the caller's facility by its QR id or by plate. */
async function findGatePass(request) {
  const db = getFirestore();
  const { facilityId } = await requireStaff(db, request.auth);
  const checkoutId = asString(request.data?.checkoutId);
  const plate = asString(request.data?.plate).toUpperCase();
  const nowMs = Date.now();

  if (checkoutId) {
    const snap = await db.collection(CHECKOUTS).doc(checkoutId).get();
    const c = snap.data();
    if (!snap.exists || !isPass(c) || c.establishmentId !== facilityId) {
      return { found: false };
    }
    return passSummary(snap.id, c, nowMs);
  }
  if (!plate) throw new HttpsError("invalid-argument", "Missing QR or plate.");

  const matches = await db
    .collection(CHECKOUTS)
    .where("establishmentId", "==", facilityId)
    .where("vehiclePlate", "==", plate)
    .get();
  const active = matches.docs
    .filter((d) => isActivePass(d.data(), nowMs))
    .sort((a, b) => (millis(b.data().createdAt) || 0) - (millis(a.data().createdAt) || 0));
  if (active.length === 0) return { found: false };
  return passSummary(active[0].id, active[0].data(), nowMs);
}

/**
 * Staff confirmed there is space: opens the PayMongo payment, which the
 * driver's app picks up and shows. Calling it again while the payment is
 * still open is harmless.
 */
async function startGatePayment(request, secretKey) {
  const db = getFirestore();
  const staff = await requireStaff(db, request.auth);
  const ref = db.collection(CHECKOUTS).doc(asString(request.data?.checkoutId) || "-");
  const nowMs = Date.now();

  // Claim the pass first so two taps (or two gates) can't open two sessions.
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const c = snap.data();
    const denial = startDenial(snap.exists ? c : null, staff.facilityId, nowMs);
    if (denial) throw new HttpsError(...denial);
    if (c.status === "pending") return { c, fresh: false };
    tx.update(ref, {
      status: "pending",
      gatePaymentStartedAt: FieldValue.serverTimestamp(),
      gatePaymentStaffId: staff.uid,
      deleteAt: Timestamp.fromMillis(nowMs + PAYING_KEEP_MS),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { c, fresh: true };
  });
  if (!claimed.fresh) return { status: "pending" };

  // The facility may have been suspended since the QR was made.
  const establishment = await loadEstablishment(db, claimed.c.establishmentId);
  let session;
  try {
    if (String(establishment?.status || "").toLowerCase() !== "approved") {
      throw new HttpsError("failed-precondition", "This facility is not accepting drivers right now.");
    }
    // An owner who owes refunds pays part back from this sale.
    const recovery = await reserveRecovery(db, claimed.c.ownerId, claimed.c.netToOwnerCentavos);
    if (recovery > 0) await ref.update({ refundRecoveryCentavos: recovery });
    session = await openPaymongoSession(secretKey, ref.id, {
      ...claimed.c,
      refundRecoveryCentavos: recovery,
    });
  } catch (error) {
    await endGatePayment(db, ref, secretKey, claimed.c);
    if (error instanceof HttpsError) throw error;
    logger.error(`Gate payment for ${ref.id} could not start`, error);
    throw new HttpsError("unavailable", "Could not open the payment. Try again.");
  }
  await ref.update({
    paymongo: {
      sessionId: session.id,
      checkoutUrl: session.checkoutUrl,
      referenceNumber: session.referenceNumber,
      status: session.status,
    },
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { status: "pending" };
}

/**
 * Staff poll this while the driver pays. Finalizes a paid pass without
 * waiting for the driver's app, and abandons a payment left too long.
 */
async function checkGatePayment(request, secretKey) {
  const db = getFirestore();
  const { facilityId } = await requireStaff(db, request.auth);
  const ref = db.collection(CHECKOUTS).doc(asString(request.data?.checkoutId) || "-");
  const snap = await ref.get();
  const c = snap.data();
  if (!snap.exists || !isPass(c) || c.establishmentId !== facilityId) {
    throw new HttpsError("not-found", "Temporary QR not found for this facility.");
  }
  if (c.status !== "pending") {
    return { status: c.status, transactionId: c.transactionId };
  }
  const sessionId = c.paymongo?.sessionId;
  if (sessionId) {
    const session = await paymongo.getCheckoutSession(secretKey, sessionId);
    if (paymongo.isSessionPaid(session)) {
      await finalizePaidCheckout(db, ref, session);
      return { status: "paid", transactionId: c.transactionId };
    }
  }
  if (gatePaymentTimedOut(c, Date.now())) {
    const status = await endGatePayment(db, ref, secretKey, c);
    return { status: status === "paid" ? "paid" : "timed_out", transactionId: c.transactionId };
  }
  return { status: "pending", transactionId: c.transactionId };
}

/** Staff stop an unfinished payment; the QR goes back to waiting. */
async function cancelGatePayment(request, secretKey) {
  const db = getFirestore();
  const { facilityId } = await requireStaff(db, request.auth);
  const ref = db.collection(CHECKOUTS).doc(asString(request.data?.checkoutId) || "-");
  const snap = await ref.get();
  const c = snap.data();
  if (!snap.exists || !isPass(c) || c.establishmentId !== facilityId) {
    throw new HttpsError("not-found", "Temporary QR not found for this facility.");
  }
  if (c.status !== "pending") return { status: c.status, transactionId: c.transactionId };
  const status = await endGatePayment(db, ref, secretKey, c);
  return { status, transactionId: c.transactionId };
}

/** For the scheduled reconcile: a pending pass nobody is finishing. */
async function reconcileGatePass(db, ref, secretKey, c, nowMs) {
  if (!gatePaymentTimedOut(c, nowMs)) return null;
  return endGatePayment(db, ref, secretKey, c);
}

module.exports = {
  KIND,
  PASS_LIFETIME_MS,
  MAX_ACTIVE_PASSES,
  GATE_PAYMENT_TIMEOUT_MS,
  isPass,
  isExpired,
  isActivePass,
  gatePaymentTimedOut,
  startDenial,
  passSummary,
  createParkingPass,
  cancelParkingPass,
  findGatePass,
  startGatePayment,
  checkGatePayment,
  cancelGatePayment,
  reconcileGatePass,
};
