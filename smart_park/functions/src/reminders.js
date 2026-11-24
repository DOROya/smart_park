// Push reminders for parked drivers. Paid time only counts down while a
// vehicle is inside, so a scheduled job checks parked tickets and sends:
//   - a reminder some minutes before the paid time ends (15, 30 or 60,
//     the driver's choice; 30 by default)
//   - an alert once overtime has started (after the facility's grace period)
// Each is sent at most once per visit. Drivers turn them off in Profile.
// It also warns drivers once when an unused temporary QR (gate pass) has
// PASS_EXPIRY_LEAD_MS left, so they don't reach the gate with a dead QR.
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

/**
 * A facility's daily hours as { open, close } in minutes after midnight, or
 * null when it is open all day or has none set (then it never closes).
 */
function facilityHours(establishment) {
  if (!establishment || establishment.open24Hours === true) return null;
  const parse = (value) => {
    const m = /^(\d{1,2}):(\d{2})$/.exec(String(value || "").trim());
    if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) return null;
    return Number(m[1]) * 60 + Number(m[2]);
  };
  const open = parse(establishment.openTime);
  const close = parse(establishment.closeTime);
  return open === null || close === null || open === close ? null : { open, close };
}

const MANILA_OFFSET_MS = 8 * HOUR_MS;
const LONGEST_CLOSED_CHECK_MS = 3 * 24 * HOUR_MS;

function isOpenAt(ms, hours) {
  const minute = Math.floor((ms + MANILA_OFFSET_MS) / MINUTE_MS) % (24 * 60);
  return hours.open < hours.close
    ? minute >= hours.open && minute < hours.close
    : minute >= hours.open || minute < hours.close;
}

/**
 * Minutes between two moments during which the facility was open. Overtime
 * does not run while it is closed (the driver can't leave then); mirrors
 * overtimeClock in lib/services/parking_pricing.dart.
 */
function openMinutesBetween(fromMs, toMs, hours) {
  if (toMs <= fromMs) return 0;
  if (!hours || toMs - fromMs > LONGEST_CLOSED_CHECK_MS) {
    return Math.floor((toMs - fromMs) / MINUTE_MS);
  }
  let open = 0;
  for (let t = fromMs; t < toMs; t += MINUTE_MS) {
    if (isOpenAt(t, hours)) open++;
  }
  return open;
}

/** Which notices are due for a parked ticket right now. */
function dueNotices(ticket, prefs, graceMinutes, nowMs, hours = null) {
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
  // Minutes of overtime so far, not counting time the facility was closed.
  const overMinutes = openMinutesBetween(until, nowMs, hours) - Math.max(0, graceMinutes);
  if (
    prefs.overtimeAlerts &&
    ticket.overtimeSentFor !== entry &&
    nowMs >= until &&
    overMinutes >= 0 &&
    overMinutes * MINUTE_MS < OVERTIME_ALERT_WINDOW_MS
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
        `(in ${minutes} min). Tap to add hours in the app, or overtime ` +
        "is charged at the exit.",
    };
  }
  return {
    title: "Overtime has started",
    body:
      `Your paid time at ${facility} ended at ${manilaTime(until)}. ` +
      "Overtime is now being charged and is paid in cash at the exit. " +
      "Tap to add hours and stop it.",
  };
}

const PASS_EXPIRY_LEAD_MS = 12 * HOUR_MS;

/** Whether an unused temporary QR should get its "expires soon" notice. */
function passExpiryDue(pass, prefs, nowMs) {
  const expiresAt = millis(pass.expiresAt);
  return (
    prefs.parkingReminders &&
    pass.status === "awaiting_gate" &&
    pass.expiryReminderSent !== true &&
    expiresAt !== null &&
    nowMs < expiresAt &&
    nowMs >= expiresAt - PASS_EXPIRY_LEAD_MS
  );
}

/** Title and body for the "temporary QR expires soon" notice. */
function passExpiryText(pass, nowMs) {
  const facility = pass.establishmentName || "the parking facility";
  const expiresAt = millis(pass.expiresAt);
  const hours = Math.max(1, Math.round((expiresAt - nowMs) / HOUR_MS));
  return {
    title: "Temporary QR expires soon",
    body:
      `Your unused QR for ${facility} expires at ${manilaTime(expiresAt)} ` +
      `(in about ${hours} h). Show it at the gate before then, or cancel ` +
      "it in Tickets if you no longer need it.",
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
  const hoursCache = new Map();
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
      if (!hoursCache.has(ticket.establishmentId)) {
        const e = await db.collection("establishments").doc(ticket.establishmentId).get();
        hoursCache.set(ticket.establishmentId, facilityHours(e.data()));
      }
      const due = dueNotices(
        ticket,
        prefsOf(user),
        graceCache.get(ticket.establishmentId),
        nowMs,
        hoursCache.get(ticket.establishmentId),
      );
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
  sent += await sendPassExpiryReminders(db, nowMs, userCache);
  if (sent) logger.info(`Sent ${sent} parking notifications.`);
}

/** Warns drivers whose unused temporary QR is about to expire. */
async function sendPassExpiryReminders(db, nowMs, userCache) {
  let sent = 0;
  let passes;
  try {
    // Two equality filters: served by single-field indexes, no composite.
    passes = await db
      .collection("parking_checkouts")
      .where("kind", "==", "gate_pass")
      .where("status", "==", "awaiting_gate")
      .get();
  } catch (error) {
    logger.warn("Temporary QR expiry check failed", error);
    return 0;
  }
  for (const doc of passes.docs) {
    const pass = doc.data();
    if (!pass.driverId) continue;
    try {
      if (!userCache.has(pass.driverId)) {
        const u = await db.collection("users").doc(pass.driverId).get();
        userCache.set(pass.driverId, u.data() || {});
      }
      const user = userCache.get(pass.driverId);
      if (!passExpiryDue(pass, prefsOf(user), nowMs)) continue;
      const tokens = Array.isArray(user.fcmTokens) ? user.fcmTokens.filter(Boolean) : [];
      const { title, body } = passExpiryText(pass, nowMs);
      sent += await sendToDriver(db, pass.driverId, tokens, {
        notification: { title, body },
        data: { checkoutId: doc.id, kind: "pass_expiry" },
        android: { priority: "high" },
      });
      // Marked even without a device, so a driver isn't told late.
      await doc.ref.update({ expiryReminderSent: true });
    } catch (error) {
      logger.warn(`Expiry reminder for temporary QR ${doc.id} failed`, error);
    }
  }
  return sent;
}

module.exports = {
  prefsOf,
  paidUntilMs,
  facilityHours,
  openMinutesBetween,
  dueNotices,
  noticeText,
  passExpiryDue,
  passExpiryText,
  PASS_EXPIRY_LEAD_MS,
  sendParkingReminders,
};
