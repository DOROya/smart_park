// Account deletion, asked for from the Profile. The sign-in and the personal
// details go; payment, ticket and gate records stay without the name, as the
// Privacy Notice says. Nothing is deleted while it would strand someone:
// a parked vehicle, a refund on its way, or drivers holding unused hours.

const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

const { hoursLeft, isProbablyGone } = require("./refunds");

const DELETED_NAME = "Deleted user";
const REFUNDS_IN_FLIGHT = ["approved", "processing", "sent", "awaiting_exit"];

function isParked(ticket) {
  const entry = String(ticket.entryStatus || "").toLowerCase();
  return entry === "checked_in" || entry === "inside";
}

/**
 * Why a driver's account can't be deleted yet, or null when it can.
 * [tickets], [refunds] and [passes] are the driver's own records.
 */
function driverDeletionDenial({ tickets, refunds, passes }, nowMs = Date.now()) {
  // A stay long past its paid time whose exit was never scanned doesn't
  // keep the driver from leaving SmartPark.
  if (tickets.some((t) => isParked(t) && !isProbablyGone(t, nowMs))) {
    return "Your vehicle is still parked. Exit the facility first.";
  }
  if (refunds.some((r) => REFUNDS_IN_FLIGHT.includes(r.status))) {
    return "A refund is still on its way to you. Try again once it has arrived.";
  }
  if (passes.some((p) => p.status === "pending")) {
    return "A payment is in progress at the gate. Finish or cancel it first.";
  }
  return null;
}

/**
 * Why an owner's account can't be deleted yet, or null when it can.
 * [tickets] are every ticket at their facilities; [balance] is their
 * owner_refund_balances record.
 */
function ownerDeletionDenial({ tickets, balance }) {
  if (tickets.some(isParked)) {
    return (
      "Vehicles are still marked as parked at your facility. Wait until they " +
      "have exited. If one already left without an exit scan, record it with " +
      "Record missed exit on the Overtime card."
    );
  }
  const stranded = tickets.some(
    (t) => t.status === "paid" && t.source !== "walk_in" && hoursLeft(t) > 0,
  );
  if (stranded) {
    return (
      "Drivers still hold tickets with unused hours at your facility. " +
      "Email SmartPark to close the facility, so they are refunded first."
    );
  }
  const owed = (balance?.owedCentavos || 0) + (balance?.reservedCentavos || 0);
  if (owed > 0) {
    return "You still have a refund balance to pay. Settle it before deleting your account.";
  }
  return null;
}

/** What is left of a profile once its account is deleted. */
function deletedProfile(role) {
  return {
    role,
    firstName: "Deleted",
    lastName: "user",
    deleted: true,
    deletedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function deleteDriver(db, uid) {
  const [tickets, refunds, passes, warnings, reports] = await Promise.all([
    db.collection("transactions").where("driverId", "==", uid).get(),
    db.collection("refunds").where("driverId", "==", uid).get(),
    db.collection("parking_checkouts").where("driverId", "==", uid).get(),
    db.collection("driver_warnings").where("driverId", "==", uid).get(),
    db.collection("driver_reports").where("driverId", "==", uid).get(),
  ]);
  const denial = driverDeletionDenial({
    tickets: tickets.docs.map((d) => d.data()),
    refunds: refunds.docs.map((d) => d.data()),
    passes: passes.docs.map((d) => d.data()),
  });
  if (denial) throw new HttpsError("failed-precondition", denial);

  const writer = db.bulkWriter();
  for (const doc of tickets.docs) {
    // The record stays for the facility's books; the name and the unused
    // hours (given up with the account) do not.
    writer.update(doc.ref, {
      driverName: DELETED_NAME,
      driverEmail: FieldValue.delete(),
      remainingHours: 0,
      accountDeleted: true,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  for (const doc of passes.docs) {
    if (doc.data().status === "awaiting_gate") {
      writer.update(doc.ref, { status: "cancelled", updatedAt: FieldValue.serverTimestamp() });
    }
  }
  for (const doc of refunds.docs) {
    if (doc.data().status === "requested") {
      writer.update(doc.ref, {
        status: "rejected",
        decidedBy: "system",
        decisionNote: "The driver deleted their account.",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  }
  for (const doc of warnings.docs) writer.delete(doc.ref);
  for (const doc of reports.docs) writer.update(doc.ref, { driverName: DELETED_NAME });
  await writer.close();
}

async function deleteOwner(db, uid) {
  const facilities = await db.collection("establishments").where("ownerId", "==", uid).get();
  const tickets = [];
  for (const facility of facilities.docs) {
    const snap = await db
      .collection("transactions")
      .where("establishmentId", "==", facility.id)
      .get();
    tickets.push(...snap.docs.map((d) => d.data()));
  }
  const balance = (await db.collection("owner_refund_balances").doc(uid).get()).data();
  const denial = ownerDeletionDenial({ tickets, balance });
  if (denial) throw new HttpsError("failed-precondition", denial);

  const staff = await db.collection("staff_accounts").where("ownerId", "==", uid).get();
  const writer = db.bulkWriter();
  for (const facility of facilities.docs) {
    // Deactivated, not removed: past tickets and reports still point at it.
    writer.set(
      db.collection("establishment_details").doc(facility.id),
      {
        status: "deactivated",
        restrictionReasons: ["Requested by the owner"],
        restrictionReason: "Requested by the owner",
        ownerDeleted: true,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    writer.delete(db.collection("establishment_private").doc(facility.id));
  }
  // setStaffSignInState disables each staff sign-in when it goes inactive.
  for (const doc of staff.docs) {
    writer.update(doc.ref, { active: false, updatedAt: FieldValue.serverTimestamp() });
  }
  await writer.close();

  for (const facility of facilities.docs) {
    try {
      await getStorage()
        .bucket()
        .deleteFiles({ prefix: `establishments/${facility.id}/document_` });
    } catch (error) {
      logger.warn(`Could not delete documents of ${facility.id}`, error);
    }
  }
}

/** Deletes the caller's own account. Drivers and parking owners only. */
async function deleteMyAccount(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Please sign in again.");
  // The app asks for the password again right before calling this.
  const authAgeSeconds = Date.now() / 1000 - (request.auth.token.auth_time || 0);
  if (authAgeSeconds > 10 * 60) {
    throw new HttpsError("failed-precondition", "Enter your password again to confirm.");
  }
  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);
  const role = String((await userRef.get()).data()?.role || "").trim();

  if (role === "Driver") await deleteDriver(db, uid);
  else if (role === "Parking Owner") await deleteOwner(db, uid);
  else if (role === "staff" || role === "supervisor") {
    throw new HttpsError("failed-precondition", "Ask your parking owner to remove your account.");
  } else {
    throw new HttpsError("failed-precondition", "This account can't be deleted from the app.");
  }

  // set, not merge: the email, phone tokens and settings all go.
  await userRef.set(deletedProfile(role));
  await getAuth().deleteUser(uid);
  logger.info(`Account ${uid} (${role}) deleted at its owner's request.`);
  return { deleted: true };
}

module.exports = {
  driverDeletionDenial,
  ownerDeletionDenial,
  deleteMyAccount,
};
