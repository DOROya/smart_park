// Extra hours on a paid ticket, bought in the app, usually when the parking
// reminder says time is almost up, so the driver never runs into overtime
// or has to pay cash at the gate. Nothing is charged until the driver taps
// Confirm (the space is already theirs: they are parked or hold the
// ticket), and it is paid like a gate payment: straight to the wallet with
// the number saved on the ticket's temporary QR, or on PayMongo's page.
//
// Each purchase is a parking_checkouts record with kind "add_hours". Once
// paid, finalizePaidCheckout adds the hours to the ticket (remainingHours)
// and records the payment, split and stats as for any sale. Hours are
// priced at the ticket's overtime rate (fixed when it was bought), the
// facility's own per-hour rate.

const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");

const {
  overtimeRateFor,
  platformFeeCentavosFor,
  estimateProcessorFeeCentavos,
} = require("./pricing");
const { hoursLeft } = require("./refunds");

const KIND = "add_hours";
const MAX_HOURS = 12;
/** PayMongo's smallest payment, in centavos. */
const MIN_CENTAVOS = 2000;

function asString(value) {
  return typeof value === "string" ? value.trim() : "";
}

/**
 * The per-hour price for extra hours on [ticket], in pesos, or null when
 * the facility has none: the rate fixed when the ticket was bought, else
 * the facility's current one.
 */
function extraHourRate(ticket, ratesByType) {
  const fixed = Number(ticket?.purchaseOvertimeRate);
  if (Number.isFinite(fixed) && fixed > 0) return fixed;
  const current = overtimeRateFor(ratesByType, ticket?.vehicleType || "car");
  return Number.isFinite(current) && current > 0 ? current : null;
}

/** Why [ticket] can't get extra hours for [driverId], or null. */
function extraHoursDenial(ticket, driverId) {
  if (!ticket || ticket.driverId !== driverId) return ["not-found", "Ticket not found."];
  if (ticket.source === "walk_in" || ticket.status !== "paid") {
    return ["failed-precondition", "Only a paid SmartPark ticket can get extra hours."];
  }
  return null;
}

/**
 * Prices [hours] at [rate]: { amountCentavos, ... } or throws an
 * HttpsError the driver can act on.
 */
function priceExtraHours(hours, rate, paymentMethod, commissionRate = undefined) {
  if (!Number.isInteger(hours) || hours < 1 || hours > MAX_HOURS) {
    throw new HttpsError("invalid-argument", `Add 1 to ${MAX_HOURS} hours.`);
  }
  if (!rate) {
    throw new HttpsError("failed-precondition", "This facility doesn't sell extra hours in the app.");
  }
  const amountCentavos = Math.round(rate * hours * 100);
  if (amountCentavos < MIN_CENTAVOS) {
    const least = Math.ceil(MIN_CENTAVOS / Math.round(rate * 100));
    throw new HttpsError(
      "failed-precondition",
      `Online payments start at PHP 20. Add at least ${least} hour${least === 1 ? "" : "s"}.`,
    );
  }
  const platformFeeCentavos = platformFeeCentavosFor(amountCentavos, commissionRate);
  const estimatedProcessorFeeCentavos = estimateProcessorFeeCentavos(amountCentavos, paymentMethod);
  return {
    amountCentavos,
    amount: amountCentavos / 100,
    ...(typeof commissionRate === "number" ? { commissionRate } : {}),
    platformFeeCentavos,
    estimatedProcessorFeeCentavos,
    netToOwnerCentavos: amountCentavos - platformFeeCentavos - estimatedProcessorFeeCentavos,
  };
}

/**
 * The checkout record for buying [hours] on [ticket]. The wallet number
 * saved with the ticket's temporary QR pays it directly; a card's saved
 * token was spent on the first payment, so a card uses PayMongo's page.
 */
