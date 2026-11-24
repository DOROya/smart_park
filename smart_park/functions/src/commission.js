// The platform commission, set by a super admin with notice to owners
// (docs/quick-fixes.md item 4). settings/platform holds the current rate and
// at most one scheduled change; only this module writes it.
//
// The rate is fixed when a price is: a temporary QR or extra hours save the
// rate in force on their checkout (commissionRate), and the ticket, payment
// split and any refund use that saved rate, never a later one. So nothing
// already shown to a driver or owner is charged at a new rate, and pricing
// doesn't depend on the daily job that tidies a change that took effect.

const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");

const { PLATFORM_FEE_RATE } = require("./pricing");

const SETTINGS = "settings";
const PLATFORM_DOC = "platform";
const MIN_RATE = 0.01;
const MAX_RATE = 0.15;
/** A higher rate needs this much notice; a lower one only a day. */
const MIN_NOTICE_DAYS = 30;
const LOWER_NOTICE_DAYS = 1;
const DAY_MS = 24 * 60 * 60 * 1000;

function millis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  return typeof value === "number" ? value : null;
}

function validRate(rate) {
  return typeof rate === "number" && Number.isFinite(rate) && rate >= MIN_RATE && rate <= MAX_RATE;
}

/** The rate in force at [nowMs] under [settings] (settings/platform). */
function commissionRateAt(settings, nowMs) {
  const pending = settings?.pendingRate;
  const at = millis(settings?.pendingEffectiveAt);
  if (validRate(pending) && at !== null && nowMs >= at) return pending;
  return validRate(settings?.commissionRate) ? settings.commissionRate : PLATFORM_FEE_RATE;
}

/** The rate in force now, read from Firestore. */
async function loadCommissionRate(db = getFirestore(), nowMs = Date.now()) {
  const snap = await db.collection(SETTINGS).doc(PLATFORM_DOC).get();
  return commissionRateAt(snap.data(), nowMs);
}

/** "5%" or "7.5%". */
function percent(rate) {
  const p = Math.round(rate * 1000) / 10;
  return `${Number.isInteger(p) ? p : p.toFixed(1)}%`;
}

/**
 * Why [rate] from [effectiveAtMs] can't be scheduled now, as [code,
 * message], or null. [current] is the rate in force.
 */
function scheduleDenial(current, rate, effectiveAtMs, nowMs, minNoticeDays = MIN_NOTICE_DAYS) {
  if (!validRate(rate)) {
    return ["invalid-argument", `Pick a rate from ${percent(MIN_RATE)} to ${percent(MAX_RATE)}.`];
  }
  if (Math.abs(rate - current) < 1e-9) return ["invalid-argument", "That is already the rate."];
  if (!Number.isFinite(effectiveAtMs)) return ["invalid-argument", "Pick when it takes effect."];
  const days = rate > current ? minNoticeDays : LOWER_NOTICE_DAYS;
  if (effectiveAtMs < nowMs + days * DAY_MS) {
    return [
      "failed-precondition",
      rate > current
        ? `Owners must be told at least ${days} days before a higher rate takes effect.`
        : "A lower rate can take effect from tomorrow at the earliest.",
    ];
  }
  return null;
}

/** The owner announcement for a scheduled change. */
function changeAnnouncement({ oldRate, newRate, effectiveAtMs, message, createdBy }) {
  const date = new Date(effectiveAtMs).toLocaleDateString("en-US", {
    timeZone: "Asia/Manila",
    month: "short",
    day: "numeric",
    year: "numeric",
  });
  const example = (r) => `PHP ${(100 * r).toFixed(2)}`;
  const note = String(message || "").trim().slice(0, 500);
  return {
    audience: "owners",
    kind: "commission_change",
    title: `SmartPark commission changes to ${percent(newRate)} on ${date}`,
    body:
      `From ${date}, SmartPark's commission on payments made in the app changes from ` +
      `${percent(oldRate)} to ${percent(newRate)}. On a PHP 100 sale, SmartPark keeps ` +
      `${example(oldRate)} now and ${example(newRate)} from ${date}. Anything bought before ` +
      "then keeps the old rate." +
      (note ? `\n\n${note}` : ""),
    oldRate,
    newRate,
    effectiveAt: Timestamp.fromMillis(effectiveAtMs),
    createdBy,
    createdAt: FieldValue.serverTimestamp(),
  };
}

async function requireSuper(db, request) {
  const { requireSuperAdmin } = require("./admin_roles");
  return requireSuperAdmin(db, request, { fresh: false });
}

