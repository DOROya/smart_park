const test = require("node:test");
const assert = require("node:assert/strict");

const {
  MAX_HOURS,
  extraHourRate,
  extraHoursDenial,
  priceExtraHours,
  extraHoursRecord,
} = require("../src/extra_hours");
const { ratingSummary, latestPerDriver } = require("../src/ratings");
const { noticeText } = require("../src/reminders");

const rates = { car: { initial: 50, succeedingHour: 30 } };

test("extra hours cost the ticket's fixed overtime rate, else the facility's", () => {
  assert.equal(extraHourRate({ vehicleType: "car", purchaseOvertimeRate: 25 }, rates), 25);
  assert.equal(extraHourRate({ vehicleType: "car" }, rates), 30);
  assert.equal(extraHourRate({ vehicleType: "truck" }, {}), null);
});

test("only the driver's own paid SmartPark ticket gets extra hours", () => {
  const ticket = { driverId: "d1", status: "paid" };
  assert.equal(extraHoursDenial(ticket, "d1"), null);
  assert.equal(extraHoursDenial(ticket, "d2")[0], "not-found");
  assert.equal(extraHoursDenial(null, "d1")[0], "not-found");
  assert.equal(extraHoursDenial({ ...ticket, source: "walk_in" }, "d1")[0], "failed-precondition");
  assert.equal(extraHoursDenial({ ...ticket, status: "refunded" }, "d1")[0], "failed-precondition");
});

test("pricing: hours x rate, with commission, PayMongo's minimum and a cap", () => {
  const p = priceExtraHours(2, 30, "gcash");
  assert.equal(p.amountCentavos, 6000);
  assert.equal(p.amount, 60);
  assert.equal(p.platformFeeCentavos, 300);
  assert.equal(p.netToOwnerCentavos, 6000 - 300 - p.estimatedProcessorFeeCentavos);
  assert.throws(() => priceExtraHours(0, 30, "gcash"), /Add 1 to 12 hours/);
  assert.throws(() => priceExtraHours(MAX_HOURS + 1, 30, "gcash"), /Add 1 to 12 hours/);
  assert.throws(() => priceExtraHours(1.5, 30, "gcash"), /Add 1 to 12 hours/);
  assert.throws(() => priceExtraHours(2, null, "gcash"), /doesn't sell extra hours/);
  // PHP 15 an hour: one hour is under PHP 20, so at least 2.
  assert.throws(() => priceExtraHours(1, 15, "gcash"), /at least 2 hours/);
});

test("a wallet ticket pays with its saved number; a card uses PayMongo's page", () => {
  const base = {
    ticketId: "t1",
    hours: 2,
    rate: 30,
    priced: priceExtraHours(2, 30, "gcash"),
  };
  const ticket = { driverId: "d1", establishmentId: "f1", ownerId: "o1", vehicleType: "car" };
  const wallet = extraHoursRecord({
    ...base,
    ticket: { ...ticket, paymentMethod: "gcash" },
    payer: { phone: "+639171234567" },
  });
  assert.equal(wallet.kind, "add_hours");
  assert.equal(wallet.status, "pending");
  assert.equal(wallet.directPay, true);
  assert.deepEqual(wallet.payer, { phone: "+639171234567" });
  assert.equal(wallet.transactionId, "t1");
  assert.equal(wallet.duration, 2);
  const card = extraHoursRecord({
    ...base,
    ticket: { ...ticket, paymentMethod: "card" },
    payer: { cardPaymentMethodId: "pm_used" },
  });
  assert.equal(card.directPay, false);
  assert.equal(card.payer, undefined);
  assert.equal(card.gatePaymentMode, "checkout");
});

test("reminders tell the driver they can add hours", () => {
  const ticket = { establishmentName: "Lot A", entryAt: { toMillis: () => 0 }, remainingHours: 2 };
  assert.match(noticeText("reminder", ticket, 90 * 60 * 1000).body, /Tap to add hours/);
  assert.match(noticeText("overtime", ticket, 3 * 60 * 60 * 1000).body, /add hours and stop it/);
});

test("a facility's rating is the average of whole stars, to one decimal", () => {
  assert.deepEqual(ratingSummary([5, 4, 4]), { rating: 4.3, ratingCount: 3 });
  assert.deepEqual(ratingSummary([5, 0, 6, "x", 3]), { rating: 4, ratingCount: 2 });
  assert.deepEqual(ratingSummary([]), { rating: 0, ratingCount: 0 });
});

test("a driver's older per-ticket ratings count once, as their newest", () => {
  const at = (ms) => ({ toMillis: () => ms });
  const kept = latestPerDriver([
    { driverId: "d1", stars: 2, updatedAt: at(1) },
    { driverId: "d1", stars: 5, updatedAt: at(3) },
    { driverId: "d1", stars: 3, updatedAt: at(2) },
    { driverId: "d2", stars: 4, updatedAt: at(1) },
  ]);
  assert.deepEqual(kept.map((r) => r.stars).sort(), [4, 5]);
});
