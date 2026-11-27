const test = require("node:test");
const assert = require("node:assert/strict");

const { driverDeletionDenial, ownerDeletionDenial } = require("../src/account");
const { permitNotice } = require("../src/permits");
const { ownerOwesCentavos, disputeDenial, paidByFor, isProbablyGone } = require("../src/refunds");
const { overtimeRateFor } = require("../src/pricing");
const { peso, stringData } = require("../src/notify");

const DAY = 24 * 60 * 60 * 1000;

test("a driver can delete their account unless something is in progress", () => {
  const none = { tickets: [], refunds: [], passes: [] };
  assert.equal(driverDeletionDenial(none), null);
  assert.equal(
    driverDeletionDenial({
      tickets: [{ entryStatus: "checked_out" }],
      refunds: [{ status: "refunded" }, { status: "requested" }],
      passes: [{ status: "awaiting_gate" }],
    }),
    null,
  );
  assert.match(driverDeletionDenial({ ...none, tickets: [{ entryStatus: "checked_in" }] }), /parked/);
  assert.match(driverDeletionDenial({ ...none, refunds: [{ status: "processing" }] }), /refund/);
  assert.match(driverDeletionDenial({ ...none, passes: [{ status: "pending" }] }), /payment/);
});

test("a stay long past its paid time counts as gone, not parked", () => {
  const HOUR = 60 * 60 * 1000;
  const entry = { toMillis: () => 0 };
  // 2 paid hours: gone once 2 + 24 hours have passed.
  const parked = { entryStatus: "checked_in", entryAt: entry, remainingHours: 2 };
  assert.equal(isProbablyGone(parked, 25 * HOUR), false);
  assert.equal(isProbablyGone(parked, 27 * HOUR), true);
  // Not parked, or no entry time: never.
  assert.equal(isProbablyGone({ ...parked, entryStatus: "checked_out" }, 99 * HOUR), false);
  assert.equal(isProbablyGone({ entryStatus: "checked_in", remainingHours: 2 }, 99 * HOUR), false);
  // So it no longer keeps the driver from deleting their account.
  const none = { tickets: [], refunds: [], passes: [] };
  assert.match(driverDeletionDenial({ ...none, tickets: [parked] }, 25 * HOUR), /parked/);
  assert.equal(driverDeletionDenial({ ...none, tickets: [parked] }, 27 * HOUR), null);
});

test("an owner can delete their account only with nothing left hanging", () => {
  const used = { status: "paid", plan: "base", remainingHours: 0, entryStatus: "checked_out" };
  assert.equal(ownerDeletionDenial({ tickets: [used], balance: undefined }), null);
  assert.equal(ownerDeletionDenial({ tickets: [], balance: { owedCentavos: 0 } }), null);
  // Walk-ins hold no paid hours.
  assert.equal(
    ownerDeletionDenial({ tickets: [{ status: "walk_in", source: "walk_in", entryStatus: "checked_out" }] }),
    null,
  );
  assert.match(ownerDeletionDenial({ tickets: [{ ...used, entryStatus: "checked_in" }] }), /parked/);
  assert.match(
    ownerDeletionDenial({ tickets: [{ status: "paid", plan: "daily", duration: 1, remainingHours: 5 }] }),
    /unused hours/,
  );
  assert.match(ownerDeletionDenial({ tickets: [], balance: { owedCentavos: 100 } }), /balance/);
  assert.match(ownerDeletionDenial({ tickets: [], balance: { reservedCentavos: 100 } }), /balance/);
});

test("permit reminders go out once, 30 days ahead and on expiry", () => {
  const now = Date.UTC(2026, 10, 15);
  assert.equal(permitNotice(null, undefined, now), null);
  assert.equal(permitNotice(now + 31 * DAY, undefined, now), null);
  assert.equal(permitNotice(now + 30 * DAY, undefined, now), "soon");
  assert.equal(permitNotice(now + 5 * DAY, `${now + 5 * DAY}:soon`, now), null);
  assert.equal(permitNotice(now - DAY, `${now - DAY}:soon`, now), "expired");
  assert.equal(permitNotice(now - DAY, `${now - DAY}:expired`, now), null);
  // A renewed permit has a new date, so it is reminded about again.
  assert.equal(permitNotice(now + 10 * DAY, `${now - DAY}:expired`, now), "soon");
});

test("an owner repays the whole refund they cover", () => {
  assert.equal(ownerOwesCentavos(10000), 10000);
  assert.equal(ownerOwesCentavos(0), 0);
  assert.equal(ownerOwesCentavos(undefined), 0);
});

test("a permit that lapsed after approval is the owner's to cover", () => {
  assert.equal(paidByFor(["Business permit expired"]), "owner");
  assert.equal(paidByFor(["Invalid business permit"]), "platform");
});

test("only the owner charged for a refund can dispute it, once", () => {
  const refund = { ownerId: "o1", paidBy: "owner" };
  assert.equal(disputeDenial(refund, "o1"), null);
  assert.equal(disputeDenial(refund, "o2")[0], "not-found");
  assert.equal(disputeDenial(undefined, "o1")[0], "not-found");
  assert.equal(disputeDenial({ ...refund, paidBy: "platform" }, "o1")[0], "failed-precondition");
  assert.equal(disputeDenial({ ...refund, dispute: { status: "rejected" } }, "o1")[0], "failed-precondition");
});

test("the overtime rate kept on a ticket matches the app's", () => {
  const rates = { car: { initial: 40, succeedingHour: "PHP 20" }, motorcycle: { initial: 15 }, truck: 80 };
  assert.equal(overtimeRateFor(rates, "car"), 20);
  assert.equal(overtimeRateFor(rates, "motorcycle"), 15);
  assert.equal(overtimeRateFor(rates, "truck"), 80);
  assert.equal(overtimeRateFor(rates, "van"), null);
  assert.equal(overtimeRateFor(null, "car"), null);
});

test("notices format money and send only string data", () => {
  assert.equal(peso(12550), "PHP 125.50");
  assert.equal(peso(undefined), "PHP 0.00");
  assert.deepEqual(stringData({ a: 1, b: null, c: "x" }), { a: "1", c: "x" });
});
