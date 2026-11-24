const test = require("node:test");
const assert = require("node:assert/strict");

const {
  SUSPENSION_REFUND_DAYS,
  includedStayHours,
  hoursLeft,
  refundCentavos,
  refundableBase,
  paidByFor,
  suspensionRefundDue,
  recoveryFor,
  buildRefund,
} = require("../src/refunds");

const DAY = 24 * 60 * 60 * 1000;

test("package hours match the app", () => {
  assert.equal(includedStayHours("base", 1), 2);
  assert.equal(includedStayHours("extended", 3), 5);
  assert.equal(includedStayHours("daily", 2), 48);
  assert.equal(includedStayHours("weekly", 1), 168);
  assert.equal(includedStayHours("monthly", 1), 720);
});

test("hours left come from remainingHours, else the whole package", () => {
  assert.equal(hoursLeft({ plan: "weekly", duration: 1 }), 168);
  assert.equal(hoursLeft({ plan: "weekly", duration: 1, remainingHours: 100 }), 100);
  assert.equal(hoursLeft({ plan: "daily", duration: 1, entryStatus: "checked_out" }), 0);
  assert.equal(hoursLeft({ remainingHours: -3 }), 0);
});

test("the refund is the unused share of the price less fees", () => {
  // 7 days for PHP 330 by GCash: 5% commission (1650) and 2% PayMongo
  // (660) are kept back, leaving 30690; 3 days used -> 4/7 of that.
  const ticket = { plan: "weekly", duration: 1, amount: 330, paymentMethod: "gcash", remainingHours: 96 };
  assert.deepEqual(refundableBase(ticket), {
    paid: 33000,
    platformFee: 1650,
    processorFee: 660,
    refundable: 30690,
  });
  assert.equal(refundCentavos(ticket), Math.floor((30690 * 96) / 168));
  assert.equal(refundCentavos({ ...ticket, remainingHours: 168 }), 30690);
  assert.equal(refundCentavos({ ...ticket, remainingHours: 0 }), 0);
  // A card's fee is 3.5%.
  assert.equal(refundableBase({ ...ticket, paymentMethod: "card" }).refundable, 33000 - 1650 - 1155);
});

test("SmartPark covers refunds for documents the admin approved", () => {
  assert.equal(paidByFor(["Invalid business permit"]), "platform");
  assert.equal(paidByFor(["Repeated driver complaints", "Incomplete or false documents"]), "platform");
  assert.equal(paidByFor(["Rates differ from the listing"]), "owner");
  assert.equal(paidByFor([]), "owner");
});

test("suspension refunds are due after 14 days", () => {
  const now = Date.UTC(2026, 10, 28);
  assert.equal(SUSPENSION_REFUND_DAYS, 14);
  assert.equal(suspensionRefundDue(now - 13 * DAY, now), false);
  assert.equal(suspensionRefundDue(now - 14 * DAY, now), true);
  assert.equal(suspensionRefundDue(null, now), false);
});

test("an owner repays at most half their share per sale", () => {
  assert.equal(recoveryFor(10000, 4000), 2000);
  assert.equal(recoveryFor(500, 4000), 500);
  assert.equal(recoveryFor(0, 4000), 0);
  assert.equal(recoveryFor(undefined, 4000), 0);
});

test("a refund record carries the amount and who pays", () => {
  const r = buildRefund(
    "t1",
    { driverId: "d1", establishmentId: "f1", ownerId: "o1", plan: "daily", duration: 2, amount: 200, remainingHours: 24 },
    { restrictionReasons: ["Invalid business permit"], name: "Lot" },
    "deactivated",
    "approved",
  );
  // PHP 200 less 5% commission and 2% PayMongo = 18600; half unused.
  assert.equal(r.amountCentavos, 9300);
  assert.equal(r.platformFeeCentavos, 1000);
  assert.equal(r.processorFeeCentavos, 400);
  assert.equal(r.unusedHours, 24);
  assert.equal(r.totalHours, 48);
  assert.equal(r.paidBy, "platform");
  assert.equal(r.establishmentName, "Lot");
});
