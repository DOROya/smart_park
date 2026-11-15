const test = require("node:test");
const assert = require("node:assert/strict");

const {
  PASS_LIFETIME_MS,
  GATE_PAYMENT_TIMEOUT_MS,
  isActivePass,
  isExpired,
  gatePaymentTimedOut,
  startDenial,
  passSummary,
} = require("../src/gate_pass");

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
});
