const test = require("node:test");
const assert = require("node:assert/strict");
const { Timestamp } = require("firebase-admin/firestore");

const { documentsDue, DOCUMENT_RETENTION_DAYS } = require("../src/privacy_cleanup");

const NOW = Date.parse("2026-11-22T00:00:00Z");
const daysAgo = (d) => Timestamp.fromMillis(NOW - d * 24 * 60 * 60 * 1000);

test("documents go 90 days after a rejection or deactivation", () => {
  assert.equal(DOCUMENT_RETENTION_DAYS, 90);
  assert.equal(documentsDue({ status: "rejected", reviewedAt: daysAgo(90) }, NOW), true);
  assert.equal(documentsDue({ status: "deactivated", reviewedAt: daysAgo(200) }, NOW), true);
  assert.equal(documentsDue({ status: "rejected", reviewedAt: daysAgo(89) }, NOW), false);
});

test("open, pending and suspended facilities keep their documents", () => {
  for (const status of ["approved", "pending", "suspended", ""]) {
    assert.equal(documentsDue({ status, reviewedAt: daysAgo(400) }, NOW), false, status);
  }
});

test("the decision date falls back to the last update, else nothing is deleted", () => {
  assert.equal(documentsDue({ status: "deactivated", updatedAt: daysAgo(100) }, NOW), true);
  assert.equal(documentsDue({ status: "deactivated" }, NOW), false);
  assert.equal(documentsDue(undefined, NOW), false);
});

test("status is read case-insensitively", () => {
  assert.equal(documentsDue({ status: "Rejected", reviewedAt: daysAgo(120) }, NOW), true);
});
