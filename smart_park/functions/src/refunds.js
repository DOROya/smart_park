// Refunds when SmartPark pulls a facility. Drivers pay at the gate, so only
// paid tickets with hours left can be stranded. The driver gets the unused
// share of what the owner received: the price less SmartPark's commission
// and PayMongo's processing fee, which are not refundable. Who covers it
// depends on why the facility was pulled:
//   - documents the admin approved turned out invalid -> SmartPark
//   - anything else -> the owner, recovered from their next online sales
//
// When refunds happen:
//   - deactivated: automatically, for every ticket with hours left
//   - suspended: the driver may request one (an admin approves it), and
//     after 14 days still suspended it is automatic
//   - a vehicle parked when this happens is refunded after it exits
//
// refunds/{ticketId} statuses: requested -> processing -> sent -> refunded,
// processing | sent -> failed (retried), requested -> rejected,
// awaiting_exit -> processing. A refund is "sent" once PayMongo accepts it
// and "refunded" only when PayMongo says the money went through.

const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

const paymongo = require("./paymongo");
const { platformFeeCentavosFor, estimateProcessorFeeCentavos } = require("./pricing");
const { notifyUser, peso } = require("./notify");
const { notifyAdmins, refundRequestAlert } = require("./alerts");

const REFUNDS = "refunds";
const BALANCES = "owner_refund_balances";
const SUSPENSION_REFUND_DAYS = 14;
/** A driver's request nobody decided in this long is approved by itself. */
const REQUEST_AUTO_APPROVE_DAYS = 3;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Restriction reasons that mean the admin approved bad documents. */
const ADMIN_FAULT_REASONS = ["Invalid business permit", "Incomplete or false documents"];

/** Share of each recovery-paying sale that goes to paying refunds back. */
const RECOVERY_SHARE = 0.5;

// Mirrors includedStayHours in lib/services/parking_pricing.dart.
const BASE_STAY_HOURS = 2;
const HOURS_PER_WEEK = 168;
const HOURS_PER_MONTH = 720;

function includedStayHours(plan, duration) {
  const n = Number(duration) >= 1 ? Math.floor(Number(duration)) : 1;
  switch (String(plan || "base").trim().toLowerCase()) {
    case "extended":
      return BASE_STAY_HOURS + n;
    case "daily":
      return 24 * n;
    case "weekly":
      return HOURS_PER_WEEK * n;
    case "monthly":
      return HOURS_PER_MONTH * n;
    default:
      return BASE_STAY_HOURS;
  }
}

/** Mirrors ticketHoursLeft in lib/services/parking_pricing.dart. */
function hoursLeft(ticket) {
  if (typeof ticket.remainingHours === "number") return Math.max(0, Math.floor(ticket.remainingHours));
  const entry = String(ticket.entryStatus || "").toLowerCase();
  if (entry === "checked_out" || entry === "exited") return 0;
  return includedStayHours(ticket.plan, ticket.duration);
}

function isParked(ticket) {
  const entry = String(ticket.entryStatus || "").toLowerCase();
  return entry === "checked_in" || entry === "inside";
}

/** Online-paid tickets only: walk-ins never went through PayMongo. */
function isRefundable(ticket) {
  return ticket.status === "paid" && ticket.source !== "walk_in" && Boolean(ticket.paymongo);
}

/**
 * What part of a ticket's price can be refunded at all, in centavos: the
 * price less SmartPark's commission and PayMongo's processing fee, worked
 * out as at checkout. Mirrors refundableBase in
 * lib/services/parking_refunds.dart.
 */
function refundableBase(ticket) {
  const paid = Math.round(Number(ticket.amount || 0) * 100);
  if (paid <= 0) return { paid: 0, platformFee: 0, processorFee: 0, refundable: 0 };
  // The commission the ticket was sold at (5% before rates were saved).
  const platformFee = platformFeeCentavosFor(paid, ticket.commissionRate);
  const processorFee = estimateProcessorFeeCentavos(paid, ticket.paymentMethod);
  return { paid, platformFee, processorFee, refundable: Math.max(0, paid - platformFee - processorFee) };
}

