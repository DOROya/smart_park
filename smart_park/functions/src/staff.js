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
 * [code, message], or null when they may: only the owner who created the
 * staff member, and only while the account is active.
 */
function staffResetDenial(callerUid, record) {
  if (!record) return ["not-found", "Staff member not found."];
  if (!callerUid || record.ownerId !== callerUid) {
    return ["permission-denied", "You can only reset your own staff."];
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
  const denial = staffResetDenial(request.auth.uid, record);
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

module.exports = {
  staffSignInChange,
  applyStaffSignInChange,
  generateStaffPassword,
  staffResetDenial,
  resetStaffPassword,
};