/** Super admin: schedules a new rate and tells owners. */
async function scheduleCommissionChange(request) {
  const db = getFirestore();
  const uid = await requireSuper(db, request);
  const rate = Number(request.data?.rate);
  const effectiveAtMs = Number(request.data?.effectiveAt);
  const ref = db.collection(SETTINGS).doc(PLATFORM_DOC);
  const announcementRef = db.collection("announcements").doc();
  const nowMs = Date.now();
  const result = await db.runTransaction(async (tx) => {
    const settings = (await tx.get(ref)).data() || {};
    const current = commissionRateAt(settings, nowMs);
    const denial = scheduleDenial(current, rate, effectiveAtMs, nowMs, settings.minNoticeDays || MIN_NOTICE_DAYS);
    if (denial) throw new HttpsError(denial[0], denial[1]);
    tx.set(
      ref,
      {
        // A change already in force becomes the current rate first.
        commissionRate: current,
        pendingRate: rate,
        pendingEffectiveAt: Timestamp.fromMillis(effectiveAtMs),
        pendingAnnouncementId: announcementRef.id,
        minNoticeDays: settings.minNoticeDays || MIN_NOTICE_DAYS,
        updatedBy: uid,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.set(
      announcementRef,
      changeAnnouncement({ oldRate: current, newRate: rate, effectiveAtMs, message: request.data?.message, createdBy: uid }),
    );
    return { oldRate: current, newRate: rate, effectiveAt: effectiveAtMs, announcementId: announcementRef.id };
  });
  await pushAnnouncement(db, result.announcementId);
  return result;
}

/** Super admin: calls off a scheduled change and tells owners. */
async function cancelCommissionChange(request) {
  const db = getFirestore();
  const uid = await requireSuper(db, request);
  const ref = db.collection(SETTINGS).doc(PLATFORM_DOC);
  const announcementRef = db.collection("announcements").doc();
  const nowMs = Date.now();
  const result = await db.runTransaction(async (tx) => {
    const settings = (await tx.get(ref)).data() || {};
    const at = millis(settings.pendingEffectiveAt);
    if (!validRate(settings.pendingRate) || at === null || at <= nowMs) {
      throw new HttpsError("failed-precondition", "No change is waiting to take effect.");
    }
    const current = commissionRateAt(settings, nowMs);
    tx.update(ref, {
      pendingRate: null,
      pendingEffectiveAt: null,
      pendingAnnouncementId: null,
      updatedBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(announcementRef, {
      audience: "owners",
      kind: "general",
      title: "Commission change called off",
      body: `The change to ${percent(settings.pendingRate)} will not happen. SmartPark's commission stays at ${percent(current)}.`,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { cancelledRate: settings.pendingRate, rate: current, announcementId: announcementRef.id };
  });
  await pushAnnouncement(db, result.announcementId);
  return result;
}

/**
 * Daily: a change whose date has passed becomes the current rate. Pricing
 * already uses it from that moment (commissionRateAt); this keeps the
 * document tidy and records it in the audit log.
 */
async function applyPendingCommission(db = getFirestore(), nowMs = Date.now()) {
  const ref = db.collection(SETTINGS).doc(PLATFORM_DOC);
  const applied = await db.runTransaction(async (tx) => {
    const settings = (await tx.get(ref)).data() || {};
    const at = millis(settings.pendingEffectiveAt);
    if (!validRate(settings.pendingRate) || at === null || at > nowMs) return null;
    tx.update(ref, {
      commissionRate: settings.pendingRate,
      pendingRate: null,
      pendingEffectiveAt: null,
      pendingAnnouncementId: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { from: commissionRateAt({ commissionRate: settings.commissionRate }, nowMs), to: settings.pendingRate };
  });
  if (applied) {
    const { record } = require("./audit");
    await record(db, {
      actorId: "",
      actorName: "SmartPark",
      actorRole: "system",
      action: "platform.commission_changed",
      summary: `Commission is now ${percent(applied.to)} (was ${percent(applied.from)})`,
      targetType: "platform",
      targetId: PLATFORM_DOC,
      ownerId: "",
      changes: { commissionRate: { from: applied.from, to: applied.to } },
    });
  }
  return applied;
}

/** Sends an announcement to its audience's phones. */
async function pushAnnouncement(db, announcementId) {
  const { notifyUser } = require("./notify");
  const snap = await db.collection("announcements").doc(announcementId).get();
  const a = snap.data();
  if (!a) return 0;
  const roles = { owners: ["Parking Owner"], drivers: ["Driver"], staff: ["staff", "supervisor"] }[a.audience];
  const users = roles
    ? await db.collection("users").where("role", "in", roles).get()
    : await db.collection("users").where("role", "in", ["Parking Owner", "Driver", "staff", "supervisor"]).get();
  let sent = 0;
  for (const doc of users.docs) {
    sent += await notifyUser(db, doc.id, {
      title: a.title,
      body: String(a.body || "").split("\n")[0],
      data: { kind: "announcement", announcementId },
    });
  }
  return sent;
}

module.exports = {
  SETTINGS,
  PLATFORM_DOC,
  MIN_RATE,
  MAX_RATE,
  MIN_NOTICE_DAYS,
  commissionRateAt,
  loadCommissionRate,
  percent,
  scheduleDenial,
  changeAnnouncement,
  scheduleCommissionChange,
  cancelCommissionChange,
  applyPendingCommission,
  pushAnnouncement,
};
