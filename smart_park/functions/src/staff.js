// Owners deactivate staff by setting staff_accounts/{uid}.active = false
// (the record is kept so past gate scans still show a name). Security rules
// already block a deactivated account at the gate; this also disables its
// Firebase Auth sign-in, which the owner's app cannot do itself.

const { getAuth } = require("firebase-admin/auth");

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

module.exports = { staffSignInChange, applyStaffSignInChange };