/** The unused share of the refundable part, in centavos (rounded down). */
function refundCentavos(ticket, unused = hoursLeft(ticket)) {
  const total = includedStayHours(ticket.plan, ticket.duration);
  const { refundable } = refundableBase(ticket);
  if (total <= 0 || unused <= 0 || refundable <= 0) return 0;
  return Math.min(refundable, Math.floor((refundable * Math.min(unused, total)) / total));
}

/** Who covers a refund, from the reasons the facility was pulled. */
function paidByFor(reasons) {
  const list = Array.isArray(reasons) ? reasons : [];
  return list.some((r) => ADMIN_FAULT_REASONS.includes(r)) ? "platform" : "owner";
}

function facilityStatusOf(details) {
  return String(details?.status || "").trim().toLowerCase();
}

function millis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  return typeof value === "number" ? value : null;
}

/**
 * What an owner repays for a refund they cover: all of it. The refund comes
 * only out of the owner's own share (SmartPark's commission and PayMongo's
 * fee were kept back from it), so nothing is given back.
 */
function ownerOwesCentavos(refundedCentavos) {
  return Math.max(0, Math.floor(refundedCentavos || 0));
}

/** Whether a suspension started at [suspendedAt] is due for refunds. */
function suspensionRefundDue(suspendedAt, nowMs) {
  const start = millis(suspendedAt);
  return start !== null && nowMs - start >= SUSPENSION_REFUND_DAYS * DAY_MS;
}

/** Whether a request made at [requestedAt] has waited long enough. */
function requestOverdue(requestedAt, nowMs) {
  const start = millis(requestedAt);
  return start !== null && nowMs - start >= REQUEST_AUTO_APPROVE_DAYS * DAY_MS;
}

/** Whether PayMongo reports a refund as paid out. */
function isRefundSettled(paymongoStatus) {
  return String(paymongoStatus || "").toLowerCase() === "succeeded";
}

/** How much of an owner's debt one sale may repay, in centavos. */
function recoveryFor(owedCentavos, netToOwnerCentavos) {
  const owed = Math.max(0, Math.floor(owedCentavos || 0));
  const cap = Math.floor(Math.max(0, netToOwnerCentavos || 0) * RECOVERY_SHARE);
  return Math.min(owed, cap);
}

/** The refund record for a ticket, before it is saved. */
function buildRefund(ticketId, ticket, details, cause, status) {
  const unused = hoursLeft(ticket);
  const reasons = Array.isArray(details?.restrictionReasons) ? details.restrictionReasons : [];
  return {
    ticketId,
    driverId: ticket.driverId || "",
    establishmentId: ticket.establishmentId || "",
    establishmentName: ticket.establishmentName || details?.name || "",
    ownerId: ticket.ownerId || details?.ownerId || "",
    vehiclePlate: ticket.vehiclePlate || "",
    vehicleType: ticket.vehicleType || "",
    plan: ticket.plan || "",
    duration: ticket.duration || 0,
    ticketAmountCentavos: Math.round(Number(ticket.amount || 0) * 100),
    // Kept back from the refund; shown to the driver as the calculation.
    platformFeeCentavos: refundableBase(ticket).platformFee,
    processorFeeCentavos: refundableBase(ticket).processorFee,
    totalHours: includedStayHours(ticket.plan, ticket.duration),
    unusedHours: unused,
    amountCentavos: refundCentavos(ticket, unused),
    cause,
    restrictionReasons: reasons,
    paidBy: paidByFor(reasons),
    status,
  };
}

// ---- PayMongo ---------------------------------------------------------------

/** The PayMongo payment id behind a ticket, from the ticket or its session. */
async function paymentIdFor(secretKey, ticket) {
  if (ticket.paymongo?.paymentId) return ticket.paymongo.paymentId;
  const sessionId = ticket.paymongo?.linkId || ticket.paymongo?.sessionId;
  if (!sessionId) return null;
  const session = await paymongo.getCheckoutSession(secretKey, sessionId);
  return paymongo.paidPaymentId(session);
}

