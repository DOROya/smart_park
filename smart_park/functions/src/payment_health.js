// Payment health, for the admin dashboard: is money getting where it should?
//
// A driver's payment is confirmed in one of two ways. Usually the app (or
// the gate staff's phone) asks PayMongo and gets the ticket at once. When
// the phone dies or loses signal first, reconcilePendingCheckouts finds the
// paid payment within 15 minutes and finishes it: a "rescued" payment.
// Gate payments that end unpaid (timed out, cancelled, failed to open) go
// back to waiting and expired QRs are deleted, so the record is kept here
// as daily counters, written as each thing happens:
//   payment_health_daily/{YYYY-MM-DD}  (Manila day)
//   stats/reconcile                    (the 15-minute job's last run)
// Both are server-only (closed by the rules); admins read a summary
// through getPaymentHealth.

const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

const { dayKeyManila, dayStartManila } = require("./dates");

const DAILY = "payment_health_daily";

// What the counters count.
const COUNTERS = [
  "confirmedInApp", // paid, confirmed by the driver's or staff's phone
  "rescued", // paid, confirmed by the 15-minute check
  "gateTimedOut", // gate payment not finished in time
  "gateCancelled", // gate payment stopped by staff
  "gateFailedToStart", // gate payment could not be opened
  "checkoutsAbandoned", // in-app checkout left unpaid for a day
];

// The 15-minute job is overdue after this long.
const RECONCILE_OVERDUE_MS = 35 * 60 * 1000;
// A gate payment times out after 5 minutes and the job runs every 15, so
// one still pending after 30 minutes was missed.
const GATE_STUCK_MS = 30 * 60 * 1000;
// In-app checkouts are expired by the job after 24 hours.
const CHECKOUT_STUCK_MS = 25 * 60 * 60 * 1000;
// A sent refund PayMongo hasn't confirmed after this long needs a look.
const REFUND_SLOW_MS = 7 * 24 * 60 * 60 * 1000;

const REFUNDS_IN_FLIGHT = ["approved", "processing", "sent"];

function dailyRef(db, date = new Date()) {
  return db.collection(DAILY).doc(dayKeyManila(date));
}

