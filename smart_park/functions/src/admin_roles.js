// Admin access levels, managed in the app (docs/admin-roles.md).
//
// users/{uid}.role == "admin" is an administrator; adminLevel says which:
//   - "super": everything admins do, plus giving and taking admin access
//   - "admin" (or missing, for accounts made before levels existed): the rest
// Only a verified Driver can be promoted. Owners can't (they would review
// their own facility) and neither can gate staff. The promoted account's
// old role is kept in formerRole and restored when access is removed.
// At least one super admin always remains, and nobody changes their own
// access. Each change needs a fresh sign-in (the password asked again).
// All four fields are written only here; the rules keep them read-only.

const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");

const { notifyUser } = require("./notify");

const LEVELS = ["admin", "super"];
/**
 * The first super admin, who set SmartPark up. Super admins they promote
 * can't demote them or take their access away; only this account's own
 * profile in the Firestore console can change it.
 */
const FOUNDING_SUPER_ADMIN = "GWBK5QsdMNMHdPDjiPgrd7g3u3C2";
const FOUNDER_LOCKED = "The first super admin's access can't be changed.";
/** How recent the caller's password sign-in must be, in seconds. */
const FRESH_SIGN_IN_SECONDS = 5 * 60;

function roleOf(user) {
  return String(user?.role || user?.Role || user?.userRole || "").trim();
}

/** "super" or "admin" for an administrator, else "". */
function adminLevelOf(user) {
  if (roleOf(user) !== "admin") return "";
  return user?.adminLevel === "super" ? "super" : "admin";
}

function isSuperAdmin(user) {
  return adminLevelOf(user) === "super";
}

/** Whether the token's password sign-in is recent enough to change access. */
function signInIsFresh(token, nowSeconds) {
  const at = Number(token?.auth_time);
  return Number.isFinite(at) && nowSeconds - at <= FRESH_SIGN_IN_SECONDS;
}

/** Why [target] can't be promoted by [callerUid], as [code, message], or null. */
function promoteDenial(callerUid, targetUid, target, level) {
  if (!LEVELS.includes(level)) return ["invalid-argument", "Pick Admin or Super admin."];
  if (!target) return ["not-found", "User not found."];
  if (targetUid === callerUid) return ["failed-precondition", "You can't change your own access."];
  const role = roleOf(target);
  if (role === "admin") return ["failed-precondition", "This account is already an admin."];
  if (role === "Parking Owner") {
    return ["failed-precondition", "Parking owners can't be admins: they would review their own facility."];
  }
  if (role !== "Driver") return ["failed-precondition", "Only driver accounts can be made admins."];
  return null;
}

/**
 * Why [target]'s level can't be set to [level], or null. [superCount] is
 * how many super admins there are now.
 */
function levelDenial(callerUid, targetUid, target, level, superCount) {
  if (!LEVELS.includes(level)) return ["invalid-argument", "Pick Admin or Super admin."];
  if (!target || roleOf(target) !== "admin") return ["not-found", "This account is not an admin."];
  if (targetUid === callerUid) return ["failed-precondition", "You can't change your own access."];
  if (targetUid === FOUNDING_SUPER_ADMIN) return ["permission-denied", FOUNDER_LOCKED];
  if (adminLevelOf(target) === level) return ["failed-precondition", "Nothing to change."];
  if (level === "admin" && superCount <= 1) {
    return ["failed-precondition", "SmartPark needs at least one super admin."];
  }
  return null;
}

/** Why [target]'s admin access can't be removed, or null. */
function removeDenial(callerUid, targetUid, target) {
  if (!target || roleOf(target) !== "admin") return ["not-found", "This account is not an admin."];
  if (targetUid === callerUid) return ["failed-precondition", "You can't remove your own access."];
  if (targetUid === FOUNDING_SUPER_ADMIN) return ["permission-denied", FOUNDER_LOCKED];
  if (isSuperAdmin(target)) {
    return ["failed-precondition", "Make this super admin a normal admin first, then remove access."];
  }
  return null;
}

