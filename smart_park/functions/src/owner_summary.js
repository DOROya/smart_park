// End-of-day summary for owners (docs/qol-features.md, item C): one push a
// day at the hour the owner picks (default 9:00 PM, Philippine time) with
// the day's gate activity, sales, gate cash and staff still on duty. Taps
// open Reports, or Staff when cash or a shift needs action.
//
// Settings: users/{owner}.notificationPrefs.dailySummary { enabled, hour }.
// What was sent: owner_summaries/{owner}.lastSentDay (server only), so a
// retried hourly run never sends twice.

const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions");

const { notifyUser } = require("./notify");
const { dayKeyManila, dayStartManila } = require("./dates");

const DEFAULT_HOUR = 21;
const SENT = "owner_summaries";
/** How far back gate cash not yet handed over is looked for. */
const CASH_LOOKBACK_DAYS = 14;
const DAY_MS = 24 * 60 * 60 * 1000;

/** The owner's choice: { enabled, hour } (on by default, at 9:00 PM). */
function dailySummaryPrefs(user) {
  const p = user?.notificationPrefs?.dailySummary || {};
  const hour = Number(p.hour);
  return {
    enabled: p.enabled !== false,
    hour: Number.isInteger(hour) && hour >= 0 && hour <= 23 ? hour : DEFAULT_HOUR,
  };
}

/** The hour (0-23) in Manila at [ms]. */
function manilaHour(ms) {
  return new Date(ms + 8 * 60 * 60 * 1000).getUTCHours();
}

function cents(pesos) {
  return Math.round(Math.max(0, Number(pesos) || 0) * 100);
}

function allowed(log) {
  return String(log.status || log.decision || "ALLOWED").toUpperCase() !== "DENIED";
}

/**
 * The day's figures, from plain data (unit-tested without Firestore):
 *   dayLogs: today's gate logs; inside: vehicles inside now;
 *   splits: today's payment splits; cashLogs: recent logs with gate cash;
 *   openShifts: shifts not ended.
 */
function summarizeOwnerDay({ dayLogs = [], inside = 0, splits = [], cashLogs = [], openShifts = [] }) {
  let entries = 0;
  let exits = 0;
  let walkInCashCentavos = 0;
  let overtimeUncollectedCentavos = 0;
  for (const log of dayLogs) {
    if (!allowed(log)) continue;
    if (log.scanType === "entry") entries++;
    if (log.scanType === "exit") {
      exits++;
      walkInCashCentavos += cents(log.walkInFee);
      if (log.overtimeStatus === "cash_due") overtimeUncollectedCentavos += cents(log.overtimeAmount);
    }
  }
  let salesCentavos = 0;
  for (const s of splits) {
    if (String(s.status || "paid").toLowerCase() !== "paid") continue;
    salesCentavos += Math.max(0, Math.round(Number(s.grossAmountCentavos) || 0));
  }
  // Cash staff took (overtime marked collected, walk-in fees) not yet
  // handed to the owner, by staff member.
  const owed = new Map();
  for (const log of cashLogs) {
    if (log.cashHandoverId) continue;
    const amount =
      (log.overtimeStatus === "collected" ? cents(log.overtimeAmount) : 0) + cents(log.walkInFee);
    if (amount <= 0 || !log.staffId) continue;
    const row = owed.get(log.staffId) || { name: log.staffName || "A staff member", centavos: 0 };
    row.centavos += amount;
    owed.set(log.staffId, row);
  }
  const cashOwed = [...owed.values()].sort((a, b) => b.centavos - a.centavos);
  const onDuty = openShifts.map((s) => s.staffName || "A staff member");
  return {
    entries,
    exits,
    inside: Math.max(0, Number(inside) || 0),
    salesCentavos,
    walkInCashCentavos,
    overtimeUncollectedCentavos,
    cashOwed,
    onDuty,
    // Nothing scanned or sold: no push.
    quiet: entries === 0 && exits === 0 && salesCentavos === 0,
  };
}

