// Owners deactivate staff by setting staff_accounts/{uid}.active = false
// (the record is kept so past gate scans still show a name). Security rules
// already block a deactivated account at the gate; this also disables its
// Firebase Auth sign-in, which the owner's app cannot do itself.

const { randomInt } = require("node:crypto");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");

function isActive(record) {
  return record.active !== false;
}

/**
 * What to do to the staff sign-in after its record changed:
 * { uid, disabled } or null for no change. A deleted record is left alone:
 * the owner app moves legacy random-id records to uid-keyed ones by
 * copy-then-delete, which must not lock the staff member out.
 */
function staffSignInChange(docId, before, after) {
  if (!after) return null;
  const uid = String(after.userId || docId || "").trim();
  if (!uid) return null;
  const wasActive = before ? isActive(before) : true;
  const nowActive = isActive(after);
  if (wasActive === nowActive) return null;
  return { uid, disabled: !nowActive };
}

async function applyStaffSignInChange(change) {
  if (!change) return;
  const auth = getAuth();
  try {
    await auth.updateUser(change.uid, { disabled: change.disabled });
  } catch (error) {
    // The sign-in may already be gone (deleted in the console).
    if (error.code === "auth/user-not-found") return;
    throw error;
  }
  if (change.disabled) {
    // Ends existing sessions within the hour instead of when they sign out.
    await auth.revokeRefreshTokens(change.uid);
  }
}

// Same alphabet as the owner app's generated staff passwords (no 0/O, 1/l/I).
const PASSWORD_ALPHABET =
  "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#";

function generateStaffPassword(length = 10, pick = randomInt) {
  let password = "";
  for (let i = 0; i < length; i++) {
    password += PASSWORD_ALPHABET[pick(PASSWORD_ALPHABET.length)];
  }
  return password;
}

/**
 * Why [callerUid] may not reset the password on this staff record, as
 * [code, message], or null when they may: the owner who created the staff
 * member, or an active supervisor of the same facility for gate staff
 * (never another supervisor), and only while the account is active.
 * [caller] is the caller's own staff record, if they have one.
 */
function staffResetDenial(callerUid, record, caller = null) {
  if (!record) return ["not-found", "Staff member not found."];
  const supervisor =
    caller?.role === "supervisor" &&
    isActive(caller) &&
    Boolean(caller.facilityId) &&
    caller.facilityId === record.facilityId;
  if (!callerUid || (record.ownerId !== callerUid && !supervisor)) {
    return ["permission-denied", "You can only reset your own staff."];
  }
  if (record.ownerId !== callerUid && (record.role === "supervisor" || callerUid === record.userId)) {
    return ["permission-denied", "Only the owner can reset a supervisor's password."];
  }
  if (!isActive(record)) {
    return [
      "failed-precondition",
      "Reactivate this staff member before resetting their password.",
    ];
  }
  return null;
}

/**
 * Owner-only emergency reset: gives an active staff member a new random
 * password and signs out every session on the old one. Staff sign in with a
 * username on a fake email domain, so an email reset link can't reach them.
 * Returns the new password once; it is not stored.
 */
async function resetStaffPassword(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Please sign in again.");
  }
  const staffId = String(request.data?.staffId || "").trim();
  if (!staffId) {
    throw new HttpsError("invalid-argument", "Missing staff member.");
  }

  const ref = getFirestore().collection("staff_accounts").doc(staffId);
  const record = (await ref.get()).data();
  const caller = (await getFirestore().collection("staff_accounts").doc(request.auth.uid).get()).data();
  const denial = staffResetDenial(request.auth.uid, record, caller);
  if (denial) throw new HttpsError(denial[0], denial[1]);

  const uid = String(record.userId || staffId).trim();
  const password = generateStaffPassword();
  const auth = getAuth();
  try {
    await auth.updateUser(uid, { password });
  } catch (error) {
    if (error.code === "auth/user-not-found") {
      throw new HttpsError("not-found", "This staff sign-in no longer exists.");
    }
    throw error;
  }
  await auth.revokeRefreshTokens(uid);
  await ref.update({
    passwordResetAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { username: String(record.username || ""), password };
}

const MAX_NAME_PART = 50;

/**
 * The new name a supervisor asked for, as { firstName, lastName, name }, or
 * [code, message] when it can't be used. Only an active supervisor renames
 * themselves here: gate staff have no Profile, and owners edit users/ directly.
 */
function supervisorRename(record, data) {
  if (!record || record.role !== "supervisor" || !isActive(record)) {
    return ["permission-denied", "Only an active supervisor can change their name here."];
  }
  const firstName = String(data?.firstName || "").replace(/\s+/g, " ").trim();
  const lastName = String(data?.lastName || "").replace(/\s+/g, " ").trim();
  if (!firstName || !lastName) {
    return ["invalid-argument", "Please enter your first and last name."];
  }
  if (firstName.length > MAX_NAME_PART || lastName.length > MAX_NAME_PART) {
    return ["invalid-argument", "That name is too long."];
  }
  return { firstName, lastName, name: `${firstName} ${lastName}` };
}

/**
 * A supervisor's Profile name change. Their staff record holds the name the
 * owner, staff list and gate scans show, but the rules don't let them write
 * it, so both it and their profile are updated here. Returns the old and
 * new names for the owner's Change History.
 */
async function renameSupervisor(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Please sign in again.");
  }
  const uid = request.auth.uid;
  const db = getFirestore();
  const staffRef = db.collection("staff_accounts").doc(uid);
  const record = (await staffRef.get()).data();
  const result = supervisorRename(record, request.data);
  if (Array.isArray(result)) throw new HttpsError(result[0], result[1]);

  const oldName = String(record.name || "").trim();
  const batch = db.batch();
  batch.set(
    db.collection("users").doc(uid),
    { firstName: result.firstName, lastName: result.lastName, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  batch.update(staffRef, { name: result.name, updatedAt: FieldValue.serverTimestamp() });
  await batch.commit();
  return {
    oldName,
    newName: result.name,
    facilityId: String(record.facilityId || ""),
    ownerId: String(record.ownerId || ""),
  };
}

module.exports = {
  supervisorRename,
  renameSupervisor,
  staffSignInChange,
  applyStaffSignInChange,
  generateStaffPassword,
  staffResetDenial,
  resetStaffPassword,
};
