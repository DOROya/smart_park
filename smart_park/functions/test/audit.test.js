const test = require("node:test");
const assert = require("node:assert/strict");
const { Timestamp } = require("firebase-admin/firestore");

const {
  fieldChanges,
  summarizeValue,
  actorFromEvent,
  describeFacilityDetails,
  describeEstablishment,
  describeStaff,
  describeWarning,
  describeReport,
  entryForWrite,
} = require("../src/audit");

const lookup = {
  actor: async (uid) => ({ actorId: uid, actorName: `Name of ${uid}`, actorRole: "admin" }),
  facility: async (id) => ({ ownerId: id ? "owner1" : "", establishmentName: id ? "Lot A" : "" }),
};

test("fieldChanges lists changed fields and skips bookkeeping ones", () => {
  const changes = fieldChanges(
    { status: "pending", updatedAt: 1, isOnline: true, name: "A" },
    { status: "approved", updatedAt: 2, isOnline: false, name: "A" },
  );
  assert.deepEqual(changes, { status: { from: "pending", to: "approved" } });
});

test("fieldChanges sees added and removed fields", () => {
  assert.deepEqual(fieldChanges({ a: 1 }, { b: 2 }), {
    a: { from: 1, to: null },
    b: { from: null, to: 2 },
  });
});

test("fieldChanges compares maps and timestamps by value", () => {
  const t = Timestamp.fromMillis(1000);
  assert.deepEqual(
    fieldChanges({ rates: { car: 50 }, at: t }, { rates: { car: 50 }, at: Timestamp.fromMillis(1000) }),
    {},
  );
  // Inside a map changed on both sides, only what changed is listed.
  assert.deepEqual(fieldChanges({ rates: { car: 50, moto: 20 } }, { rates: { car: 60, moto: 20 } }), {
    "rates.car": { from: 50, to: 60 },
  });
  // A map appearing or going away is shown whole.
  assert.deepEqual(fieldChanges({}, { notice: { a: 1 } }), {
    notice: { from: null, to: '{"a":1}' },
  });
});

test("a rate edit reads as one plain line, without the duplicate copies", async () => {
  // The edit made on the phone: car daily rate 251 -> 250, stored three ways.
  const rate = (daily) => ({
    car: { initial: "100", succeedingHour: "20", succeedingDaily: daily },
    motorcycle: { initial: "30", succeedingDaily: "100" },
  });
  const before = { status: "approved", ratesByType: rate("251"), rates: rate("251"), pricing: "Car: 100 (251/day)" };
  const after = { status: "approved", ratesByType: rate("250"), rates: rate("250"), pricing: "Car: 100 (250/day)" };
  const entry = await entryForWrite("establishment_details", "est1", before, after, "owner1", lookup);
  assert.equal(entry.action, "facility.rates_changed");
  assert.equal(entry.summary, "Changed the car daily rate from PHP 251 to PHP 250");
  assert.deepEqual(entry.changes, { "Car daily rate": { from: "PHP 251", to: "PHP 250" } });
});

test("several rate changes are summed up", () => {
  const changes = fieldChanges(
    { ratesByType: { car: { initial: "100", weekly: "550" }, motorcycle: { initial: "30" } } },
    { ratesByType: { car: { initial: "120", weekly: "600" }, motorcycle: { initial: "35" } } },
  );
  const d = describeFacilityDetails({ a: 1 }, { a: 1 }, changes);
  assert.equal(d.action, "facility.rates_changed");
  assert.equal(d.summary, "Changed 3 rates: car base rate, car weekly rate and motorcycle base rate");
  assert.equal(Object.keys(d.changes).length, 3);
});

test("a notice changed inside still reads as a notice", () => {
  const changes = fieldChanges(
    { status: "approved", complianceNotice: { reason: "a" } },
    { status: "approved", complianceNotice: { reason: "b" } },
  );
  assert.equal(describeFacilityDetails({ a: 1 }, { complianceNotice: {} }, changes).action, "facility.notice_given");
});

