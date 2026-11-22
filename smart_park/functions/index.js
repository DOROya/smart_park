const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onObjectFinalized } = require("firebase-functions/v2/storage");
const { getStorage } = require("firebase-admin/storage");
const { onDocumentWrittenWithAuthContext } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const { defineSecret, defineBoolean } = require("firebase-functions/params");

const audit = require("./src/audit");
const dataExport = require("./src/data_export");
const paymentHealth = require("./src/payment_health");
const privacyCleanup = require("./src/privacy_cleanup");

const alerts = require("./src/alerts");
const authEmails = require("./src/auth_emails");
const extraHours = require("./src/extra_hours");
const ratings = require("./src/ratings");
const checkout = require("./src/checkout");
const gatePass = require("./src/gate_pass");
const refunds = require("./src/refunds");
const reminders = require("./src/reminders");
const account = require("./src/account");
const permits = require("./src/permits");
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

// Firebase App Check (see lib/services/app_check.dart). When true, every
// callable below refuses requests that don't come from the real app on a
// real phone. Set in functions/.env; turn it on only after the App Check
// page in the Firebase console shows the app's requests as verified.
const ENFORCE_APP_CHECK = defineBoolean("ENFORCE_APP_CHECK", { default: false });

/** onCall with the App Check setting applied. */
function callable(options, handler) {
  return onCall({ enforceAppCheck: ENFORCE_APP_CHECK, ...options }, handler);
}

exports.sendVerificationEmail = callable(
  { secrets: [GMAIL_APP_PASSWORD] },
  (request) =>
    authEmails.sendVerificationEmail(request, GMAIL_APP_PASSWORD.value()),
);

exports.sendPasswordResetEmail = callable(
  { secrets: [GMAIL_APP_PASSWORD] },
  (request) =>
    authEmails.sendPasswordResetEmail(request, GMAIL_APP_PASSWORD.value()),
);

// Temporary QRs: the driver pays only at the gate (see src/gate_pass.js).
// The secret checks a card the app saved with PayMongo.
exports.createParkingPass = callable(
  { secrets: [PAYMONGO_SECRET_KEY] },
  (request) => gatePass.createParkingPass(request, PAYMONGO_SECRET_KEY.value()),
);

exports.cancelParkingPass = callable({}, (request) => gatePass.cancelParkingPass(request));

// Extra hours on a paid ticket, e.g. from the "time almost up" reminder.
exports.addTicketHours = callable(
  { secrets: [PAYMONGO_SECRET_KEY] },
  (request) => extraHours.addTicketHours(request, PAYMONGO_SECRET_KEY.value()),
);

// The driver's Confirm tap at the gate: pays with the details saved on the QR.
exports.payGatePass = callable(
  { secrets: [PAYMONGO_SECRET_KEY] },
  (request) => gatePass.payGatePass(request, PAYMONGO_SECRET_KEY.value()),
);

exports.findGatePass = callable({}, (request) => gatePass.findGatePass(request));

exports.startGatePayment = callable(
  { secrets: [PAYMONGO_SECRET_KEY] },
  (request) => gatePass.startGatePayment(request, PAYMONGO_SECRET_KEY.value()),
);

exports.checkGatePayment = callable(
  { secrets: [PAYMONGO_SECRET_KEY] },
  (request) => gatePass.checkGatePayment(request, PAYMONGO_SECRET_KEY.value()),
);

exports.cancelGatePayment = callable(
  { secrets: [PAYMONGO_SECRET_KEY] },
  (request) => gatePass.cancelGatePayment(request, PAYMONGO_SECRET_KEY.value()),
);

exports.confirmParkingCheckout = callable(
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
  async () => {
    await checkout.reconcilePendingCheckouts(PAYMONGO_SECRET_KEY.value());
    // Same run: mark sent refunds refunded once PayMongo confirms them.
    await refunds.confirmSentRefunds(PAYMONGO_SECRET_KEY.value());
  },
);

