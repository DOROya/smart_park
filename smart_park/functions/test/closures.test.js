const test = require("node:test");
const assert = require("node:assert/strict");

const { newClosureUntil, closureNotice } = require("../src/closures");

const at = (ms) => ({ toMillis: () => ms });

test("drivers are told once per new or moved closure", () => {
  const now = Date.UTC(2026, 10, 23, 2);
  const later = now + 86400000;
  assert.equal(newClosureUntil({}, { closedUntil: at(later) }, now), later);
  // Same closure saved again (another field edited): no repeat.
  assert.equal(newClosureUntil({ closedUntil: at(later) }, { closedUntil: at(later) }, now), null);
  // Moved: told again.
  assert.equal(newClosureUntil({ closedUntil: at(later) }, { closedUntil: at(later + 3600000) }, now), later + 3600000);
  // Reopened, or an end already past: nothing.
  assert.equal(newClosureUntil({ closedUntil: at(later) }, { closedUntil: null }, now), null);
  assert.equal(newClosureUntil({}, { closedUntil: at(now - 1) }, now), null);
});

test("the notice says until when, why, and that tickets stay valid", () => {
  // 2026-11-24 07:00 UTC is 3:00 PM in Manila.
  const n = closureNotice("Lot A", Date.UTC(2026, 10, 24, 7), "Holiday");
  assert.equal(n.title, "Lot A is closed for now");
  assert.match(n.body, /Closed until Nov 24, 3:00 PM \(Holiday\)\./);
  assert.match(n.body, /stays valid/);
});

test("facilityClosedMessage refuses pulled and temporarily closed facilities", () => {
  const { facilityClosedMessage } = require("../src/checkout");
  const now = Date.UTC(2026, 10, 28, 4, 0);
  assert.equal(facilityClosedMessage({ status: "approved" }, now), null);
  assert.match(facilityClosedMessage({ status: "suspended" }, now), /not accepting/);
  assert.match(
    facilityClosedMessage({ status: "approved", closedUntil: at(now + 3600e3) }, now),
    /closed until/,
  );
  // Ended, or not started yet.
  assert.equal(facilityClosedMessage({ status: "approved", closedUntil: at(now - 1) }, now), null);
  assert.equal(
    facilityClosedMessage(
      { status: "approved", closedAt: at(now + 60e3), closedUntil: at(now + 3600e3) },
      now,
    ),
    null,
  );
});