test("summarizeValue shortens long values and shows timestamps as ISO", () => {
  assert.equal(summarizeValue("x".repeat(400)).length, 303);
  assert.equal(summarizeValue(Timestamp.fromMillis(0)), "1970-01-01T00:00:00.000Z");
  assert.equal(summarizeValue(undefined), null);
});

test("writes by the server itself are not logged from triggers", () => {
  assert.equal(actorFromEvent({ authType: "service_account", authId: "x@y" }), null);
  assert.equal(actorFromEvent({ authType: "system" }), null);
  assert.equal(actorFromEvent({ authType: "api_key", authId: "uid1" }), "uid1");
  assert.equal(actorFromEvent({ authType: "unknown" }), "");
});

test("facility review decisions are named, with the reason", () => {
  const d = describeFacilityDetails(
    { status: "approved" },
    { status: "suspended", restrictionReason: "Expired permit" },
    { status: {} },
  );
  assert.equal(d.action, "facility.suspended");
  assert.equal(d.summary, "Suspended the facility: Expired permit");
  assert.equal(
    describeFacilityDetails({ status: "pending" }, { status: "approved", restrictionReason: "old" }, { status: {} })
      .summary,
    "Approved the facility",
  );
  assert.equal(describeFacilityDetails(undefined, { status: "pending" }, {}).action, "facility.submitted");
  assert.equal(describeFacilityDetails({ a: 1 }, { a: 1 }, {}), null);
});

test("rate edits on the listing are called out", () => {
  assert.equal(
    describeEstablishment({}, {}, { vehicleRates: {}, name: {} }).action,
    "facility.rates_changed",
  );
  assert.equal(describeEstablishment({}, {}, { name: {} }).action, "facility.updated");
});

test("staff changes", () => {
  assert.equal(describeStaff(undefined, { name: "Ben" }, {}).summary, "Added staff member Ben");
  assert.equal(describeStaff({ name: "Ben" }, { name: "Ben", active: false }, { active: {} }).action, "staff.deactivated");
  assert.equal(describeStaff({ name: "Ben", active: false }, { name: "Ben", active: true }, { active: {} }).action, "staff.reactivated");
  assert.equal(describeStaff({ name: "Ben" }, undefined, {}).action, "staff.removed");
});

test("a driver only reading a warning is not logged", () => {
  assert.equal(describeWarning({}, { acknowledgedAt: 1 }, { acknowledgedAt: {} }), null);
  assert.equal(describeWarning(undefined, { driverName: "Ana" }, {}).summary, "Warned Ana");
});

test("report creation is left to the admin alert; decisions are logged", () => {
  const describe = describeReport("driver");
  assert.equal(describe(undefined, { status: "open" }, {}), null);
  assert.equal(
    describe({ status: "open" }, { status: "resolved", driverName: "Ana" }, { status: {} }).summary,
    "Marked a report about Ana as resolved",
  );
});

test("entries about a facility reach its owner", async () => {
  const entry = await entryForWrite(
    "establishment_details",
    "est1",
    { status: "pending" },
    { status: "approved" },
    "admin1",
    lookup,
  );
  assert.equal(entry.action, "facility.approved");
  assert.equal(entry.actorName, "Name of admin1");
  assert.equal(entry.establishmentId, "est1");
  assert.equal(entry.establishmentName, "Lot A");
  assert.equal(entry.ownerId, "owner1");
  assert.deepEqual(entry.changes, { status: { from: "pending", to: "approved" } });
});

test("facility reports never reach the reported facility's owner", async () => {
  const entry = await entryForWrite(
    "facility_reports",
    "r1",
    { status: "open", establishmentId: "est1" },
    { status: "dismissed", establishmentId: "est1" },
    "admin1",
    lookup,
  );
  assert.equal(entry.ownerId, "");
});