// Refunds when SmartPark pulls a facility (see src/refunds.js).
exports.onFacilityStatusChange = onDocumentWritten(
  { document: "establishment_details/{establishmentId}", secrets: [PAYMONGO_SECRET_KEY] },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    // A notice to fix something before a suspension reaches the owner's phone.
    await permits.notifyComplianceNotice(event.params.establishmentId, before, after);
    // Applications and review requests to admins; decisions to the owner.
    await alerts.onFacilityChange(event.params.establishmentId, before, after);
    await refunds.onFacilityStatusChange(
      event.params.establishmentId,
      before,
      after,
      PAYMONGO_SECRET_KEY.value(),
    );
  },
);

exports.refundOnExit = onDocumentWritten(
  { document: "transactions/{transactionId}", secrets: [PAYMONGO_SECRET_KEY] },
  (event) =>
    refunds.onTicketExit(
      event.params.transactionId,
      event.data?.before?.data(),
      event.data?.after?.data(),
      PAYMONGO_SECRET_KEY.value(),
    ),
);

exports.refundLongSuspensions = onSchedule(
  { schedule: "every day 06:00", timeZone: "Asia/Manila", secrets: [PAYMONGO_SECRET_KEY] },
  async () => {
    await refunds.refundLongSuspensions(PAYMONGO_SECRET_KEY.value());
    // Same daily run: tell owners whose business permit is about to lapse.
    await permits.remindExpiringPermits();
    // And delete business documents of facilities rejected or deactivated
    // 90 days ago (src/privacy_cleanup.js, as the Privacy Notice says).
    await privacyCleanup.deleteStaleBusinessDocuments();
  },
);

// Keeps each facility's average rating (src/ratings.js).
exports.updateFacilityRating = onDocumentWritten("facility_ratings/{ticketId}", (event) =>
  ratings.onRatingWritten(event.data?.before?.data(), event.data?.after?.data()),
);

// New reports reach the admins, and staff flags their owner (src/alerts.js).
exports.alertDriverReport = onDocumentCreated("driver_reports/{reportId}", (event) =>
  alerts.onReportCreated("driver_reports", event.data?.data()),
);

exports.alertFacilityReport = onDocumentCreated("facility_reports/{reportId}", (event) =>
  alerts.onReportCreated("facility_reports", event.data?.data()),
);

exports.alertStaffFlag = onDocumentCreated("staff_incidents/{incidentId}", (event) =>
  alerts.onStaffFlagCreated(event.data?.data()),
);

// Push reminders before parked drivers' paid time runs out (src/reminders.js).
exports.sendParkingReminders = onSchedule(
  { schedule: "every 5 minutes", timeZone: "Asia/Manila" },
  () => reminders.sendParkingReminders(),
);

exports.requestRefund = callable({}, (request) => refunds.requestRefund(request));

exports.decideRefund = callable(
  { secrets: [PAYMONGO_SECRET_KEY] },
  audit.audited(
    (request) => refunds.decideRefund(request, PAYMONGO_SECRET_KEY.value()),
    (request, _, db) => {
      const approve = request.data?.approve === true;
      return audit.refundEntry(
        db,
        String(request.data?.ticketId || "").trim(),
        approve ? "refund.approved" : "refund.rejected",
        approve ? "Approved a refund" : "Rejected a refund",
        { note: String(request.data?.note || "").slice(0, 300) },
      );
    },
  ),
);

// Owners may dispute a refund charged to them; admins decide, and record
// balances owners pay directly.
exports.disputeRefundCharge = callable(
  {},
  audit.audited(
    (request) => refunds.disputeRefundCharge(request),
    (request, _, db) =>
      audit.refundEntry(
        db,
        String(request.data?.ticketId || "").trim(),
        "refund.charge_disputed",
        "Disputed a refund charge",
        { message: String(request.data?.message || "").slice(0, 500) },
      ),
  ),
);

exports.resolveRefundDispute = callable(
  {},
  audit.audited(
    (request) => refunds.resolveRefundDispute(request),
    (request, _, db) => {
      const uphold = request.data?.uphold === true;
      return audit.refundEntry(
        db,
        String(request.data?.ticketId || "").trim(),
        uphold ? "refund.dispute_upheld" : "refund.dispute_rejected",
        uphold ? "Upheld an owner's refund dispute" : "Rejected an owner's refund dispute",
        { note: String(request.data?.note || "").slice(0, 300) },
      );
    },
  ),
);