function peso(centavos) {
  return `PHP ${(centavos / 100).toLocaleString("en-US", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
}

/** The push for [facilityName]'s day. */
function summaryMessage(facilityName, s) {
  const parts = [
    `${s.entries} entr${s.entries === 1 ? "y" : "ies"}, ${s.exits} exit${s.exits === 1 ? "" : "s"}, ${s.inside} still inside`,
    `${peso(s.salesCentavos)} sales`,
  ];
  if (s.walkInCashCentavos > 0) parts.push(`${peso(s.walkInCashCentavos)} walk-in cash`);
  if (s.overtimeUncollectedCentavos > 0) parts.push(`${peso(s.overtimeUncollectedCentavos)} overtime not collected`);
  for (const c of s.cashOwed.slice(0, 2)) parts.push(`${c.name} hasn't handed over ${peso(c.centavos)}`);
  if (s.cashOwed.length > 2) parts.push(`${s.cashOwed.length - 2} more with cash to hand over`);
  if (s.onDuty.length === 1) parts.push(`${s.onDuty[0]} is still clocked in`);
  if (s.onDuty.length > 1) parts.push(`${s.onDuty.length} staff still clocked in`);
  const needsStaff = s.cashOwed.length > 0 || s.onDuty.length > 0;
  return {
    title: `${facilityName || "Your facility"} — today`,
    body: parts.join(" · "),
    data: { kind: "owner_daily_summary", tab: needsStaff ? "staff" : "reports" },
  };
}

/** Reads one facility's day and builds its summary. */
async function facilityDay(db, facilityId, nowMs) {
  const dayKey = dayKeyManila(new Date(nowMs));
  const start = Timestamp.fromDate(dayStartManila(dayKey));
  const since = Timestamp.fromMillis(nowMs - CASH_LOOKBACK_DAYS * DAY_MS);
  const logs = db.collection("activity_logs").where("establishmentID", "==", facilityId);
  const [day, occupancy, splits, collected, walkIns, shifts] = await Promise.all([
    logs.where("timestamp", ">=", start).get(),
    db.collection("establishment_occupancy").doc(facilityId).get(),
    db.collection("payment_splits").where("establishmentId", "==", facilityId).where("createdAt", ">=", start).get(),
    logs.where("overtimeStatus", "==", "collected").get(),
    logs.where("walkInFee", ">", 0).get(),
    db.collection("staff_shifts").where("establishmentId", "==", facilityId).where("endedAt", "==", null).get(),
  ]);
  const recent = (d) => (d.data().timestamp?.toMillis?.() ?? nowMs) >= since.toMillis();
  const cashById = new Map();
  for (const d of [...collected.docs, ...walkIns.docs]) if (recent(d)) cashById.set(d.id, d.data());
  return summarizeOwnerDay({
    dayLogs: day.docs.map((d) => d.data()),
    inside: occupancy.data()?.total || 0,
    splits: splits.docs.map((d) => d.data()),
    cashLogs: [...cashById.values()],
    openShifts: shifts.docs.map((d) => d.data()),
  });
}

/** Hourly: sends today's summary to owners whose hour it is. */
async function sendOwnerDailySummaries(nowMs = Date.now()) {
  const db = getFirestore();
  const hour = manilaHour(nowMs);
  const dayKey = dayKeyManila(new Date(nowMs));
  const owners = await db.collection("users").where("role", "==", "Parking Owner").get();
  let sent = 0;
  for (const owner of owners.docs) {
    const prefs = dailySummaryPrefs(owner.data());
    if (!prefs.enabled || prefs.hour !== hour) continue;
    try {
      const sentRef = db.collection(SENT).doc(owner.id);
      if ((await sentRef.get()).data()?.lastSentDay === dayKey) continue;
      const facility = await db.collection("establishments").where("ownerId", "==", owner.id).limit(1).get();
      if (facility.empty) continue;
      const doc = facility.docs[0];
      const summary = await facilityDay(db, doc.id, nowMs);
      // Marked even on a quiet day, so a retry doesn't look again.
      await sentRef.set({ lastSentDay: dayKey, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      if (summary.quiet) continue;
      sent += await notifyUser(db, owner.id, summaryMessage(doc.data().name, summary));
    } catch (error) {
      logger.warn(`Daily summary for owner ${owner.id} failed`, error);
    }
  }
  logger.info(`Owner daily summaries: ${sent} sent at ${hour}:00 Manila.`);
  return sent;
}

module.exports = {
  DEFAULT_HOUR,
  dailySummaryPrefs,
  manilaHour,
  summarizeOwnerDay,
  summaryMessage,
  sendOwnerDailySummaries,
};