async function emailVerified(uid) {
  const { getAuth } = require("firebase-admin/auth");
  try {
    return (await getAuth().getUser(uid)).emailVerified === true;
  } catch (_) {
    return false;
  }
}

function deny(denial) {
  if (denial) throw new HttpsError(denial[0], denial[1]);
}

/** The caller, who must be a super admin with a fresh sign-in. */
async function requireSuperAdmin(db, request, { fresh = true } = {}) {
  const auth = request.auth;
  if (!auth?.uid) throw new HttpsError("unauthenticated", "Please sign in again.");
  const caller = (await db.collection("users").doc(auth.uid).get()).data();
  if (!isSuperAdmin(caller)) {
    throw new HttpsError("permission-denied", "Only a super admin can change admin access.");
  }
  if (fresh && !signInIsFresh(auth.token, Math.floor(Date.now() / 1000))) {
    throw new HttpsError("unauthenticated", "Enter your password again to change admin access.");
  }
  return auth.uid;
}

function targetUidOf(request) {
  const uid = String(request.data?.uid || "").trim();
  if (!uid) throw new HttpsError("invalid-argument", "Missing user.");
  return uid;
}

const LEVEL_NAMES = { super: "super admin", admin: "admin" };

/** "an admin", "a super admin". */
function withArticle(name) {
  return `${/^[aeiou]/i.test(name) ? "an" : "a"} ${name}`;
}

/** Super admin: makes a verified driver an admin or super admin. */
async function promoteToAdmin(request) {
  const db = getFirestore();
  const callerUid = await requireSuperAdmin(db, request);
  const uid = targetUidOf(request);
  const level = String(request.data?.level || "admin");
  // Auth isn't Firestore, so this is checked before the transaction.
  if (!(await emailVerified(uid))) {
    throw new HttpsError("failed-precondition", "This account hasn't verified its email.");
  }
  const ref = db.collection("users").doc(uid);
  let before;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    before = snap.data();
    deny(promoteDenial(callerUid, uid, snap.exists ? before : null, level));
    const staff = await tx.get(db.collection("staff_accounts").doc(uid));
    if (staff.exists) deny(["failed-precondition", "Gate staff accounts can't be made admins."]);
    tx.update(ref, {
      role: "admin",
      adminLevel: level,
      formerRole: roleOf(before),
      adminSince: FieldValue.serverTimestamp(),
      promotedBy: callerUid,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  await notifyUser(db, uid, {
    title: "You now have admin access",
    body: `You were made ${withArticle(`SmartPark ${LEVEL_NAMES[level]}`)}. Open the app to see the admin dashboard.`,
    data: { kind: "admin_access" },
  });
  return { uid, role: "admin", adminLevel: level, formerRole: roleOf(before) };
}

/** Super admin: switches an admin between "admin" and "super". */
async function setAdminLevel(request) {
  const db = getFirestore();
  const callerUid = await requireSuperAdmin(db, request);
  const uid = targetUidOf(request);
  const level = String(request.data?.level || "");
  const ref = db.collection("users").doc(uid);
  let from = "";
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    // Read in the transaction, so two demotions at once can't leave none.
    const supers = await tx.get(
      db.collection("users").where("role", "==", "admin").where("adminLevel", "==", "super"),
    );
    from = adminLevelOf(snap.data());
    deny(levelDenial(callerUid, uid, snap.exists ? snap.data() : null, level, supers.size));
    tx.update(ref, { adminLevel: level, updatedAt: FieldValue.serverTimestamp() });
  });
  await notifyUser(db, uid, {
    title: "Your admin access changed",
    body: `You are now ${withArticle(`SmartPark ${LEVEL_NAMES[level]}`)}.`,
    data: { kind: "admin_access" },
  });
  return { uid, from, adminLevel: level };
}

