// Temporary QRs ("gate passes"): the driver picks a package in the app but
// pays only at the gate, after staff confirm there is space. The pass is a
// parking_checkouts record with kind "gate_pass" and no PayMongo payment
// until staff start it. Once paid, finalizePaidCheckout turns it into a
// normal ticket with the same id, so the same QR keeps working.
//
// Payment details are entered with the QR, not at the gate: a GCash or Maya
// number, or a card the app saved with PayMongo (only its token is kept).
// Such a pass is "directPay": when staff start the payment, the driver's
// phone shows one Confirm button, and the server attaches the saved details
// to a PayMongo payment intent, so all that is left is approving it in the
// wallet (or the bank's OTP for a card). Nothing is charged before that
// tap. If the direct payment can't be made, the driver gets PayMongo's
// checkout page instead, as for passes without saved details (QR Ph).
//
// Statuses: awaiting_gate -> pending (paying at the gate) -> paid,
// or back to awaiting_gate if the payment is cancelled or times out;
// cancelled (by the driver) and expired are final.

const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

const paymongo = require("./paymongo");
const { reserveRecovery, releaseRecovery } = require("./refunds");
const { notifyUser, peso } = require("./notify");
const {
  CHECKOUTS,
  asString,
  requireVerifiedUser,
  loadEstablishment,
  priceCheckout,
  buildQrCode,
  chargeDetails,
  driverBilling,
  openPaymongoSession,
  fetchPaidPayment,
  finalizePaidCheckout,
} = require("./checkout");

const KIND = "gate_pass";
const PASS_LIFETIME_MS = 3 * 24 * 60 * 60 * 1000;
const MAX_ACTIVE_PASSES = 3;
/** An unfinished payment at the gate is abandoned after this long. */
const GATE_PAYMENT_TIMEOUT_MS = 5 * 60 * 1000;
/** Keeps a pass mid-payment from being TTL-deleted under the driver. */
const PAYING_KEEP_MS = 24 * 60 * 60 * 1000;
/** E-wallets paid straight from a saved mobile number. */
const WALLET_METHODS = ["gcash", "paymaya"];
/** Where PayMongo sends the driver after approving; the app watches for it. */
const RETURN_URL = "https://smartpark.app/payment-success";
/** A Confirm tap still opening its payment blocks a second one this long. */
const CONFIRM_LOCK_MS = 60 * 1000;

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

/**
 * A Philippine mobile number as "+639XXXXXXXXX", from "0917 123 4567",
 * "9171234567", "+63 917-123-4567" and the like; "" if it isn't one.
 */
function normalizePhMobile(raw) {
  const digits = String(raw || "").replace(/[\s\-().]/g, "");
  const match = /^(?:\+?63|0)?(9\d{9})$/.exec(digits);
  return match ? `+63${match[1]}` : "";
}

/**
 * The payment details saved with a new pass, from what the app sent:
 * { payer, directPay }. A wallet number is checked here; a card token is
 * checked with PayMongo by [checkCard]. Without details (QR Ph, an older
 * app, a card entered at the gate) the pass uses PayMongo's checkout page.
 */