test("warnings stay admin-only", async () => {
  const entry = await entryForWrite("driver_warnings", "w1", undefined, { driverId: "d1" }, "admin1", lookup);
  assert.equal(entry.ownerId, "");
});

test("unwatched collections and no-op writes log nothing", async () => {
  assert.equal(await entryForWrite("transactions", "t1", {}, { a: 1 }, "u", lookup), null);
  assert.equal(
    await entryForWrite("staff_accounts", "s1", { isOnline: true }, { isOnline: false }, "u", lookup),
    null,
  );
});

test("supervisor operations are described: overtime, cash, shifts", () => {
  const {
    describeGateLog,
    describeCashHandover,
    describeShift,
    fieldChanges,
  } = require("../src/audit");
  const before = { plate: "ABC 123", overtimeStatus: "cash_due" };
  const after = { ...before, overtimeStatus: "collected" };
  assert.equal(
    describeGateLog(before, after, fieldChanges(before, after)).summary,
    "Marked overtime for ABC 123 as collected",
  );
  // A new scan, or a change that isn't overtime, isn't logged here.
  assert.equal(describeGateLog(null, after, {}), null);
  assert.equal(describeGateLog(before, { ...before, isActive: false }, { isActive: {} }), null);
  assert.equal(
    describeCashHandover(null, { amount: 150, staffName: "Juan" }).summary,
    "Received PHP 150.00 from Juan",
  );
  assert.equal(
    describeShift({ staffName: "Ana", endedAt: null }, { staffName: "Ana", endedAt: 1, endedBy: "sup" }).summary,
    "Ended Ana's shift",
  );
  // Staff ending their own shift isn't an action on someone else.
  assert.equal(describeShift({ endedAt: null }, { endedAt: 1 }), null);
});

test("a temporary closure reads as one, not as field names", () => {
  const { describeFacilityDetails, fieldChanges } = require("../src/audit");
  const { Timestamp } = require("firebase-admin/firestore");
  const before = { status: "approved" };
  // 2026-11-24 14:00 UTC is 10:00 PM in Manila.
  const after = {
    status: "approved",
    closedUntil: Timestamp.fromMillis(Date.UTC(2026, 10, 24, 14)),
    closedReason: "Testing",
    closedBy: "o1",
  };
  assert.equal(
    describeFacilityDetails(before, after, fieldChanges(before, after)).summary,
    "Closed the facility until Nov 24, 10:00 PM (Testing)",
  );
  const reopened = { status: "approved", closedUntil: null };
  assert.equal(
    describeFacilityDetails(after, reopened, fieldChanges(after, reopened)).summary,
    "Reopened the facility",
  );
});

test("admin entries use the right article", () => {
  const { withArticle } = require("../src/admin_roles");
  assert.equal(withArticle("admin"), "an admin");
  assert.equal(withArticle("super admin"), "a super admin");
  assert.equal(withArticle("Driver"), "a Driver");
});

test("resolveActor names supervisors and console edits without their emails", async () => {
  const { resolveActor } = require("../src/audit");
  const docs = {
    "users/sup1": { role: "supervisor", email: "e6zfa_boss@staff.smartpark.internal" },
    "staff_accounts/sup1": { name: "Test Supervisor", role: "supervisor" },
    "users/own1": { firstName: "Saya", lastName: "Calamba", role: "Parking Owner" },
  };
  const db = {
    collection: (c) => ({ doc: (id) => ({ get: async () => ({ data: () => docs[`${c}/${id}`] }) }) }),
  };
  assert.deepEqual(await resolveActor(db, "sup1"), {
    actorId: "sup1",
    actorName: "Test Supervisor",
    actorRole: "supervisor",
  });
  assert.equal((await resolveActor(db, "own1")).actorName, "Saya Calamba");
  assert.equal((await resolveActor(db, "dev@gmail.com")).actorName, "SmartPark team");
});
