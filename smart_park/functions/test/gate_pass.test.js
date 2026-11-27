const test = require("node:test");
const assert = require("node:assert/strict");

const {
  PASS_LIFETIME_MS,
  GATE_PAYMENT_TIMEOUT_MS,
  isActivePass,
  isExpired,
  gatePaymentTimedOut,
  startDenial,
  confirmDenial,
  passSummary,
  normalizePhMobile,
  savedPayment,
} = require("../src/gate_pass");
const { buildPaymentIntentPayload, isIntentPaid } = require("../src/paymongo");

const NOW = Date.UTC(2026, 10, 14, 4, 0, 0);
const pass = (extra = {}) => ({
  kind: "gate_pass",
  establishmentId: "f1",
  status: "awaiting_gate",
  expiresAt: NOW + 60_000,
  ...extra,
});

test("a temporary QR lasts 3 days", () => {
  assert.equal(PASS_LIFETIME_MS, 3 * 24 * 60 * 60 * 1000);
});

test("expiry is by the stored time", () => {
  assert.equal(isExpired(pass(), NOW), false);
  assert.equal(isExpired(pass({ expiresAt: NOW }), NOW), true);
});

test("only waiting or paying passes are active", () => {
  assert.equal(isActivePass(pass(), NOW), true);
  assert.equal(isActivePass(pass({ status: "pending", expiresAt: NOW - 1 }), NOW), true);
  assert.equal(isActivePass(pass({ expiresAt: NOW - 1 }), NOW), false);
  for (const status of ["paid", "cancelled", "expired"]) {
    assert.equal(isActivePass(pass({ status }), NOW), false, status);
  }
  assert.equal(isActivePass({ ...pass(), kind: undefined }, NOW), false);
});

test("a gate payment times out after 5 minutes", () => {
  assert.equal(GATE_PAYMENT_TIMEOUT_MS, 5 * 60 * 1000);
  assert.equal(gatePaymentTimedOut(pass(), NOW), false);
  assert.equal(gatePaymentTimedOut(pass({ gatePaymentStartedAt: NOW - 60_000 }), NOW), false);
  assert.equal(
    gatePaymentTimedOut(pass({ gatePaymentStartedAt: NOW - GATE_PAYMENT_TIMEOUT_MS }), NOW),
    true,
  );
});

test("staff can start payment only on a usable pass at their facility", () => {
  assert.equal(startDenial(pass(), "f1", NOW), null);
  assert.equal(startDenial(pass({ status: "pending" }), "f1", NOW), null);
  assert.equal(startDenial(pass(), "f2", NOW)[0], "not-found");
  assert.equal(startDenial(null, "f1", NOW)[0], "not-found");
  assert.match(startDenial(pass({ expiresAt: NOW - 1 }), "f1", NOW)[1], /expired/);
  assert.match(startDenial(pass({ status: "cancelled" }), "f1", NOW)[1], /cancelled/);
  assert.match(startDenial(pass({ status: "paid" }), "f1", NOW)[1], /paid/i);
});

test("the summary reports an unused, out-of-date pass as expired", () => {
  const s = passSummary("c1", pass({ expiresAt: NOW - 1, vehiclePlate: "ABC123", amount: 50 }), NOW);
  assert.equal(s.status, "expired");
  assert.equal(s.plate, "ABC123");
  assert.equal(s.checkoutId, "c1");
  assert.equal(s.directPay, false);
  assert.equal(passSummary("c1", pass({ directPay: true }), NOW).directPay, true);
});

test("mobile numbers are normalized to +639XXXXXXXXX", () => {
  for (const raw of ["09171234567", "0917 123 4567", "9171234567", "+63 917-123-4567", "639171234567"]) {
    assert.equal(normalizePhMobile(raw), "+639171234567", raw);
  }
  for (const raw of ["", "0817 123 4567", "0917123456", "091712345678", "hello"]) {
    assert.equal(normalizePhMobile(raw), "", raw);
  }
});

const noCard = async () => {
  throw new Error("card lookup not expected");
};