async function savedPayment(data, paymentMethod, checkCard) {
  if (WALLET_METHODS.includes(paymentMethod)) {
    const raw = asString(data.payerPhone);
    if (!raw) return { payer: null, directPay: false };
    const phone = normalizePhMobile(raw);
    if (!phone) {
      throw new HttpsError("invalid-argument", "Enter a valid mobile number, e.g. 0917 123 4567.");
    }
    return { payer: { phone }, directPay: true };
  }
  if (paymentMethod === "card") {
    const methodId = asString(data.cardPaymentMethodId);
    if (!methodId) return { payer: null, directPay: false };
    if (!/^pm_[A-Za-z0-9]+$/.test(methodId)) {
      throw new HttpsError("invalid-argument", "Could not save this card. Try again.");
    }
    const card = await checkCard(methodId);
    return {
      payer: { cardPaymentMethodId: methodId, cardLast4: card.last4 || "", cardBrand: card.brand || "" },
      directPay: true,
    };
  }
  return { payer: null, directPay: false };
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

/** Why the driver's Confirm tap can't open a payment, or null when it can. */
function confirmDenial(c, driverId, nowMs) {
  if (!isPass(c) || c.driverId !== driverId) return ["not-found", "Temporary QR not found."];
  if (c.status !== "pending" || c.gatePaymentMode !== "direct") {
    return ["failed-precondition", "Staff have not started your payment yet."];
  }
  if (gatePaymentTimedOut(c, nowMs)) {
    return ["deadline-exceeded", "The payment timed out. Ask staff to scan your QR again."];
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
    // The driver only confirms on their phone; nothing to type.
    directPay: c.directPay === true,
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

async function cancelIntentQuietly(secretKey, intentId) {
  if (!intentId) return;
  try {
    await paymongo.cancelPaymentIntent(secretKey, intentId);
  } catch (error) {
    // Already paid, processing or cancelled; the re-check decides.
    logger.info(`Could not cancel payment intent ${intentId}: ${error.message}`);
  }
}

/**
 * Ends an unfinished gate payment. The payment is closed first and then
 * re-checked, so one that landed at the last second is finalized instead of
 * lost. Returns the new status.
 */
async function endGatePayment(db, ref, secretKey, c) {
  const fresh = (await ref.get()).data() || c;
  const sessionId = fresh.paymongo?.sessionId;
  const intentId = fresh.paymongo?.intentId;
  await expireSessionQuietly(secretKey, sessionId);
  await cancelIntentQuietly(secretKey, intentId);
  if (sessionId || intentId) {
    const paid = await fetchPaidPayment(secretKey, fresh);
    if (paid) {
      await finalizePaidCheckout(db, ref, paid);
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
    gatePaymentMode: FieldValue.delete(),
    confirmLockAt: FieldValue.delete(),
    deleteAt: c.expiresAt || FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return status;
}

// ---- Driver ----------------------------------------------------------------

/** The saved card's last digits and brand, after checking it with PayMongo. */
async function checkSavedCard(secretKey, methodId) {
  let method;
  try {
    method = await paymongo.getPaymentMethod(secretKey, methodId);
  } catch (error) {
    logger.warn(`Saved card ${methodId} could not be read`, error);
    throw new HttpsError("invalid-argument", "Could not save this card. Check the details and try again.");
  }
  const attributes = method.attributes || {};
  if (attributes.type !== "card") {
    throw new HttpsError("invalid-argument", "Could not save this card. Try again.");
  }
  const details = attributes.details || {};
  return { last4: asString(details.last4), brand: asString(details.brand || details.card_brand) };
}

async function createParkingPass(request, secretKey) {
  const driverId = requireVerifiedUser(request.auth);
  const db = getFirestore();
  const data = request.data || {};
  const record = await priceCheckout(db, driverId, data);

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

  const saved = await savedPayment(data, record.paymentMethod, (id) =>
    checkSavedCard(secretKey, id),
  );

  const ref = db.collection(CHECKOUTS).doc();
  const expiresAt = Timestamp.fromMillis(nowMs + PASS_LIFETIME_MS);
  const qrCode = buildQrCode(ref.id, record, new Date(nowMs));
  await ref.set({
    ...record,
    kind: KIND,
    transactionId: ref.id,
    qrCode,
    status: "awaiting_gate",
    directPay: saved.directPay,
    ...(saved.payer ? { payer: saved.payer } : {}),
    expiresAt,
    // Firestore TTL policy field: unused passes are deleted after expiry.
    deleteAt: expiresAt,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await rememberPaymentChoice(db, driverId, record.paymentMethod, saved.payer);

  return {
    checkoutId: ref.id,
    qrCode,
    amount: record.amount,
    establishmentName: record.establishmentName,
    expiresAt: expiresAt.toMillis(),
    directPay: saved.directPay,
  };
}

/**
 * The method (and wallet number) the driver used, so the next temporary QR
 * starts with them filled in. Never the card token: a card is entered again.
 */
async function rememberPaymentChoice(db, driverId, paymentMethod, payer) {
  try {
    await db
      .collection("users")
      .doc(driverId)
      .set(
        {
          paymentPrefs: {
            method: paymentMethod || "",
            ...(payer?.phone ? { walletPhone: payer.phone } : {}),
          },
        },
        { merge: true },
      );
  } catch (error) {
    // A convenience only; the pass is already made.
    logger.warn(`Could not remember payment choice for ${driverId}`, error);
  }
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

/** Saves [fields] only while the pass is still being paid. */
async function updateIfPending(db, ref, fields) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.data()?.status !== "pending") return false;
    tx.update(ref, { ...fields, updatedAt: FieldValue.serverTimestamp() });
    return true;
  });
}

/** The wallet's billing details: the account's name and email, the saved number. */
async function walletBilling(db, c) {
  const account = (await driverBilling(db, c.driverId)) || {};
  const billing = {};
  if (account.name) billing.name = account.name;
  if (account.email) billing.email = account.email;
  if (c.payer?.phone) billing.phone = c.payer.phone;
  return Object.keys(billing).length > 0 ? billing : null;
}

const STOPPED = new HttpsError("failed-precondition", "Staff stopped this payment.");

/**
 * Opens the payment with the saved details. Returns { status, redirectUrl }:
 * "paid", or "pending" with the wallet's (or bank's) approval page.
 */
async function openDirectPayment(db, ref, secretKey, c) {
  let intentId = null;
  try {
    const intent = await paymongo.createPaymentIntent(
      secretKey,
      paymongo.buildPaymentIntentPayload(chargeDetails(ref.id, c)),
    );
    intentId = intent.id;
    if (!(await updateIfPending(db, ref, { "paymongo.intentId": intentId }))) {
      await cancelIntentQuietly(secretKey, intentId);
      throw STOPPED;
    }
    const methodId =
      c.paymentMethod === "card"
        ? c.payer?.cardPaymentMethodId
        : await paymongo.createPaymentMethod(secretKey, {
            type: c.paymentMethod,
            billing: await walletBilling(db, c),
          });
    if (!methodId) throw new Error("No saved payment details on this pass.");
    const attached = await paymongo.attachPaymentIntent(secretKey, intentId, {
      paymentMethodId: methodId,
      returnUrl: RETURN_URL,
    });
    if (attached.status === "succeeded") {
      await finalizePaidCheckout(db, ref, await paymongo.getPaymentIntent(secretKey, intentId));
      return { status: "paid", redirectUrl: "" };
    }
    if (attached.status === "awaiting_next_action" || attached.status === "processing") {
      const saved = await updateIfPending(db, ref, {
        "paymongo.checkoutUrl": attached.redirectUrl || "",
        "paymongo.status": attached.status,
        confirmLockAt: FieldValue.delete(),
      });
      if (!saved) throw STOPPED;
      return { status: "pending", redirectUrl: attached.redirectUrl || "" };
    }
    throw new Error(`Payment intent ${intentId} is ${attached.status} after attach.`);
  } catch (error) {
    if (error === STOPPED) throw error;
    logger.warn(`Direct payment for ${ref.id} failed; falling back to checkout`, error);
    return openFallbackCheckout(db, ref, secretKey, intentId);
  }
}

/**
 * PayMongo's checkout page, when the saved details could not be used (an
 * expired card token, say). Only once the intent is surely not going to
 * charge, so the driver can never pay twice.
 */
async function openFallbackCheckout(db, ref, secretKey, intentId) {
  if (intentId) {
    await cancelIntentQuietly(secretKey, intentId);
    const intent = await paymongo.getPaymentIntent(secretKey, intentId);
    if (paymongo.isIntentPaid(intent)) {
      await finalizePaidCheckout(db, ref, intent);
      return { status: "paid", redirectUrl: "" };
    }
    const status = String(intent.attributes?.status || "");
    if (status !== "cancelled" && status !== "awaiting_payment_method") {
      throw new HttpsError("unavailable", "Your payment is still processing. Wait a moment.");
    }
  }
  const fresh = (await ref.get()).data() || {};
  if (fresh.status === "paid") return { status: "paid", redirectUrl: "" };
  if (fresh.status !== "pending") throw STOPPED;
  let session;
  try {
    session = await openPaymongoSession(secretKey, ref.id, fresh, db);
  } catch (error) {
    logger.error(`Fallback checkout for ${ref.id} could not open`, error);
    await updateIfPending(db, ref, { paymongo: FieldValue.delete(), confirmLockAt: FieldValue.delete() });
    throw new HttpsError("unavailable", "Could not open the payment. Try again.");
  }
  const saved = await updateIfPending(db, ref, {
    paymongo: {
      sessionId: session.id,
      checkoutUrl: session.checkoutUrl,
      referenceNumber: session.referenceNumber,
      status: session.status,
    },
    confirmLockAt: FieldValue.delete(),
  });
  if (!saved) {
    await expireSessionQuietly(secretKey, session.id);
    throw STOPPED;
  }
  return { status: "pending", redirectUrl: session.checkoutUrl, fallback: true };
}

/**
 * Opens a payment the driver just confirmed: straight to the wallet with
 * saved details, else PayMongo's checkout page. For records made already
 * pending (extra hours). Returns { status, redirectUrl }.
 */
async function openPayment(db, ref, secretKey, c) {
  return c.directPay === true
    ? openDirectPayment(db, ref, secretKey, c)
    : openFallbackCheckout(db, ref, secretKey, null);
}

/**
 * Driver: the Confirm tap at the gate. Pays with the details saved on the
 * pass; calling it again while the payment is open returns the same page.
 */
async function payGatePass(request, secretKey) {
  const driverId = requireVerifiedUser(request.auth);
  const db = getFirestore();
  const ref = db.collection(CHECKOUTS).doc(asString(request.data?.checkoutId) || "-");
  const nowMs = Date.now();

  // Claim first, so a double tap can't open two payments.
  const claim = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const c = snap.exists ? snap.data() : null;
    if (c?.status === "paid" && c.driverId === driverId) return { c, paid: true };
    const denial = confirmDenial(c, driverId, nowMs);
    if (denial) throw new HttpsError(...denial);
    if (c.paymongo?.sessionId || c.paymongo?.intentId) return { c, open: true };
    const locked = millis(c.confirmLockAt);
    if (locked !== null && nowMs - locked < CONFIRM_LOCK_MS) {
      throw new HttpsError("aborted", "Your payment is already opening.");
    }
    tx.update(ref, { confirmLockAt: FieldValue.serverTimestamp() });
    return { c };
  });
  if (claim.paid) return { status: "paid", redirectUrl: "" };
  if (claim.open) {
    const paid = await fetchPaidPayment(secretKey, claim.c);
    if (paid) {
      await finalizePaidCheckout(db, ref, paid);
      return { status: "paid", redirectUrl: "" };
    }
    return { status: "pending", redirectUrl: claim.c.paymongo?.checkoutUrl || "" };
  }
  return openDirectPayment(db, ref, secretKey, claim.c);
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
 * Staff confirmed there is space. A pass with saved details asks the driver
 * to confirm on their phone; any other opens PayMongo's checkout there.
 * Calling it again while the payment is still open is harmless.
 */
async function startGatePayment(request, secretKey) {
  const db = getFirestore();
  const staff = await requireStaff(db, request.auth);
  const ref = db.collection(CHECKOUTS).doc(asString(request.data?.checkoutId) || "-");
  const nowMs = Date.now();

  // Claim the pass first so two taps (or two gates) can't open two payments.
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const c = snap.data();
    const denial = startDenial(snap.exists ? c : null, staff.facilityId, nowMs);
    if (denial) throw new HttpsError(...denial);
    if (c.status === "pending") return { c, fresh: false };
    tx.update(ref, {
      status: "pending",
      gatePaymentMode: c.directPay === true ? "direct" : "checkout",
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
    // Saved details: the driver's Confirm tap opens the payment.
    if (claimed.c.directPay === true) {
      await notifyGateConfirm(db, ref.id, claimed.c);
      return { status: "pending" };
    }
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
  await notifyGateConfirm(db, ref.id, claimed.c);
  return { status: "pending" };
}

/**
 * Tells the driver staff confirmed space, in case the QR isn't open on
 * their phone (a saved image, the phone in a pocket). Tapping it opens the
 * QR, where Confirm (or the payment page) is waiting.
 */
async function notifyGateConfirm(db, checkoutId, c) {
  const amount = peso(c.amountCentavos);
  await notifyUser(db, c.driverId, {
    title: "Staff confirmed there is space",
    body:
      c.directPay === true
        ? `Tap to confirm your ${amount} payment for ${c.establishmentName}.`
        : `Tap to pay ${amount} for ${c.establishmentName}.`,
    data: { kind: "gate_confirm", checkoutId },
  });
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
  const paid = await fetchPaidPayment(secretKey, c);
  if (paid) {
    await finalizePaidCheckout(db, ref, paid);
    return { status: "paid", transactionId: c.transactionId };
  }
  if (gatePaymentTimedOut(c, Date.now())) {
    const status = await endGatePayment(db, ref, secretKey, c);
    return { status: status === "paid" ? "paid" : "timed_out", transactionId: c.transactionId };
  }
  return { status: "pending", stage: paymentStage(c), transactionId: c.transactionId };
}

/**
 * Where a payment in progress is, for staff: "confirm" while the driver
 * hasn't tapped Confirm yet, "approve" once the payment is open on their
 * phone (the wallet, bank or PayMongo page).
 */
function paymentStage(c) {
  if (c.paymongo?.sessionId || c.paymongo?.intentId) return "approve";
  return c.gatePaymentMode === "direct" ? "confirm" : "approve";
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
  WALLET_METHODS,
  isPass,
  isExpired,
  isActivePass,
  gatePaymentTimedOut,
  normalizePhMobile,
  savedPayment,
  startDenial,
  confirmDenial,
  paymentStage,
  passSummary,
  createParkingPass,
  cancelParkingPass,
  payGatePass,
  openPayment,
  findGatePass,
  startGatePayment,
  checkGatePayment,
  cancelGatePayment,
  reconcileGatePass,
};
