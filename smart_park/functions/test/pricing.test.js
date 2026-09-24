const test = require("node:test");
const assert = require("node:assert/strict");

const {
  PricingError,
  parseAmount,
  computeAmount,
  platformFeeCentavosFor,
  estimateProcessorFeeCentavos,
} = require("../src/pricing");
const { buildCheckoutPayload, isSessionPaid } = require("../src/paymongo");
const { dayKeyManila, dayStartManila } = require("../src/dates");

const rates = {
  car: { initial: "50", succeedingHour: 20, succeedingDaily: "PHP 300" },
  motorcycle: 30,
};

test("parseAmount reads numbers and the first number in text", () => {
  assert.equal(parseAmount(45), 45);
  assert.equal(parseAmount("PHP 12.50/hr"), 12.5);
  assert.equal(parseAmount("n/a"), 0);
  assert.equal(parseAmount(undefined), 0);
  assert.equal(parseAmount({}), 0);
});

test("base plan charges the initial rate once", () => {
  assert.deepEqual(
    computeAmount({ ratesByType: rates, vehicleType: "car", plan: "base", duration: 9 }),
    { amount: 50, duration: 1 },
  );
});

test("a flat vehicle rate counts as the initial rate", () => {
  assert.equal(
    computeAmount({ ratesByType: rates, vehicleType: "motorcycle", plan: "base" }).amount,
    30,
  );
});

test("extended adds the succeeding hourly rate per hour", () => {
  assert.equal(
    computeAmount({ ratesByType: rates, vehicleType: "car", plan: "extended", duration: 3 }).amount,
    110,
  );
});

test("daily multiplies the daily rate", () => {
  assert.equal(
    computeAmount({ ratesByType: rates, vehicleType: "car", plan: "daily", duration: 2 }).amount,
    600,
  );
});

test("plans the establishment does not offer are rejected", () => {
  assert.throws(
    () => computeAmount({ ratesByType: rates, vehicleType: "motorcycle", plan: "daily", duration: 1 }),
    PricingError,
  );
  assert.throws(
    () => computeAmount({ ratesByType: rates, vehicleType: "truck", plan: "base" }),
    PricingError,
  );
  assert.throws(
    () => computeAmount({ ratesByType: rates, vehicleType: "car", plan: "vip", duration: 1 }),
    PricingError,
  );
});

test("out-of-range durations are rejected", () => {
  for (const duration of [0, 13, 1.5, "3", undefined]) {
    assert.throws(
      () => computeAmount({ ratesByType: rates, vehicleType: "car", plan: "extended", duration }),
      PricingError,
    );
  }
  assert.throws(
    () => computeAmount({ ratesByType: rates, vehicleType: "car", plan: "daily", duration: 8 }),
    PricingError,
  );
});

test("fees match the app's rounding", () => {
  assert.equal(platformFeeCentavosFor(5000), 250);
  assert.equal(platformFeeCentavosFor(3333), 167);
  assert.equal(estimateProcessorFeeCentavos(10000, "card"), 350);
  assert.equal(estimateProcessorFeeCentavos(10000, "gcash"), 200);
  assert.equal(estimateProcessorFeeCentavos(10000, "qrph"), 134);
});

test("checkout payload falls back to every method for unsupported ones", () => {
  const payload = buildCheckoutPayload({
    amountCentavos: 5000,
    platformFeeCentavos: 250,
    description: "d",
    destinationAccountId: "owner1",
    paymentMethod: "shopeepay",
    metadata: { checkoutId: "c1" },
  });
  const attrs = payload.data.attributes;
  assert.deepEqual(attrs.payment_method_types, ["card", "gcash", "paymaya", "qrph"]);
  assert.equal(attrs.line_items[0].amount, 5000);
  assert.equal(attrs.metadata.checkoutId, "c1");
  assert.equal(attrs.metadata.platform_fee, 250);
});

test("isSessionPaid checks the session and its payments", () => {
  assert.equal(isSessionPaid({ attributes: { status: "paid" } }), true);
  assert.equal(
    isSessionPaid({ attributes: { status: "active", payments: [{ attributes: { status: "paid" } }] } }),
    true,
  );
  assert.equal(isSessionPaid({ attributes: { status: "active", payments: [] } }), false);
  assert.equal(isSessionPaid(undefined), false);
});

test("Manila day keys roll over at 16:00 UTC", () => {
  assert.equal(dayKeyManila(new Date("2026-09-24T15:59:59Z")), "2026-09-24");
  assert.equal(dayKeyManila(new Date("2026-09-24T16:00:00Z")), "2026-09-25");
  assert.equal(dayStartManila("2026-09-25").toISOString(), "2026-09-24T16:00:00.000Z");
});

const { tallyOccupancy, affectedEstablishments } = require("../src/occupancy");

test("occupancy tallies checked-in tickets per vehicle type", () => {
  assert.deepEqual(
    tallyOccupancy([{ vehicleType: "car" }, { vehicleType: "Car" }, { vehicleType: "motor" }, {}]),
    { car: 3, motorcycle: 1 },
  );
});

test("occupancy recounts only when a relevant field changes", () => {
  const t = { establishmentId: "e1", entryStatus: "not_checked_in", vehicleType: "car" };
  assert.deepEqual(affectedEstablishments(undefined, t), ["e1"]);
  assert.deepEqual(affectedEstablishments(t, { ...t, entryStatus: "checked_in" }), ["e1"]);
  assert.deepEqual(affectedEstablishments(t, { ...t, updatedAt: 1 }), []);
  assert.deepEqual(affectedEstablishments(t, { ...t, establishmentId: "e2" }), ["e1", "e2"]);
  assert.deepEqual(affectedEstablishments(t, undefined), ["e1"]);
});
