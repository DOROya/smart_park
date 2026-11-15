// Push reminders for parked drivers. Paid time only counts down while a
// vehicle is inside, so a scheduled job checks parked tickets and sends:
//   - a reminder some minutes before the paid time ends (15, 30 or 60,
//     the driver's choice; 30 by default)
//   - an alert once overtime has started (after the facility's grace period)
// Each is sent at most once per visit. Drivers turn them off in Profile.
//
// users/{uid}: fcmTokens (device tokens), notificationPrefs
//   { parkingReminders: bool, leadMinutes: 15 | 30 | 60, overtimeAlerts: bool }

const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { logger } = require("firebase-functions");

const { hoursLeft } = require("./refunds");

const HOUR_MS = 60 * 60 * 1000;
const MINUTE_MS = 60 * 1000;
const DEFAULT_GRACE_MINUTES = 20;
const LEAD_CHOICES = [15, 30, 60];
/** Overtime alerts are not sent for stays that ran over long ago. */
const OVERTIME_ALERT_WINDOW_MS = 6 * HOUR_MS;

function millis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  return typeof value === "number" ? value : null;
}

/** The driver's choices, with defaults (everything on, 30 minutes). */
function prefsOf(user) {
  const p = user?.notificationPrefs || {};
  return {
    parkingReminders: p.parkingReminders !== false,
    leadMinutes: LEAD_CHOICES.includes(p.leadMinutes) ? p.leadMinutes : 30,
    overtimeAlerts: p.overtimeAlerts !== false,
  };
}

/** When the paid time of the current visit ends, or null if unknown. */
function paidUntilMs(ticket) {
  const entry = millis(ticket.entryAt);
  if (entry === null) return null;
  return entry + hoursLeft(ticket) * HOUR_MS;
}

/** Which notices are due for a parked ticket right now. */
function dueNotices(ticket, prefs, graceMinutes, nowMs) {
  const entry = millis(ticket.entryAt);
  const until = paidUntilMs(ticket);
  if (entry === null || until === null) return [];
  const due = [];
  if (
    prefs.parkingReminders &&
    ticket.reminderSentFor !== entry &&
    nowMs >= until - prefs.leadMinutes * MINUTE_MS &&
    nowMs < until
  ) {
    due.push("reminder");
  }
  const overtimeAt = until + Math.max(0, graceMinutes) * MINUTE_MS;
  if (
    prefs.overtimeAlerts &&
    ticket.overtimeSentFor !== entry &&
    nowMs >= overtimeAt &&
    nowMs - overtimeAt < OVERTIME_ALERT_WINDOW_MS
  ) {
    due.push("overtime");
  }
  return due;
}

function manilaTime(ms) {
  return new Date(ms).toLocaleTimeString("en-PH", {
    hour: "numeric",
    minute: "2-digit",
    timeZone: "Asia/Manila",
  });
}

/** Title and body for a notice. */
function noticeText(kind, ticket, nowMs) {
  const facility = ticket.establishmentName || "the parking facility";
  const until = paidUntilMs(ticket);
  if (kind === "reminder") {
    const minutes = Math.max(1, Math.round((until - nowMs) / MINUTE_MS));
    return {
      title: "Parking time almost up",
      body:
        `Your paid time at ${facility} ends at ${manilaTime(until)} ` +
        `(in ${minutes} min). After that, overtime is charged at the exit.`,
    };
  }
  return {
    title: "Overtime has started",
    body:
      `Your paid time at ${facility} ended at ${manilaTime(until)}. ` +
      "Overtime is now being charged and is paid in cash at the exit.",
  };
}

/** Sends to every device of a driver; drops tokens that no longer work. */
async function sendToDriver(db, driverId, tokens, message) {
  if (!tokens.length) return 0;
  const result = await getMessaging().sendEachForMulticast({ ...message, tokens });
  const dead = [];
  result.responses.forEach((r, i) => {
    const code = r.error?.code || "";
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token" ||
      code === "messaging/invalid-argument"
    ) {
      dead.push(tokens[i]);
    }
  });
  if (dead.length) {
    await db
      .collection("users")
      .doc(driverId)
      .update({ fcmTokens: FieldValue.arrayRemove(...dead) });
  }
  return result.successCount;
}

/** Scheduled: checks every parked ticket and sends what is due. */
async function sendParkingReminders() {
  const db = getFirestore();
  const nowMs = Date.now();
  const parked = await db
    .collection("transactions")
    .where("entryStatus", "==", "checked_in")
    .get();
  const graceCache = new Map();
  const userCache = new Map();
  let sent = 0;
  for (const doc of parked.docs) {
    const ticket = doc.data();
    // Walk-ins have no driver to tell.
    if (!ticket.driverId || ticket.source === "walk_in") continue;
    try {
      if (!userCache.has(ticket.driverId)) {
        const u = await db.collection("users").doc(ticket.driverId).get();
        userCache.set(ticket.driverId, u.data() || {});
      }
      const user = userCache.get(ticket.driverId);
      if (!graceCache.has(ticket.establishmentId)) {
        const d = await db.collection("establishment_details").doc(ticket.establishmentId).get();
        const g = Number(d.data()?.gracePeriodMinutes);
        graceCache.set(ticket.establishmentId, Number.isFinite(g) ? g : DEFAULT_GRACE_MINUTES);
      }
      const due = dueNotices(ticket, prefsOf(user), graceCache.get(ticket.establishmentId), nowMs);
      if (!due.length) continue;
      const tokens = Array.isArray(user.fcmTokens) ? user.fcmTokens.filter(Boolean) : [];
      const entry = millis(ticket.entryAt);
      const marks = {};
      for (const kind of due) {
        const { title, body } = noticeText(kind, ticket, nowMs);
        sent += await sendToDriver(db, ticket.driverId, tokens, {
          notification: { title, body },
          data: { ticketId: doc.id, kind },
          android: { priority: "high" },
        });
        marks[kind === "reminder" ? "reminderSentFor" : "overtimeSentFor"] = entry;
      }
      // Marked even without a device, so a driver isn't told late.
      await doc.ref.update(marks);
    } catch (error) {
      logger.warn(`Reminder for ticket ${doc.id} failed`, error);
    }
  }
  if (sent) logger.info(`Sent ${sent} parking notifications.`);
}

module.exports = {
  prefsOf,
  paidUntilMs,
  dueNotices,
  noticeText,
  sendParkingReminders,
};
