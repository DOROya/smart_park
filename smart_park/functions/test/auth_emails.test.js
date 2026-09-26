const test = require("node:test");
const assert = require("node:assert/strict");

const {
  escapeHtml,
  firstNameFrom,
  buildVerificationEmail,
  buildPasswordResetEmail,
  throttleDecision,
} = require("../src/auth_emails");

const MINUTE = 60 * 1000;

test("firstNameFrom reads the sign-up First|Last format", () => {
  assert.equal(firstNameFrom("Seele|Vollerei"), "Seele");
  assert.equal(firstNameFrom("Juan dela Cruz"), "Juan");
  assert.equal(firstNameFrom(""), "there");
  assert.equal(firstNameFrom(undefined), "there");
});

test("escapeHtml neutralises markup", () => {
  assert.equal(escapeHtml(`<b a="1">&'`), "&lt;b a=&quot;1&quot;&gt;&amp;&#39;");
});

test("verification email carries the link and escapes the name", () => {
  const link = "https://example.com/__/auth/action?mode=verifyEmail&oobCode=abc";
  const email = buildVerificationEmail({ displayName: "<script>|X", link });
  assert.equal(email.subject, "Confirm your SmartPark account");
  assert.ok(email.html.includes("mode=verifyEmail&amp;oobCode=abc"));
  assert.ok(!email.html.includes("<script>"));
  assert.ok(email.text.includes(link));
});

test("password reset email carries the link", () => {
  const link = "https://example.com/__/auth/action?mode=resetPassword&oobCode=xyz";
  const email = buildPasswordResetEmail({ displayName: "Seele|Vollerei", link });
  assert.equal(email.subject, "Reset your SmartPark password");
  assert.ok(email.html.includes("Hi Seele,"));
  assert.ok(email.text.includes(link));
});

test("throttle allows the first send", () => {
  assert.equal(throttleDecision([], 1000).waitMs, 0);
});

test("throttle enforces a one-minute cooldown", () => {
  const now = 10 * MINUTE;
  assert.equal(throttleDecision([now - 20 * 1000], now).waitMs, 40 * 1000);
  assert.equal(throttleDecision([now - MINUTE], now).waitMs, 0);
});

test("throttle caps five sends per hour and forgets old ones", () => {
  const now = 100 * MINUTE;
  const five = [50, 40, 30, 20, 10].map((m) => now - m * MINUTE);
  assert.equal(throttleDecision(five, now).waitMs, 10 * MINUTE);

  const stale = [now - 61 * MINUTE, now - 30 * MINUTE];
  const { recent, waitMs } = throttleDecision(stale, now);
  assert.equal(waitMs, 0);
  assert.deepEqual(recent, [now - 30 * MINUTE]);
});