exports.recordOwnerRepayment = callable(
  {},
  audit.audited(
    (request) => refunds.recordOwnerRepayment(request),
    async (request, result, db) => {
      const ownerId = String(request.data?.ownerId || "").trim();
      const centavos = Math.floor(Number(request.data?.amountCentavos)) || 0;
      const owner = await audit.resolveActor(db, ownerId);
      return {
        action: "refund.owner_repayment",
        summary:
          `Recorded a PHP ${(centavos / 100).toFixed(2)} repayment from ${owner.actorName}` +
          ` (PHP ${((result?.owedCentavos || 0) / 100).toFixed(2)} still owed)`,
        targetType: "owner",
        targetId: ownerId,
        ownerId,
        details: { amountCentavos: centavos, owedCentavosAfter: result?.owedCentavos ?? null },
      };
    },
  ),
);

// Deletes the caller's own account (see src/account.js). The audit entry
// keeps the uid and role only: the name goes with the account.
exports.deleteMyAccount = callable(
  {},
  audit.audited(
    (request) => account.deleteMyAccount(request),
    () => ({
      action: "account.deleted",
      summary: "Deleted their own account",
      targetType: "user",
      ownerId: "",
    }),
  ),
);

// A copy of the caller's own data, from Profile > Download My Data
// (see src/data_export.js).
exports.exportMyData = callable(
  { timeoutSeconds: 120, memory: "512MiB" },
  audit.audited(
    (request) => dataExport.exportMyData(request),
    (request) => ({
      action: "account.data_exported",
      summary: "Downloaded a copy of their data",
      targetType: "user",
      targetId: request.auth?.uid || "",
      ownerId: "",
    }),
  ),
);

// Admin dashboard: payments confirmed in the app vs rescued by the 15-minute
// check, unfinished gate payments, stuck payments and refunds
// (see src/payment_health.js).
exports.getPaymentHealth = callable({}, (request) => paymentHealth.getPaymentHealth(request));

// Audit trail of direct changes made in the app (see src/audit.js).
for (const [collection, name] of [
  ["establishment_details", "auditFacilityDetails"],
  ["establishments", "auditFacilityListing"],
  ["staff_accounts", "auditStaffAccounts"],
  ["driver_warnings", "auditDriverWarnings"],
  ["driver_reports", "auditDriverReports"],
  ["facility_reports", "auditFacilityReports"],
]) {
  exports[name] = onDocumentWrittenWithAuthContext(`${collection}/{docId}`, (event) =>
    audit.onWatchedWrite(collection, event),
  );
}

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
// The audit entry never holds the new password from the result.
exports.resetStaffPassword = callable(
  {},
  audit.audited(
    (request) => staff.resetStaffPassword(request),
    async (request, _, db) => {
      const staffId = String(request.data?.staffId || "").trim();
      const record = (await db.collection("staff_accounts").doc(staffId).get()).data() || {};
      return {
        action: "staff.password_reset",
        summary: `Reset the password of staff member ${record.name || staffId}`,
        targetType: "staff",
        targetId: staffId,
        establishmentId: record.facilityId || record.establishmentID || "",
        ownerId: record.ownerId || "",
      };
    },
  ),
);

/**
 * Admin-only: rebuilds `stats_daily` and `stats/platform` from every paid
 * payment, and recounts every establishment's slot occupancy. Run once after deploying (Settings > Rebuild statistics), and
 * again only if the totals ever look wrong.
 */
exports.rebuildDailyStats = callable(
  { timeoutSeconds: 300, memory: "512MiB" },
  audit.audited(async (request) => {
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
  }, (_, result) => ({
    action: "maintenance.stats_rebuilt",
    summary: `Rebuilt statistics (${result?.paymentCount ?? 0} payments over ${result?.days ?? 0} days)`,
    targetType: "platform",
  })),
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
exports.compressExistingPhotos = callable(
  { memory: "1GiB", timeoutSeconds: 540 },
  audit.audited(async (request) => {
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
  }, () => ({
    action: "maintenance.photos_compressed",
    summary: "Compressed existing facility photos",
    targetType: "platform",
  })),
);