test("a wallet pass saves the number and is paid directly", async () => {
  assert.deepEqual(await savedPayment({ payerPhone: "0917 123 4567" }, "gcash", noCard), {
    payer: { phone: "+639171234567" },
    directPay: true,
  });
  assert.equal((await savedPayment({ payerPhone: "09171234567" }, "paymaya", noCard)).directPay, true);
  await assert.rejects(savedPayment({ payerPhone: "12345" }, "gcash", noCard), /valid mobile number/);
});

test("without saved details a pass uses the checkout page", async () => {
  // An older app sends no number; QR Ph has nothing to save.
  assert.deepEqual(await savedPayment({}, "gcash", noCard), { payer: null, directPay: false });
  assert.deepEqual(await savedPayment({ payerPhone: "09171234567" }, "qrph", noCard), {
    payer: null,
    directPay: false,
  });
  assert.deepEqual(await savedPayment({}, "card", noCard), { payer: null, directPay: false });
});

test("a saved card keeps only PayMongo's token and its last digits", async () => {
  const saved = await savedPayment({ cardPaymentMethodId: "pm_abc123" }, "card", async (id) => {
    assert.equal(id, "pm_abc123");
    return { last4: "4242", brand: "visa" };
  });
  assert.deepEqual(saved, {
    payer: { cardPaymentMethodId: "pm_abc123", cardLast4: "4242", cardBrand: "visa" },
    directPay: true,
  });
  await assert.rejects(savedPayment({ cardPaymentMethodId: "4242424242424242" }, "card", noCard));
});

test("the driver can confirm only a payment staff started", () => {
  const paying = pass({
    driverId: "d1",
    status: "pending",
    gatePaymentMode: "direct",
    gatePaymentStartedAt: NOW - 60_000,
  });
  assert.equal(confirmDenial(paying, "d1", NOW), null);
  assert.equal(confirmDenial(paying, "d2", NOW)[0], "not-found");
  assert.equal(confirmDenial(null, "d1", NOW)[0], "not-found");
  assert.match(confirmDenial({ ...paying, status: "awaiting_gate" }, "d1", NOW)[1], /not started/);
  assert.match(confirmDenial({ ...paying, gatePaymentMode: "checkout" }, "d1", NOW)[1], /not started/);
  assert.equal(
    confirmDenial({ ...paying, gatePaymentStartedAt: NOW - GATE_PAYMENT_TIMEOUT_MS }, "d1", NOW)[0],
    "deadline-exceeded",
  );
});

test("a direct payment charges the same amount and records the split", () => {
  const payload = buildPaymentIntentPayload({
    amountCentavos: 5000,
    platformFeeCentavos: 500,
    description: "SmartPark Lot - HOURLY CAR",
    destinationAccountId: "owner1",
    paymentMethod: "gcash",
    metadata: { checkoutId: "c1", duration: 2, missing: undefined },
  });
  const a = payload.data.attributes;
  assert.equal(a.amount, 5000);
  assert.equal(a.currency, "PHP");
  assert.deepEqual(a.payment_method_allowed, ["gcash"]);
  assert.deepEqual(a.metadata, {
    checkoutId: "c1",
    duration: "2",
    platform_fee: "500",
    destination_account: "owner1",
  });
});

test("an intent counts as paid once it succeeded or has a paid payment", () => {
  assert.equal(isIntentPaid({ attributes: { status: "succeeded" } }), true);
  assert.equal(
    isIntentPaid({ attributes: { status: "processing", payments: [{ attributes: { status: "paid" } }] } }),
    true,
  );
  assert.equal(isIntentPaid({ attributes: { status: "awaiting_next_action" } }), false);
  assert.equal(isIntentPaid({}), false);
});

test("plateVariants matches a plate typed with or without the space", () => {
  const { plateVariants } = require("../src/gate_pass");
  assert.deepEqual(plateVariants("gaj789"), ["GAJ789", "GAJ 789", "GAJ-789"]);
  assert.deepEqual(plateVariants(" ABC  1234 "), ["ABC 1234", "ABC1234", "ABC-1234"]);
  assert.ok(plateVariants("ABC-1234").includes("ABC 1234"));
  assert.deepEqual(plateVariants("   "), []);
});
