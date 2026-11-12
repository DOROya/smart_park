const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onObjectFinalized } = require("firebase-functions/v2/storage");
const { getStorage } = require("firebase-admin/storage");
const { setGlobalOptions } = require("firebase-functions/v2");
const { defineSecret } = require("firebase-functions/params");

const authEmails = require("./src/auth_emails");
const checkout = require("./src/checkout");
const occupancy = require("./src/occupancy");
const photoCompress = require("./src/photo_compress");
const staff = require("./src/staff");
const { platformFeeCentavosFor } = require("./src/pricing");
const { dayKeyManila, dayStartManila } = require("./src/dates");

initializeApp();

// Singapore is the closest region to the Philippines. The app must call
// these functions with the same region (see parking_checkout_service.dart).
setGlobalOptions({ region: "asia-southeast1", maxInstances: 10 });

const PAYMONGO_SECRET_KEY = defineSecret("PAYMONGO_SECRET_KEY");
// App password for smartpark.noreply@gmail.com (see src/auth_emails.js).
const GMAIL_APP_PASSWORD = defineSecret("GMAIL_APP_PASSWORD");

exports.sendVerificationEmail = onCall(
  { secrets: [GMAIL_APP_PASSWORD] },
  (request) =>
    authEmails.sendVerificationEmail(request, GMAIL_APP_PASSWORD.value()),
);

exports.sendPasswordResetEmail = onCall(
  { secrets: [GMAIL_APP_PASSWORD] },
  (request) =>
    authEmails.sendPasswordResetEmail(request, GMAIL_APP_PASSWORD.value()),
);

exports.createParkingCheckout = onCall(
  { secrets: [PAYMONGO_SECRET_KEY] },
  (request) =>
    checkout.createParkingCheckout(request, PAYMONGO_SECRET_KEY.value()),
);

exports.confirmParkingCheckout = onCall(
  { secrets: [PAYMONGO_SECRET_KEY] },
  (request) =>
    checkout.confirmParkingCheckout(request, PAYMONGO_SECRET_KEY.value()),
);

exports.reconcilePendingCheckouts = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Manila",
    secrets: [PAYMONGO_SECRET_KEY],
  },
  () => checkout.reconcilePendingCheckouts(PAYMONGO_SECRET_KEY.value()),
);

// Keeps establishment_occupancy/{id} in step with checked-in tickets.
exports.updateOccupancy = onDocumentWritten("transactions/{transactionId}", async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  const db = getFirestore();
  for (const establishmentId of occupancy.affectedEstablishments(before, after)) {
    await occupancy.recountOccupancy(db, establishmentId);
  }
});

// Disables a staff member's sign-in when their owner deactivates them, and
// re-enables it on reactivation.
exports.setStaffSignInState = onDocumentWritten("staff_accounts/{staffId}", (event) =>
  staff.applyStaffSignInChange(
    staff.staffSignInChange(
      event.params.staffId,
      event.data?.before?.data(),
      event.data?.after?.data(),
    ),
  ),
);

// Owner-only emergency password reset for one of their staff members.
exports.resetStaffPassword = onCall((request) => staff.resetStaffPassword(request));

/**
 * Admin-only: rebuilds `stats_daily` and `stats/platform` from every paid
 * payment, and recounts every establishment's slot occupancy. Run once after deploying (Settings > Rebuild statistics), and
 * again only if the totals ever look wrong.
 */
exports.rebuildDailyStats = onCall(
  { timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Please sign in again.");
    }
    const db = getFirestore();
    const caller = await db.collection("users").doc(request.auth.uid).get();
    if (caller.data()?.role !== "admin") {
      throw new HttpsError("permission-denied", "Admins only.");
    }

    const [payments, splits, oldDays] = await Promise.all([
      db.collection("payments").get(),
      db.collection("payment_splits").get(),
      db.collection("stats_daily").get(),
    ]);

    const feeByPaymentId = new Map();
    for (const doc of splits.docs) {
      const s = doc.data();
      const paymentId = s.paymentId || doc.id;
      if (typeof s.platformFeeCentavos === "number") {
        feeByPaymentId.set(paymentId, s.platformFeeCentavos);
      }
    }

    const days = new Map();
    const total = { grossCentavos: 0, commissionCentavos: 0, paymentCount: 0 };
    for (const doc of payments.docs) {
      const p = doc.data();
      if (String(p.status || "paid").toLowerCase() !== "paid") continue;
      const created = p.createdAt instanceof Timestamp ? p.createdAt.toDate() : null;
      if (!created) continue;
      const gross = Math.round(Number(p.amount || 0) * 100);
      const fee = feeByPaymentId.get(doc.id) ?? platformFeeCentavosFor(gross);
      const key = dayKeyManila(created);
      const day = days.get(key) || { grossCentavos: 0, commissionCentavos: 0, paymentCount: 0 };
      day.grossCentavos += gross;
      day.commissionCentavos += fee;
      day.paymentCount += 1;
      days.set(key, day);
      total.grossCentavos += gross;
      total.commissionCentavos += fee;
      total.paymentCount += 1;
    }

    const writer = db.bulkWriter();
    for (const doc of oldDays.docs) {
      if (!days.has(doc.id)) writer.delete(doc.ref);
    }
    for (const [key, day] of days) {
      writer.set(db.collection("stats_daily").doc(key), {
        date: key,
        dayStart: Timestamp.fromDate(dayStartManila(key)),
        ...day,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    writer.set(db.collection("stats").doc("platform"), {
      ...total,
      updatedAt: FieldValue.serverTimestamp(),
    });
    await writer.close();

    // Also recount slot occupancy for every establishment.
    const establishments = await db.collection("establishments").get();
    for (const doc of establishments.docs) {
      await occupancy.recountOccupancy(db, doc.id);
    }

    return { days: days.size, ...total };
  },
);

// Re-encodes each facility photo / business document an owner uploads to a
// phone-sized JPEG (see src/photo_compress.js), in place, so drivers on
// mobile data download a few hundred KB instead of a 6-7 MB original.
// Storage triggers must run in the bucket's own region (us-east1).
exports.compressFacilityPhoto = onObjectFinalized(
  { region: "us-east1", memory: "1GiB", timeoutSeconds: 120 },
  async (event) => {
    const object = event.data;
    if (!photoCompress.shouldCompress(object)) return;
    const file = getStorage().bucket(object.bucket).file(object.name);
    const result = await photoCompress.compressObject(file);
    if (!result.skipped) {
      console.log(
        `Compressed ${result.name}: ${result.before} -> ${result.after} bytes`,
      );
    }
  },
);

/**
 * Admin-only: compresses the facility photos and documents uploaded before
 * compressFacilityPhoto existed. Safe to run again; finished files are
 * skipped. Run from Settings > Compress existing photos.
 */
exports.compressExistingPhotos = onCall(
  { memory: "1GiB", timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Please sign in again.");
    }
    const caller = await getFirestore()
      .collection("users")
      .doc(request.auth.uid)
      .get();
    if (caller.data()?.role !== "admin") {
      throw new HttpsError("permission-denied", "Admins only.");
    }
    return photoCompress.compressAllExisting(getStorage().bucket());
  },
);