/**
 * Sends a refund that is ready (or re-sends a failed one). Claims it first so
 * two runs can never pay it twice.
 */
async function processRefund(db, refundRef, secretKey, actor = "system") {
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(refundRef);
    const r = snap.data();
    if (!snap.exists || !["approved", "failed", "awaiting_exit"].includes(r.status)) {
      return null;
    }
    const ticketSnap = await tx.get(db.collection("transactions").doc(r.ticketId));
    const ticket = ticketSnap.data() || {};
    // Hours may have changed (a parked vehicle has since left). A refund
    // already sent once keeps its amount: its hours came off the ticket then.
    const locked = typeof r.lockedAmountCentavos === "number";
    const unused = locked ? r.unusedHours : hoursLeft(ticket);
    const amountCentavos = locked ? r.lockedAmountCentavos : refundCentavos(ticket, unused);
    tx.update(refundRef, {
      status: "processing",
      unusedHours: unused,
      amountCentavos,
      processedBy: actor,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { ...r, unusedHours: unused, amountCentavos, ticket };
  });
  if (!claimed) return null;

  if (claimed.amountCentavos <= 0) {
    await refundRef.update({
      status: "refunded",
      note: "No unused hours left to refund.",
      refundedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "refunded";
  }

  let refund;
  try {
    const paymentId = await paymentIdFor(secretKey, claimed.ticket);
    if (!paymentId) throw new Error("No PayMongo payment found for this ticket.");
    refund = await paymongo.createRefund(secretKey, {
      paymentId,
      amountCentavos: claimed.amountCentavos,
      notes: `SmartPark: ${claimed.establishmentName} was ${claimed.cause === "deactivated" ? "deactivated" : "suspended"}.`,
      metadata: { ticketId: claimed.ticketId, cause: claimed.cause, paidBy: claimed.paidBy },
    });
  } catch (error) {
    logger.warn(`Refund for ticket ${claimed.ticketId} failed`, error);
    await refundRef.update({
      status: "failed",
      failureReason: String(error.message || error).slice(0, 300),
      updatedAt: FieldValue.serverTimestamp(),
    });
    // Told once; the daily retries after that are silent.
    if (!claimed.retries) {
      await notifyUser(db, claimed.driverId, {
        title: "Refund delayed",
        body:
          `Your ${peso(claimed.amountCentavos)} refund for ${claimed.establishmentName} ` +
          "could not be sent yet. SmartPark will try again.",
        data: { ticketId: claimed.ticketId, kind: "refund_failed" },
      });
    }
    return "failed";
  }

  const ownerPays = claimed.paidBy === "owner" && Boolean(claimed.ownerId);
  const owed = ownerPays ? ownerOwesCentavos(claimed.amountCentavos) : 0;
  // PayMongo accepted it; the money has only arrived once it says so.
  const settled = isRefundSettled(refund.status);
  // Sent again after PayMongo failed it: the owner was charged the first time.
  const firstSend = !claimed.charged;
  const batch = db.batch();
  batch.update(refundRef, {
    status: settled ? "refunded" : "sent",
    lockedAmountCentavos: claimed.amountCentavos,
    charged: true,
    ...(firstSend ? { ownerOwedCentavos: owed } : {}),
    paymongoRefundId: refund.id,
    paymongoRefundStatus: refund.status,
    failureReason: FieldValue.delete(),
    sentAt: FieldValue.serverTimestamp(),
    ...(settled ? { refundedAt: FieldValue.serverTimestamp() } : {}),
    updatedAt: FieldValue.serverTimestamp(),
  });
  // The refunded hours can no longer be used.
  batch.update(db.collection("transactions").doc(claimed.ticketId), {
    remainingHours: 0,
    refundStatus: settled ? "refunded" : "sent",
    refundedCentavos: claimed.amountCentavos,
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (ownerPays && firstSend) {
    batch.set(
      db.collection(BALANCES).doc(claimed.ownerId),
      {
        ownerId: claimed.ownerId,
        owedCentavos: FieldValue.increment(owed),
        refundedCentavos: FieldValue.increment(owed),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  if (firstSend) {
    batch.set(
      db.collection("stats").doc("refunds"),
      {
        ownerCentavos: FieldValue.increment(owed),
        platformCentavos: FieldValue.increment(claimed.amountCentavos - owed),
        count: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  await batch.commit();
  await notifyUser(db, claimed.driverId, {
    title: "Refund sent",
    body:
      `${peso(claimed.amountCentavos)} for your unused hours at ` +
      `${claimed.establishmentName} is on its way back to the account you paid with.`,
    data: { ticketId: claimed.ticketId, kind: "refund_sent" },
  });
  if (ownerPays && firstSend) {
    await notifyUser(db, claimed.ownerId, {
      title: "A refund was charged to you",
      body:
        `${peso(claimed.amountCentavos)} was refunded to a driver at ` +
        `${claimed.establishmentName}. ${peso(owed)} will come out of your later ` +
        "online sales. You can dispute it in your Report tab.",
      data: { ticketId: claimed.ticketId, kind: "refund_charged" },
    });
  }
  return settled ? "refunded" : "sent";
}

/**
 * Every 15 minutes: asks PayMongo about refunds that were sent. One that
 * went through becomes "refunded"; one PayMongo could not complete becomes
 * "failed" and is sent again by the daily retry, for the same amount.
 */
async function confirmSentRefunds(secretKey) {
  const db = getFirestore();
  const sent = await db.collection(REFUNDS).where("status", "==", "sent").limit(50).get();
  for (const doc of sent.docs) {
    const r = doc.data();
    try {
      if (!r.paymongoRefundId) continue;
      const refund = await paymongo.getRefund(secretKey, r.paymongoRefundId);
      const status = String(refund.status || "").toLowerCase();
      if (isRefundSettled(status)) {
        const batch = db.batch();
        batch.update(doc.ref, {
          status: "refunded",
          paymongoRefundStatus: status,
          refundedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        batch.update(db.collection("transactions").doc(doc.id), {
          refundStatus: "refunded",
          updatedAt: FieldValue.serverTimestamp(),
        });
        await batch.commit();
      } else if (status === "failed") {
        await doc.ref.update({
          status: "failed",
          paymongoRefundStatus: status,
          failureReason: "PayMongo could not complete the refund.",
          updatedAt: FieldValue.serverTimestamp(),
        });
        await notifyUser(db, r.driverId, {
          title: "Refund delayed",
          body:
            `Your ${peso(r.amountCentavos)} refund for ${r.establishmentName} ` +
            "did not go through. SmartPark will send it again.",
          data: { ticketId: doc.id, kind: "refund_failed" },
        });
      }
    } catch (error) {
      logger.warn(`Could not confirm refund ${doc.id}`, error);
    }
  }
}

/**
 * Daily: a driver's request nobody decided within 3 days is approved and
 * sent, so their money never waits on an admin without limit.
 */
async function approveOverdueRequests(db, secretKey, nowMs) {
  const waiting = await db.collection(REFUNDS).where("status", "==", "requested").get();
  for (const doc of waiting.docs) {
    const r = doc.data();
    if (!requestOverdue(r.requestedAt || r.createdAt, nowMs)) continue;
    try {
      const approved = await db.runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        if (snap.data()?.status !== "requested") return false;
        tx.update(doc.ref, {
          status: "approved",
          decidedBy: "system",
          decisionNote: `Approved automatically: not reviewed within ${REQUEST_AUTO_APPROVE_DAYS} days.`,
          decidedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (approved) await processRefund(db, doc.ref, secretKey);
    } catch (error) {
      logger.error(`Auto-approving refund ${doc.id} failed`, error);
    }
  }
}

// ---- Issuing ----------------------------------------------------------------

/**
 * Refunds every eligible ticket at a facility for [cause], without approval.
 * Parked vehicles get an awaiting_exit refund, sent when they leave. Pending
 * driver requests are sent too: the automatic refund supersedes them.
 */
async function refundFacility(db, establishmentId, details, cause, secretKey) {
  const tickets = await db
    .collection("transactions")
    .where("establishmentId", "==", establishmentId)
    .where("status", "==", "paid")
    .get();
  const ready = [];
  for (const doc of tickets.docs) {
    const ticket = doc.data();
    if (!isRefundable(ticket) || hoursLeft(ticket) <= 0) continue;
    const ref = db.collection(REFUNDS).doc(doc.id);
    const status = isParked(ticket) ? "awaiting_exit" : "approved";
    const created = await db.runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      const old = existing.data();
      if (existing.exists && !["requested", "rejected"].includes(old.status)) return false;
      tx.set(ref, {
        ...buildRefund(doc.id, ticket, details, cause, status),
        createdAt: old?.createdAt || FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (created && status === "approved") ready.push(ref);
  }
  let refunded = 0;
  for (const ref of ready) {
    const result = await processRefund(db, ref, secretKey);
    if (result === "refunded" || result === "sent") refunded++;
  }
  logger.info(
    `Facility ${establishmentId} (${cause}): ${ready.length} refunds sent, ${refunded} refunded.`,
  );
}

/** Firestore trigger on establishment_details: suspension clock + deactivation. */
async function onFacilityStatusChange(establishmentId, before, after, secretKey) {
  const was = facilityStatusOf(before);
  const now = facilityStatusOf(after);
  if (was === now || !after) return;
  const db = getFirestore();
  const ref = db.collection("establishment_details").doc(establishmentId);
  if (now === "suspended") {
    await ref.set({ suspendedAt: FieldValue.serverTimestamp() }, { merge: true });
  } else if (was === "suspended") {
    await ref.set({ suspendedAt: FieldValue.delete() }, { merge: true });
  }
  if (now === "deactivated") {
    await refundFacility(db, establishmentId, after, "deactivated", secretKey);
  }
  if (was === "suspended" && now === "approved") {
    await closeOpenRequests(db, establishmentId);
  }
}

const REINSTATED_NOTE = "The facility was reinstated, so your ticket can be used again.";

/**
 * A reinstated facility's tickets work again, so refund requests nobody
 * decided yet are closed instead of staying approvable.
 */
async function closeOpenRequests(db, establishmentId) {
  const open = await db
    .collection(REFUNDS)
    .where("establishmentId", "==", establishmentId)
    .where("status", "==", "requested")
    .get();
  for (const doc of open.docs) {
    const closed = await db.runTransaction(async (tx) => {
      const snap = await tx.get(doc.ref);
      if (snap.data()?.status !== "requested") return false;
      tx.update(doc.ref, {
        status: "rejected",
        decidedBy: "system",
        decisionNote: REINSTATED_NOTE,
        decidedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!closed) continue;
    const r = doc.data();
    await notifyUser(db, r.driverId, {
      title: "Refund request closed",
      body: `${r.establishmentName} is open again. ${REINSTATED_NOTE}`,
      data: { ticketId: doc.id, kind: "refund_closed" },
    });
  }
}

/** Daily: refunds tickets at facilities suspended for 14 days or more. */
async function refundLongSuspensions(secretKey) {
  const db = getFirestore();
  const suspended = await db
    .collection("establishment_details")
    .where("status", "==", "suspended")
    .get();
  const nowMs = Date.now();
  for (const doc of suspended.docs) {
    const details = doc.data();
    if (!suspensionRefundDue(details.suspendedAt, nowMs)) continue;
    try {
      await refundFacility(db, doc.id, details, "suspended_14_days", secretKey);
    } catch (error) {
      logger.error(`Suspension refunds failed for ${doc.id}`, error);
    }
  }
  await approveOverdueRequests(db, secretKey, nowMs);
  // Retry refunds that failed for a passing reason (network, PayMongo down).
  const failed = await db.collection(REFUNDS).where("status", "==", "failed").limit(50).get();
  for (const doc of failed.docs) {
    const r = doc.data();
    const age = nowMs - (millis(r.updatedAt) || nowMs);
    if (r.retries >= 3 || age < DAY_MS / 2) continue;
    await doc.ref.update({ retries: FieldValue.increment(1) });
    await processRefund(db, doc.ref, secretKey);
  }
}

/** Ticket trigger: a parked vehicle at a pulled facility has left. */
async function onTicketExit(ticketId, before, after, secretKey) {
  if (!after || isParked(after) || !before || !isParked(before)) return;
  const db = getFirestore();
  const ref = db.collection(REFUNDS).doc(ticketId);
  const snap = await ref.get();
  if (snap.exists && snap.data().status === "awaiting_exit") {
    await processRefund(db, ref, secretKey);
  }
}

// ---- Callables --------------------------------------------------------------

/** Driver: asks for a refund on a ticket at a suspended facility. */
async function requestRefund(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Please sign in again.");
  const ticketId = String(request.data?.ticketId || "").trim();
  const db = getFirestore();
  const ticketSnap = await db.collection("transactions").doc(ticketId || "-").get();
  const ticket = ticketSnap.data();
  if (!ticketSnap.exists || ticket.driverId !== uid) {
    throw new HttpsError("not-found", "Ticket not found.");
  }
  const detailsSnap = await db.collection("establishment_details").doc(ticket.establishmentId).get();
  const details = detailsSnap.data() || {};
  if (facilityStatusOf(details) !== "suspended") {
    throw new HttpsError("failed-precondition", "Refunds are only for tickets at a suspended facility.");
  }
  if (!isRefundable(ticket) || hoursLeft(ticket) <= 0) {
    throw new HttpsError("failed-precondition", "This ticket has no unused hours to refund.");
  }
  if (isParked(ticket)) {
    throw new HttpsError("failed-precondition", "Exit the facility first, then request the refund.");
  }
  const ref = db.collection(REFUNDS).doc(ticketId);
  const refund = buildRefund(ticketId, ticket, details, "driver_request", "requested");
  const result = await db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists && existing.data().status !== "rejected") {
      return { status: existing.data().status, fresh: false };
    }
    tx.set(ref, {
      ...refund,
      requestedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { status: "requested", fresh: true };
  });
  // Nobody deciding approves it after a few days, so admins hear now.
  if (result.fresh) {
    await notifyAdmins(db, refundRequestAlert(refund, REQUEST_AUTO_APPROVE_DAYS));
  }
  return { status: result.status };
}

/** Admin: approves (and sends) or rejects a driver's refund request. */
async function decideRefund(request, secretKey) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Please sign in again.");
  const db = getFirestore();
  const caller = await db.collection("users").doc(uid).get();
  if (caller.data()?.role !== "admin") throw new HttpsError("permission-denied", "Admins only.");
  const ticketId = String(request.data?.ticketId || "").trim();
  const approve = request.data?.approve === true;
  const note = String(request.data?.note || "").trim().slice(0, 300);
  const ref = db.collection(REFUNDS).doc(ticketId || "-");

  const decided = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const r = snap.data();
    if (!snap.exists) throw new HttpsError("not-found", "Refund not found.");
    selfCaseCheck(r, uid);
    // Failed ones can be retried from the same screen.
    if (!["requested", "failed"].includes(r.status)) return r.status;
    tx.update(ref, {
      status: approve ? "approved" : "rejected",
      decidedBy: uid,
      decidedAt: FieldValue.serverTimestamp(),
      ...(note ? { decisionNote: note } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return approve ? "approved" : "rejected";
  });
  if (decided === "rejected") {
    const r = (await ref.get()).data() || {};
    await notifyUser(db, r.driverId, {
      title: "Refund request declined",
      body:
        `Your refund request for ${r.establishmentName} was not approved.` +
        (note ? ` ${note}` : "") +
        " Your hours stay on the ticket.",
      data: { ticketId, kind: "refund_rejected" },
    });
  }
  if (decided !== "approved") return { status: decided };
  return { status: (await processRefund(db, ref, secretKey, uid)) || "processing" };
}

// ---- Owner disputes and direct repayment --------------------------------------

async function requireAdmin(db, auth) {
  if (!auth?.uid) throw new HttpsError("unauthenticated", "Please sign in again.");
  const caller = await db.collection("users").doc(auth.uid).get();
  if (caller.data()?.role !== "admin") throw new HttpsError("permission-denied", "Admins only.");
  return auth.uid;
}

/** No admin decides a case about their own account (docs/admin-roles.md). */
function selfCaseCheck(record, adminId) {
  if (adminId && (record?.driverId === adminId || record?.ownerId === adminId)) {
    throw new HttpsError("permission-denied", "Another admin has to decide a case about your own account.");
  }
}

/** Why an owner can't dispute this refund's charge, or null when they can. */
function disputeDenial(refund, ownerId) {
  if (!refund || refund.ownerId !== ownerId) return ["not-found", "Refund not found."];
  if (refund.paidBy !== "owner") {
    return ["failed-precondition", "This refund is not charged to you."];
  }
  if (refund.dispute) {
    return ["failed-precondition", "You already disputed this refund."];
  }
  return null;
}

/** Owner: says a refund should not be charged to them, and why. */
async function disputeRefundCharge(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Please sign in again.");
  const ticketId = String(request.data?.ticketId || "").trim();
  const message = String(request.data?.message || "").trim().slice(0, 500);
  if (message.length < 10) {
    throw new HttpsError("invalid-argument", "Explain why in a sentence or two.");
  }
  const db = getFirestore();
  const ref = db.collection(REFUNDS).doc(ticketId || "-");
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const denial = disputeDenial(snap.data(), uid);
    if (denial) throw new HttpsError(...denial);
    tx.update(ref, {
      dispute: { status: "open", message, createdAt: Timestamp.now() },
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { status: "open" };
}

/**
 * Admin: upholds an owner's dispute (SmartPark takes over the charge and the
 * owner's balance drops by what they owed for it) or turns it down.
 */
async function resolveRefundDispute(request) {
  const db = getFirestore();
  const adminId = await requireAdmin(db, request.auth);
  const ticketId = String(request.data?.ticketId || "").trim();
  const uphold = request.data?.uphold === true;
  const note = String(request.data?.note || "").trim().slice(0, 300);
  const ref = db.collection(REFUNDS).doc(ticketId || "-");

  const resolved = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const r = snap.data();
    if (!snap.exists) throw new HttpsError("not-found", "Refund not found.");
    selfCaseCheck(r, adminId);
    if (r.dispute?.status !== "open") {
      throw new HttpsError("failed-precondition", "This refund has no open dispute.");
    }
    const dispute = {
      ...r.dispute,
      status: uphold ? "upheld" : "rejected",
      resolvedBy: adminId,
      resolvedAt: Timestamp.now(),
      ...(note ? { note } : {}),
    };
    if (!uphold) {
      tx.update(ref, { dispute, updatedAt: FieldValue.serverTimestamp() });
      return r;
    }
    // Only a refund already sent has been added to the owner's balance.
    const owed =
      r.charged || r.status === "refunded"
        ? Math.max(0, r.ownerOwedCentavos ?? r.amountCentavos ?? 0)
        : 0;
    tx.update(ref, {
      dispute,
      paidBy: "platform",
      ownerOwedCentavos: 0,
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (owed > 0) {
      // May go below zero when part was already repaid: that is credit,
      // which later charges use up first.
      tx.set(
        db.collection(BALANCES).doc(r.ownerId),
        {
          owedCentavos: FieldValue.increment(-owed),
          refundedCentavos: FieldValue.increment(-owed),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      tx.set(
        db.collection("stats").doc("refunds"),
        {
          ownerCentavos: FieldValue.increment(-owed),
          platformCentavos: FieldValue.increment(owed),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    return r;
  });
  await notifyUser(db, resolved.ownerId, {
    title: uphold ? "Refund dispute upheld" : "Refund dispute turned down",
    body: uphold
      ? `SmartPark now covers the ${peso(resolved.amountCentavos)} refund at ${resolved.establishmentName}.`
      : `The ${peso(resolved.amountCentavos)} refund at ${resolved.establishmentName} stays charged to you.` +
        (note ? ` ${note}` : ""),
    data: { ticketId, kind: "refund_dispute" },
  });
  return { status: uphold ? "upheld" : "rejected" };
}

/**
 * Admin: records money an owner paid SmartPark directly toward their refund
 * balance (asked for when a facility has no later sales to recover it from).
 */
async function recordOwnerRepayment(request) {
  const db = getFirestore();
  const adminId = await requireAdmin(db, request.auth);
  const ownerId = String(request.data?.ownerId || "").trim();
  const centavos = Math.floor(Number(request.data?.amountCentavos));
  if (!ownerId || !(centavos > 0)) {
    throw new HttpsError("invalid-argument", "Enter the amount received.");
  }
  selfCaseCheck({ ownerId }, adminId);
  const ref = db.collection(BALANCES).doc(ownerId);
  const left = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const owed = Math.max(0, snap.data()?.owedCentavos || 0);
    if (centavos > owed) {
      throw new HttpsError("failed-precondition", `Only ${peso(owed)} is still owed.`);
    }
    tx.update(ref, {
      owedCentavos: FieldValue.increment(-centavos),
      recoveredCentavos: FieldValue.increment(centavos),
      directPaidCentavos: FieldValue.increment(centavos),
      lastDirectPaymentAt: FieldValue.serverTimestamp(),
      lastDirectPaymentBy: adminId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return owed - centavos;
  });
  await notifyUser(db, ownerId, {
    title: "Payment recorded",
    body: `SmartPark recorded your ${peso(centavos)} payment. ${peso(left)} is left on your refund balance.`,
    data: { kind: "refund_repayment" },
  });
  return { owedCentavos: left };
}

// ---- Owner recovery (used by checkout) ---------------------------------------

/**
 * Reserves part of an owner's refund debt to come out of this sale's split.
 * Returns the centavos reserved (0 when nothing is owed).
 */
async function reserveRecovery(db, ownerId, netToOwnerCentavos) {
  if (!ownerId) return 0;
  const ref = db.collection(BALANCES).doc(ownerId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const amount = recoveryFor(snap.data()?.owedCentavos, netToOwnerCentavos);
    if (amount <= 0) return 0;
    tx.update(ref, {
      owedCentavos: FieldValue.increment(-amount),
      reservedCentavos: FieldValue.increment(amount),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return amount;
  });
}

/** A reserved recovery was paid (in the split) or released (payment ended). */
function settleRecoveryInTx(tx, db, ownerId, amount, paid) {
  if (!ownerId || !(amount > 0)) return;
  tx.set(
    db.collection(BALANCES).doc(ownerId),
    {
      reservedCentavos: FieldValue.increment(-amount),
      ...(paid
        ? { recoveredCentavos: FieldValue.increment(amount) }
        : { owedCentavos: FieldValue.increment(amount) }),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function releaseRecovery(db, ownerId, amount) {
  if (!ownerId || !(amount > 0)) return;
  await db.runTransaction(async (tx) => settleRecoveryInTx(tx, db, ownerId, amount, false));
}

module.exports = {
  selfCaseCheck,
  refundableBase,
  REFUNDS,
  BALANCES,
  ADMIN_FAULT_REASONS,
  SUSPENSION_REFUND_DAYS,
  includedStayHours,
  hoursLeft,
  refundCentavos,
  paidByFor,
  ownerOwesCentavos,
  disputeDenial,
  suspensionRefundDue,
  requestOverdue,
  isRefundSettled,
  REQUEST_AUTO_APPROVE_DAYS,
  confirmSentRefunds,
  recoveryFor,
  buildRefund,
  processRefund,
  onFacilityStatusChange,
  refundLongSuspensions,
  onTicketExit,
  requestRefund,
  decideRefund,
  disputeRefundCharge,
  resolveRefundDispute,
  recordOwnerRepayment,
  reserveRecovery,
  settleRecoveryInTx,
  releaseRecovery,
};