/** Super admin: takes a normal admin's access away, restoring their old role. */
async function removeAdminAccess(request) {
  const db = getFirestore();
  const callerUid = await requireSuperAdmin(db, request);
  const uid = targetUidOf(request);
  const ref = db.collection("users").doc(uid);
  let restored = "Driver";
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    deny(removeDenial(callerUid, uid, snap.exists ? snap.data() : null));
    const former = String(snap.data().formerRole || "").trim();
    // Admins made by hand before levels existed have no formerRole; they
    // registered as drivers (owners were never made admins).
    restored = former && former !== "admin" ? former : "Driver";
    tx.update(ref, {
      role: restored,
      adminLevel: FieldValue.delete(),
      adminSince: FieldValue.delete(),
      promotedBy: FieldValue.delete(),
      formerRole: FieldValue.delete(),
      adminRemovedAt: FieldValue.serverTimestamp(),
      adminRemovedBy: callerUid,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  await notifyUser(db, uid, {
    title: "Your admin access was removed",
    body: `Your SmartPark account is ${withArticle(restored)} account again.`,
    data: { kind: "admin_access" },
  });
  return { uid, role: restored };
}

/**
 * Super admin, before promoting: what the account is and what it holds, for
 * the confirmation dialog. No fresh sign-in needed; it changes nothing.
 */
async function getAdminCandidate(request) {
  const db = getFirestore();
  await requireSuperAdmin(db, request, { fresh: false });
  const uid = targetUidOf(request);
  const [profile, staff, tickets, passes] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("staff_accounts").doc(uid).get(),
    db.collection("transactions").where("driverId", "==", uid).where("status", "==", "paid").get(),
    db
      .collection("parking_checkouts")
      .where("driverId", "==", uid)
      .where("kind", "==", "gate_pass")
      .where("status", "==", "awaiting_gate")
      .get(),
  ]);
  const { hoursLeft } = require("./refunds");
  return {
    role: staff.exists ? "staff" : roleOf(profile.data()),
    emailVerified: await emailVerified(uid),
    activeTickets: tickets.docs.filter((d) => hoursLeft(d.data()) > 0).length,
    unusedPasses: passes.size,
  };
}

/** Audit entry for a change; [result] is what the callable returned. */
async function auditEntry(db, action, request, result) {
  const { resolveActor } = require("./audit");
  const target = await resolveActor(db, result?.uid || "");
  const summaries = {
    "admin.promoted": `Made ${target.actorName} ${withArticle(LEVEL_NAMES[result?.adminLevel] || "admin")}`,
    "admin.level_changed": `Changed ${target.actorName} to ${withArticle(LEVEL_NAMES[result?.adminLevel] || "admin")}`,
    "admin.removed": `Removed ${target.actorName}'s admin access`,
  };
  const changes = {
    "admin.promoted": {
      role: { from: result?.formerRole || "", to: "admin" },
      adminLevel: { from: null, to: result?.adminLevel || "" },
    },
    "admin.level_changed": { adminLevel: { from: result?.from || "", to: result?.adminLevel || "" } },
    "admin.removed": { role: { from: "admin", to: result?.role || "" } },
  };
  return {
    action,
    summary: summaries[action],
    targetType: "user",
    targetId: result?.uid || "",
    // Admin-only entries: no owner sees them.
    ownerId: "",
    changes: changes[action],
  };
}

module.exports = {
  withArticle,
  LEVELS,
  FOUNDING_SUPER_ADMIN,
  FRESH_SIGN_IN_SECONDS,
  adminLevelOf,
  isSuperAdmin,
  signInIsFresh,
  promoteDenial,
  levelDenial,
  removeDenial,
  requireSuperAdmin,
  promoteToAdmin,
  setAdminLevel,
  removeAdminAccess,
  getAdminCandidate,
  auditEntry,
};