function counterUpdate(field, date = new Date()) {
  const key = dayKeyManila(date);
  return {
    date: key,
    dayStart: Timestamp.fromDate(dayStartManila(key)),
    [field]: FieldValue.increment(1),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** Counts one [field] event today, inside the transaction [tx]. */
function countInTx(tx, db, field) {
  tx.set(dailyRef(db), counterUpdate(field), { merge: true });
}

/** Counts one [field] event today. Best effort: never throws. */
async function count(db, field) {
  try {
    await dailyRef(db).set(counterUpdate(field), { merge: true });
  } catch (error) {
    logger.warn(`Could not count payment health event ${field}`, error);
  }
}

/** Remembers how the 15-minute job's latest run went. Never throws. */
async function recordReconcileRun(db, result) {
  try {
    await db.collection("stats").doc("reconcile").set({
      lastRunAt: FieldValue.serverTimestamp(),
      checked: result.checked || 0,
      paid: result.paid || 0,
      expired: result.expired || 0,
      gatePaymentsEnded: result.reverted || 0,
      errors: result.errors || 0,
    });
  } catch (error) {
    logger.warn("Could not record the reconcile run", error);
  }
}

function millis(value) {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  return null;
}

/**
 * The dashboard's summary. Pure, so it can be tested.
 *  - [days]: payment_health_daily records for the period, any order.
 *  - [pending]: parking_checkouts now in status "pending".
 *  - [refunds]: refunds that are in flight or failed.
 *  - [lastRun]: stats/reconcile.
 *  - [rescuedRecent]: the latest rescued payments, newest first.
 */
function summarizePaymentHealth({ days = [], pending = [], refunds = [], lastRun = null, rescuedRecent = [], nowMs, periodDays }) {
  const totals = Object.fromEntries(COUNTERS.map((c) => [c, 0]));
  for (const day of days) {
    for (const c of COUNTERS) totals[c] += Number(day[c] || 0);
  }
  const paid = totals.confirmedInApp + totals.rescued;

  // One entry per day of the period, oldest first, zero for quiet days, so
  // the chart always has [periodDays] bars (one busy day is not one wide bar).
  const byDate = new Map(days.map((d) => [String(d.date), d]));
  const dates =
    periodDays > 0
      ? Array.from({ length: periodDays }, (_, i) =>
          dayKeyManila(new Date(nowMs - (periodDays - 1 - i) * 24 * 60 * 60 * 1000)),
        )
      : [...byDate.keys()].sort();
  const series = dates.map((date) => {
    const d = byDate.get(date) || {};
    return {
      date,
      confirmedInApp: Number(d.confirmedInApp || 0),
      rescued: Number(d.rescued || 0),
      unfinished:
        Number(d.gateTimedOut || 0) +
        Number(d.gateCancelled || 0) +
        Number(d.gateFailedToStart || 0) +
        Number(d.checkoutsAbandoned || 0),
    };
  });

  let stuck = 0;
  let oldestPendingMinutes = null;
  for (const c of pending) {
    const since = millis(c.gatePaymentStartedAt) ?? millis(c.createdAt);
    if (since === null) continue;
    const age = nowMs - since;
    const minutes = Math.floor(age / 60000);
    if (oldestPendingMinutes === null || minutes > oldestPendingMinutes) oldestPendingMinutes = minutes;
    const gate = c.kind === "gate_pass";
    if (age > (gate ? GATE_STUCK_MS : CHECKOUT_STUCK_MS)) stuck++;
  }

  let refundsInFlight = 0;
  let refundsFailed = 0;
  let refundsSlow = 0;
  for (const r of refunds) {
    const status = String(r.status || "");
    if (REFUNDS_IN_FLIGHT.includes(status)) refundsInFlight++;
    if (status === "failed") refundsFailed++;
    const sentAt = millis(r.sentAt);
    if (status === "sent" && sentAt !== null && nowMs - sentAt > REFUND_SLOW_MS) refundsSlow++;
  }

  const lastRunMs = millis(lastRun?.lastRunAt);
  const lastRunMinutesAgo = lastRunMs === null ? null : Math.floor((nowMs - lastRunMs) / 60000);
  const jobOverdue = lastRunMs === null || nowMs - lastRunMs > RECONCILE_OVERDUE_MS;

  const problems = [];
  if (jobOverdue) {
    problems.push(
      lastRunMs === null
        ? "The 15-minute payment check has not run yet."
        : `The 15-minute payment check last ran ${lastRunMinutesAgo} minutes ago.`,
    );
  }
  if (stuck > 0) problems.push(`${stuck} payment${stuck === 1 ? " is" : "s are"} stuck in progress.`);
  if (refundsFailed > 0) {
    problems.push(`${refundsFailed} refund${refundsFailed === 1 ? "" : "s"} failed (retried daily).`);
  }
  if (refundsSlow > 0) {
    problems.push(`${refundsSlow} sent refund${refundsSlow === 1 ? " has" : "s have"} not been confirmed by PayMongo after 7 days.`);
  }

  return {
    periodDays,
    status: problems.length === 0 ? "ok" : "attention",
    problems,
    paid,
    confirmedInApp: totals.confirmedInApp,
    rescued: totals.rescued,
    rescuedPercent: paid === 0 ? 0 : Math.round((totals.rescued / paid) * 1000) / 10,
    unfinished: {
      gateTimedOut: totals.gateTimedOut,
      gateCancelled: totals.gateCancelled,
      gateFailedToStart: totals.gateFailedToStart,
      checkoutsAbandoned: totals.checkoutsAbandoned,
    },
    inProgress: pending.length,
    stuck,
    oldestPendingMinutes,
    refunds: { inFlight: refundsInFlight, failed: refundsFailed, slow: refundsSlow },
    reconcile: {
      lastRunAt: lastRunMs === null ? null : new Date(lastRunMs).toISOString(),
      lastRunMinutesAgo,
      overdue: jobOverdue,
      lastPaid: Number(lastRun?.paid || 0),
      lastErrors: Number(lastRun?.errors || 0),
    },
    series,
    rescuedRecent: rescuedRecent.map((c) => ({
      establishmentName: c.establishmentName || "",
      amount: Number(c.amount || 0),
      kind: c.kind === "gate_pass" ? "gate" : c.kind === "add_hours" ? "add_hours" : "app",
      paidAt: millis(c.paidAt) === null ? null : new Date(millis(c.paidAt)).toISOString(),
    })),
  };
}

/** Admin-only callable: the summary for the last [days] (1-90, default 7). */
async function getPaymentHealth(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Please sign in again.");
  const db = getFirestore();
  const caller = await db.collection("users").doc(request.auth.uid).get();
  if (caller.data()?.role !== "admin") throw new HttpsError("permission-denied", "Admins only.");

  const periodDays = Math.min(90, Math.max(1, Math.floor(Number(request.data?.days) || 7)));
  const now = new Date();
  const firstKey = dayKeyManila(new Date(now.getTime() - (periodDays - 1) * 24 * 60 * 60 * 1000));

  const [days, pending, refunds, lastRun, rescued] = await Promise.all([
    db.collection(DAILY).where("date", ">=", firstKey).get(),
    db.collection("parking_checkouts").where("status", "==", "pending").limit(500).get(),
    db.collection("refunds").where("status", "in", [...REFUNDS_IN_FLIGHT, "failed"]).limit(500).get(),
    db.collection("stats").doc("reconcile").get(),
    db
      .collection("parking_checkouts")
      .where("confirmedBy", "==", "reconcile")
      .orderBy("paidAt", "desc")
      .limit(5)
      .get()
      .catch((error) => {
        // Only the list of examples needs this index; the rest still works.
        logger.warn("Could not list rescued payments", error);
        return { docs: [] };
      }),
  ]);

  return summarizePaymentHealth({
    days: days.docs.map((d) => d.data()),
    pending: pending.docs.map((d) => d.data()),
    refunds: refunds.docs.map((d) => d.data()),
    lastRun: lastRun.data() || null,
    rescuedRecent: rescued.docs.map((d) => d.data()),
    nowMs: now.getTime(),
    periodDays,
  });
}

/** Admins are pushed about payment problems at most this often. */
const ALERT_EVERY_MS = 6 * 60 * 60 * 1000;

/**
 * The problems worth waking an admin for, from a summary: payments stuck
 * in progress and an overdue 15-minute check. (Refund retries are daily
 * and shown on the dashboard, not pushed.)
 */
function alertProblems(summary) {
  const out = [];
  if (summary.stuck > 0) {
    out.push(`${summary.stuck} payment${summary.stuck === 1 ? " is" : "s are"} stuck in progress.`);
  }
  if (summary.reconcile?.overdue) {
    out.push(
      summary.reconcile.lastRunMinutesAgo === null
        ? "The 15-minute payment check has not run yet."
        : `The 15-minute payment check last ran ${summary.reconcile.lastRunMinutesAgo} minutes ago.`,
    );
  }
  return out;
}

/** Whether an alert may go out now, given the last one at [lastAlertMs]. */
function alertDue(problems, lastAlertMs, nowMs) {
  return problems.length > 0 && (lastAlertMs === null || nowMs - lastAlertMs >= ALERT_EVERY_MS);
}

/**
 * Pushes admins when payments are stuck or the 15-minute check is overdue,
 * once every 6 hours at most (stats/reconcile.lastAlertAt). Run from the
 * reconcile job and from the 5-minute reminder job, so a stopped reconcile
 * job is noticed too. Best effort.
 */
async function alertAdminsIfNeeded(db = getFirestore(), nowMs = Date.now()) {
  try {
    const [pending, lastRun] = await Promise.all([
      db.collection("parking_checkouts").where("status", "==", "pending").limit(500).get(),
      db.collection("stats").doc("reconcile").get(),
    ]);
    const summary = summarizePaymentHealth({
      pending: pending.docs.map((d) => d.data()),
      lastRun: lastRun.data() || null,
      nowMs,
      periodDays: 1,
    });
    const problems = alertProblems(summary);
    if (!alertDue(problems, millis(lastRun.data()?.lastAlertAt), nowMs)) return 0;
    await db.collection("stats").doc("reconcile").set(
      { lastAlertAt: Timestamp.fromMillis(nowMs), lastAlertProblems: problems },
      { merge: true },
    );
    const { notifyAdmins } = require("./alerts");
    return notifyAdmins(db, {
      title: "Payments need attention",
      body: `${problems.join(" ")} Open Payment Health in the admin app.`,
      data: { kind: "payment_health" },
    });
  } catch (error) {
    logger.warn("Could not check payment health for an alert", error);
    return 0;
  }
}

module.exports = {
  ALERT_EVERY_MS,
  alertProblems,
  alertDue,
  alertAdminsIfNeeded,
  DAILY,
  COUNTERS,
  countInTx,
  count,
  recordReconcileRun,
  summarizePaymentHealth,
  getPaymentHealth,
};
