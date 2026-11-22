// "Download my data" from the Profile: a copy of the personal data SmartPark
// keeps about the caller, as one JSON file (the right of access under the
// Data Privacy Act of 2012, RA 10173). It holds only the caller's own
// records, the same ones the app already shows them; reports other people
// filed about them stay private, as in the app.

const { getAuth } = require("firebase-admin/auth");
const { getFirestore, Timestamp, GeoPoint, DocumentReference, FieldValue } =
  require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");

const FORMAT = "smartpark-data-export/1";
// Enough for years of parking; keeps the reply well under the 10 MB limit.
const MAX_DOCS_PER_COLLECTION = 2000;
// One export a minute per account.
const MIN_SECONDS_BETWEEN_EXPORTS = 60;

/** A Firestore value as plain JSON. */
function toJson(value) {
  if (value === undefined || value === null) return null;
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (value instanceof GeoPoint) return { latitude: value.latitude, longitude: value.longitude };
  if (value instanceof DocumentReference) return value.path;
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) return "(binary data)";
  if (Array.isArray(value)) return value.map(toJson);
  if (typeof value === "object") {
    const out = {};
    for (const [key, v] of Object.entries(value)) out[key] = toJson(v);
    return out;
  }
  return value;
}

/** A profile as exported: phone push tokens are counted, not copied. */
function profileForExport(profile) {
  if (!profile) return null;
  const out = toJson(profile);
  if (Array.isArray(profile.fcmTokens)) {
    out.fcmTokens = `${profile.fcmTokens.length} phone(s) signed in for notifications`;
  }
  return out;
}

/**
 * The queries that make up a [role]'s export: { section: [collection,
 * field] } (all where field == uid), plus single documents { section:
 * [collection, docId] }.
 */
function exportPlan(role, uid) {
  const common = { queries: {}, docs: {} };
  switch (role) {
    case "Driver":
      return {
        queries: {
          tickets: ["transactions", "driverId"],
          payments: ["payments", "driverId"],
          gatePasses: ["parking_checkouts", "driverId"],
          refunds: ["refunds", "driverId"],
          warnings: ["driver_warnings", "driverId"],
          facilityReportsYouFiled: ["facility_reports", "driverId"],
          ratingsYouGave: ["facility_ratings", "driverId"],
        },
        docs: {},
      };
    case "Parking Owner":
      return {
        queries: {
          facilities: ["establishments", "ownerId"],
          staff: ["staff_accounts", "ownerId"],
          driverReportsYouFiled: ["driver_reports", "reporterId"],
        },
        docs: { refundBalance: ["owner_refund_balances", uid] },
      };
    case "staff":
      return {
        queries: {
          shifts: ["staff_shifts", "staffId"],
          cashHandovers: ["cash_handovers", "staffId"],
          flagsYouRaised: ["staff_incidents", "staffId"],
        },
        docs: { staffRecord: ["staff_accounts", uid] },
      };
    default:
      return common;
  }
}

async function readQuery(db, collection, field, uid) {
  const snap = await db
    .collection(collection)
    .where(field, "==", uid)
    .limit(MAX_DOCS_PER_COLLECTION)
    .get();
  return snap.docs.map((d) => ({ id: d.id, ...toJson(d.data()) }));
}

/** Builds the export for [uid]. */
async function buildExport(db, uid, authUser, profile) {
  const role = String(profile?.role || profile?.Role || profile?.userRole || "").trim();
  const plan = exportPlan(role, uid);
  const sections = {};
  await Promise.all(
    Object.entries(plan.queries).map(async ([section, [collection, field]]) => {
      sections[section] = await readQuery(db, collection, field, uid);
    }),
  );
  await Promise.all(
    Object.entries(plan.docs).map(async ([section, [collection, id]]) => {
      const snap = await db.collection(collection).doc(id).get();
      sections[section] = snap.exists ? { id: snap.id, ...toJson(snap.data()) } : null;
    }),
  );

  // An owner's facilities: the review record and documents they submitted.
  if (role === "Parking Owner" && Array.isArray(sections.facilities)) {
    for (const facility of sections.facilities) {
      const [details, privateDocs] = await Promise.all([
        db.collection("establishment_details").doc(facility.id).get(),
        db.collection("establishment_private").doc(facility.id).get(),
      ]);
      facility.details = details.exists ? toJson(details.data()) : null;
      facility.businessDocuments = privateDocs.exists ? toJson(privateDocs.data()) : null;
    }
  }

  const truncated = Object.entries(sections)
    .filter(([, v]) => Array.isArray(v) && v.length >= MAX_DOCS_PER_COLLECTION)
    .map(([k]) => k);

  return {
    format: FORMAT,
    exportedAt: new Date().toISOString(),
    note:
      "Your personal data held by SmartPark. Times are in UTC. " +
      "Owners: your facility's sales and gate records are in the Sales Report export." +
      (truncated.length > 0
        ? ` Only the latest ${MAX_DOCS_PER_COLLECTION} records are included for: ${truncated.join(", ")}.`
        : ""),
    account: {
      uid,
      email: authUser?.email || profile?.email || null,
      emailVerified: authUser?.emailVerified ?? null,
      createdAt: authUser?.metadata?.creationTime
        ? new Date(authUser.metadata.creationTime).toISOString()
        : null,
      lastSignInAt: authUser?.metadata?.lastSignInTime
        ? new Date(authUser.metadata.lastSignInTime).toISOString()
        : null,
      role: role || null,
    },
    profile: profileForExport(profile),
    ...sections,
  };
}

/** Callable: the caller's own data. */
async function exportMyData(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Please sign in again.");
  const db = getFirestore();

  // Rate limit, in a server-only record (the rules close it to clients).
  const limitRef = db.collection("data_exports").doc(uid);
  await db.runTransaction(async (tx) => {
    const last = (await tx.get(limitRef)).data()?.lastAt;
    if (last instanceof Timestamp) {
      const seconds = (Date.now() - last.toMillis()) / 1000;
      if (seconds < MIN_SECONDS_BETWEEN_EXPORTS) {
        throw new HttpsError(
          "resource-exhausted",
          "You just downloaded your data. Try again in a minute.",
        );
      }
    }
    tx.set(limitRef, { lastAt: FieldValue.serverTimestamp() });
  });

  const [authUser, profileSnap] = await Promise.all([
    getAuth().getUser(uid).catch(() => null),
    db.collection("users").doc(uid).get(),
  ]);
  return buildExport(db, uid, authUser, profileSnap.data());
}

module.exports = {
  FORMAT,
  toJson,
  profileForExport,
  exportPlan,
  buildExport,
  exportMyData,
};
