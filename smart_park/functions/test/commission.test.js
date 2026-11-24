const test = require("node:test");
const assert = require("node:assert/strict");

const {
  commissionRateAt,
  scheduleDenial,
  changeAnnouncement,
  percent,
} = require("../src/commission");
const { platformFeeCentavosFor, PLATFORM_FEE_RATE } = require("../src/pricing");
const { refundableBase } = require("../src/refunds");
const { priceExtraHours } = require("../src/extra_hours");

const DAY = 24 * 60 * 60 * 1000;
const at = (ms) => ({ toMillis: () => ms });
const now = Date.UTC(2026, 10, 23);

test("the rate in force: the pending one only from its date", () => {
  assert.equal(commissionRateAt(undefined, now), PLATFORM_FEE_RATE);
  const settings = { commissionRate: 0.05, pendingRate: 0.07, pendingEffectiveAt: at(now + DAY) };
  assert.equal(commissionRateAt(settings, now), 0.05);
  assert.equal(commissionRateAt(settings, now + DAY), 0.07);
  // A bad stored value never prices a sale.
  assert.equal(commissionRateAt({ commissionRate: 2 }, now), PLATFORM_FEE_RATE);
});

test("a higher rate needs 30 days' notice; a lower one a day", () => {
  assert.equal(scheduleDenial(0.05, 0.07, now + 30 * DAY, now), null);
  assert.match(scheduleDenial(0.05, 0.07, now + 29 * DAY, now)[1], /30 days/);
  assert.equal(scheduleDenial(0.05, 0.04, now + DAY, now), null);
  assert.match(scheduleDenial(0.05, 0.04, now + DAY - 1, now)[1], /tomorrow/);
  assert.equal(scheduleDenial(0.05, 0.2, now + 40 * DAY, now)[0], "invalid-argument");
  assert.equal(scheduleDenial(0.05, 0.005, now + 40 * DAY, now)[0], "invalid-argument");
  assert.match(scheduleDenial(0.05, 0.05, now + 40 * DAY, now)[1], /already/);
});

test("the announcement shows both rates and a PHP 100 example", () => {
  const a = changeAnnouncement({ oldRate: 0.05, newRate: 0.07, effectiveAtMs: Date.UTC(2027, 0, 1), message: "" });
  assert.equal(a.audience, "owners");
  assert.equal(a.kind, "commission_change");
  assert.match(a.body, /from 5% to 7%/);
  assert.match(a.body, /keeps PHP 5\.00 now and PHP 7\.00 from Jan 1, 2027/);
  assert.equal(percent(0.075), "7.5%");
});

test("a sale keeps the rate it was priced at, through refunds", () => {
  assert.equal(platformFeeCentavosFor(10000), 500);
  assert.equal(platformFeeCentavosFor(10000, 0.07), 700);
  // Extra hours bought at 7%.
  assert.equal(priceExtraHours(2, 30, "gcash", 0.07).platformFeeCentavos, 420);
  assert.equal(priceExtraHours(2, 30, "gcash", 0.07).commissionRate, 0.07);
  // A ticket sold at 7% refunds with 7% kept back; older ones with 5%.
  assert.equal(refundableBase({ amount: 100, paymentMethod: "gcash", commissionRate: 0.07 }).platformFee, 700);
  assert.equal(refundableBase({ amount: 100, paymentMethod: "gcash" }).platformFee, 500);
});
