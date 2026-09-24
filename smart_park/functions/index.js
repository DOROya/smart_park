const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const { defineSecret } = require("firebase-functions/params");

const checkout = require("./src/checkout");
const occupancy = require("./src/occupancy");
const { platformFeeCentavosFor } = require("./src/pricing");
const { dayKeyManila, dayStartManila } = require("./src/dates");

initializeApp();

// Singapore is the closest region to the Philippines. The app must call
// these functions with the same region (see parking_checkout_service.dart).
setGlobalOptions({ region: "asia-southeast1", maxInstances: 10 });

const PAYMONGO_SECRET_KEY = defineSecret("PAYMONGO_SECRET_KEY");

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