function extraHoursRecord({ ticketId, ticket, hours, rate, priced, payer, establishmentName }) {
  const paymentMethod = asString(ticket.paymentMethod) || "gcash";
  const wallet = ["gcash", "paymaya"].includes(paymentMethod) && Boolean(payer?.phone);
  return {
    kind: KIND,
    ticketId,
    hours,
    hourRate: rate,
    driverId: ticket.driverId,
    establishmentId: ticket.establishmentId,
    establishmentName: establishmentName || ticket.establishmentName || "Parking Establishment",
    ownerId: asString(ticket.ownerId),
    vehicleType: ticket.vehicleType || "car",
    vehiclePlate: ticket.vehiclePlate || "",
    // Shown on PayMongo and the receipt as "EXTRA HOURS".
    plan: "extra hours",
    duration: hours,
    paymentMethod,
    ...priced,
    destinationAccountId: asString(ticket.ownerId) || ticket.establishmentId,
    transactionId: ticketId,
    status: "pending",
    gatePaymentMode: wallet ? "direct" : "checkout",
    directPay: wallet,
    ...(wallet ? { payer: { phone: payer.phone } } : {}),
  };
}

/**
 * Driver: buys [hours] more on a ticket and opens the payment. Returns
 * { checkoutId, status, redirectUrl }: "paid", or "pending" with the
 * wallet's approval page (or PayMongo's checkout page) to open.
 */
async function addTicketHours(request, secretKey) {
  // Required here: gate_pass.js and checkout.js load this module's
  // neighbours, and only the payment helpers are needed.
  const { requireVerifiedUser, loadEstablishment, CHECKOUTS } = require("./checkout");
  const gatePass = require("./gate_pass");

  const driverId = requireVerifiedUser(request.auth);
  const ticketId = asString(request.data?.ticketId);
  const hours = Number(request.data?.hours);
  const db = getFirestore();
  const ticketSnap = await db.collection("transactions").doc(ticketId || "-").get();
  const ticket = ticketSnap.data();
  const denial = extraHoursDenial(ticketSnap.exists ? ticket : null, driverId);
  if (denial) throw new HttpsError(...denial);

  const establishment = await loadEstablishment(db, ticket.establishmentId);
  if (String(establishment?.status || "").toLowerCase() !== "approved") {
    throw new HttpsError("failed-precondition", "This facility is not accepting payments right now.");
  }
  const rate = extraHourRate(ticket, establishment?.ratesByType);
  // Extra hours use the commission in force when they are bought.
  const commissionRate = await require("./commission").loadCommissionRate(db);
  const priced = priceExtraHours(hours, rate, ticket.paymentMethod, commissionRate);

  // The wallet number saved with the ticket's temporary QR.
  let payer = null;
  if (ticket.checkoutId) {
    const pass = await db.collection(CHECKOUTS).doc(ticket.checkoutId).get();
    payer = pass.data()?.payer || null;
  }

  const ref = db.collection(CHECKOUTS).doc();
  const record = extraHoursRecord({
    ticketId,
    ticket,
    hours,
    rate,
    priced,
    payer,
    establishmentName: establishment?.name,
  });
  await ref.set({
    ...record,
    gatePaymentStartedAt: FieldValue.serverTimestamp(),
    // Unpaid ones are cleared by the TTL policy, like unused QRs.
    deleteAt: Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  const opened = await gatePass.openPayment(db, ref, secretKey, record);
  return { checkoutId: ref.id, ...opened };
}

/**
 * In finalizePaidCheckout's transaction: adds the paid hours to the ticket
 * (also for a visit in progress, which moves its overtime back) and lets
 * the parking reminder fire again for the new end time.
 */
function applyExtraHoursInTx(tx, ticketRef, ticket, c) {
  tx.update(ticketRef, {
    remainingHours: hoursLeft(ticket || {}) + c.hours,
    extraHoursBought: FieldValue.increment(c.hours),
    extraHoursCentavos: FieldValue.increment(c.amountCentavos),
    reminderSentFor: FieldValue.delete(),
    overtimeSentFor: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

module.exports = {
  KIND,
  MAX_HOURS,
  extraHourRate,
  extraHoursDenial,
  priceExtraHours,
  extraHoursRecord,
  addTicketHours,
  applyExtraHoursInTx,
};
