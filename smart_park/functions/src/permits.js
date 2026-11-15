// Business permits lapse every year. Owners give the expiry date with their
// documents (establishment_private/{id}.permitExpiresAt); this reminds them
// before it passes, so a lapsed permit is never a surprise to either side.

const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions");

const { notifyUser } = require("./notify");

const DAY_MS = 24 * 60 * 60 * 1000;
const REMIND_DAYS_BEFORE = 30;

function millis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  return typeof value === "number" ? value : null;
}

/**
 * Which reminder a permit is due right now: "soon" within 30 days of
 * expiry, "expired" once past it, or null. Each is sent once per expiry
 * date ([sentFor] is `${expiry}:${kind}` of the last one sent).
 */
function permitNotice(expiresAt, sentFor, nowMs) {
  const expiry = millis(expiresAt);
  if (expiry === null) return null;
  const kind =
    nowMs >= expiry ? "expired" : expiry - nowMs <= REMIND_DAYS_BEFORE * DAY_MS ? "soon" : null;
  if (!kind || sentFor === `${expiry}:${kind}`) return null;
  return kind;
}

function manilaDate(ms) {
  return new Date(ms).toLocaleDateString("en-PH", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "Asia/Manila",
  });
}

/** Daily: reminds owners whose permit expires within 30 days or has expired. */
async function remindExpiringPermits() {
  const db = getFirestore();
  const nowMs = Date.now();
  const due = await db
    .collection("establishment_private")
    .where("permitExpiresAt", "<=", Timestamp.fromMillis(nowMs + REMIND_DAYS_BEFORE * DAY_MS))
    .get();
  for (const doc of due.docs) {
    try {
      const data = doc.data();
      const kind = permitNotice(data.permitExpiresAt, data.permitNoticeSentFor, nowMs);
      if (!kind) continue;
      const base = (await db.collection("establishments").doc(doc.id).get()).data() || {};
      const expiry = millis(data.permitExpiresAt);
      await notifyUser(db, base.ownerId, {
        title: kind === "expired" ? "Business permit expired" : "Business permit expiring soon",
        body:
          kind === "expired"
            ? `The permit for ${base.name || "your facility"} expired on ${manilaDate(expiry)}. ` +
              "Upload the renewed permit to keep your facility listed."
            : `The permit for ${base.name || "your facility"} expires on ${manilaDate(expiry)}. ` +
              "Upload the renewed permit and its new expiry date before then.",
        data: { establishmentId: doc.id, kind: `permit_${kind}` },
      });
      await doc.ref.update({ permitNoticeSentFor: `${expiry}:${kind}` });
    } catch (error) {
      logger.warn(`Permit reminder for ${doc.id} failed`, error);
    }
  }
}

/**
 * Whether the notice on [after] is one the owner has not been told about:
 * newly issued, or issued again with a new date.
 */
function isNewComplianceNotice(before, after) {
  const notice = after?.complianceNotice;
  if (!notice) return false;
  const previous = before?.complianceNotice;
  return !previous || millis(previous.issuedAt) !== millis(notice.issuedAt);
}

/**
 * Trigger on establishment_details: tells the owner when an admin gives
 * them notice to fix something before a suspension.
 */
async function notifyComplianceNotice(establishmentId, before, after) {
  if (!isNewComplianceNotice(before, after)) return;
  const notice = after.complianceNotice;
  const db = getFirestore();
  const base = (await db.collection("establishments").doc(establishmentId).get()).data() || {};
  const reasons = Array.isArray(notice.reasons) ? notice.reasons.join(", ") : "";
  await notifyUser(db, base.ownerId, {
    title: "Notice from SmartPark",
    body:
      `${base.name || "Your facility"} must fix this by ${manilaDate(millis(notice.dueAt))}` +
      `${reasons ? `: ${reasons}` : ""}. It may be suspended if it is not fixed.`,
    data: { establishmentId, kind: "compliance_notice" },
  });
}

module.exports = {
  REMIND_DAYS_BEFORE,
  permitNotice,
  remindExpiringPermits,
  isNewComplianceNotice,
  notifyComplianceNotice,
};
