const test = require("node:test");
const assert = require("node:assert/strict");
const { Timestamp, GeoPoint } = require("firebase-admin/firestore");

const { toJson, profileForExport, exportPlan, buildExport, FORMAT } = require("../src/data_export");

test("toJson turns Firestore values into plain JSON", () => {
  assert.deepEqual(
    toJson({
      at: Timestamp.fromMillis(0),
      where: new GeoPoint(14.5, 121),
      list: [Timestamp.fromMillis(0), 1],
      nested: { n: null },
    }),
    {
      at: "1970-01-01T00:00:00.000Z",
      where: { latitude: 14.5, longitude: 121 },
      list: ["1970-01-01T00:00:00.000Z", 1],
      nested: { n: null },
    },
  );
});

test("push tokens are counted, not copied", () => {
  const out = profileForExport({ firstName: "Ana", fcmTokens: ["secret1", "secret2"] });
  assert.equal(out.firstName, "Ana");
  assert.equal(out.fcmTokens, "2 phone(s) signed in for notifications");
  assert.ok(!JSON.stringify(out).includes("secret1"));
});

test("each role exports only records keyed to the caller", () => {
  const driver = exportPlan("Driver", "u1");
  assert.deepEqual(driver.queries.tickets, ["transactions", "driverId"]);
  // Reports owners filed about a driver stay private, as in the app.
  assert.ok(!Object.values(driver.queries).some(([c]) => c === "driver_reports"));

  const owner = exportPlan("Parking Owner", "u1");
  assert.deepEqual(owner.queries.facilities, ["establishments", "ownerId"]);
  assert.deepEqual(owner.docs.refundBalance, ["owner_refund_balances", "u1"]);
  // Drivers' reports about the owner's facility stay private too.
  assert.ok(!Object.values(owner.queries).some(([c]) => c === "facility_reports"));

  assert.deepEqual(exportPlan("staff", "s1").docs.staffRecord, ["staff_accounts", "s1"]);
  assert.deepEqual(exportPlan("admin", "a1"), { queries: {}, docs: {} });
});

/** A tiny in-memory stand-in for the Firestore calls buildExport makes. */
function fakeDb(collections) {
  return {
    collection(name) {
      const docs = collections[name] || {};
      return {
        where(field, _, value) {
          return {
            limit() {
              return {
                async get() {
                  return {
                    docs: Object.entries(docs)
                      .filter(([, d]) => d[field] === value)
                      .map(([id, d]) => ({ id, data: () => d })),
                  };
                },
              };
            },
          };
        },
        doc(id) {
          return {
            async get() {
              return { id, exists: id in docs, data: () => docs[id] };
            },
          };
        },
      };
    },
  };
}

test("a driver's export holds their own tickets and not other drivers'", async () => {
  const db = fakeDb({
    transactions: {
      t1: { driverId: "u1", amount: 50, createdAt: Timestamp.fromMillis(0) },
      t2: { driverId: "u2", amount: 70 },
    },
  });
  const out = await buildExport(
    db,
    "u1",
    { email: "a@b.c", emailVerified: true, metadata: { creationTime: "2026-01-01T00:00:00Z" } },
    { role: "Driver", firstName: "Ana" },
  );
  assert.equal(out.format, FORMAT);
  assert.equal(out.account.email, "a@b.c");
  assert.equal(out.account.role, "Driver");
  assert.equal(out.account.createdAt, "2026-01-01T00:00:00.000Z");
  assert.deepEqual(out.tickets, [
    { id: "t1", driverId: "u1", amount: 50, createdAt: "1970-01-01T00:00:00.000Z" },
  ]);
  assert.deepEqual(out.payments, []);
});

test("an owner's export includes each facility's review record", async () => {
  const db = fakeDb({
    establishments: { e1: { ownerId: "o1", name: "Lot A" } },
    establishment_details: { e1: { status: "approved" } },
  });
  const out = await buildExport(db, "o1", null, { role: "Parking Owner" });
  assert.equal(out.facilities[0].name, "Lot A");
  assert.deepEqual(out.facilities[0].details, { status: "approved" });
  assert.equal(out.facilities[0].businessDocuments, null);
  assert.equal(out.refundBalance, null);
});
