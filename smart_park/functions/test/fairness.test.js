const test = require("node:test");
const assert = require("node:assert/strict");

const { requestOverdue, isRefundSettled, REQUEST_AUTO_APPROVE_DAYS } = require("../src/refunds");
const { facilityHours, openMinutesBetween, dueNotices, prefsOf } = require("../src/reminders");
const { isNewComplianceNotice } = require("../src/permits");
const { driverDeletionDenial } = require("../src/account");

const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
/** A Manila wall-clock time as epoch milliseconds (Manila is UTC+8). */
const manila = (day, hour, minute = 0) => Date.UTC(2026, 10, day, hour - 8, minute);

test("a refund request nobody decided is approved after 3 days", () => {
  const now = manila(20, 6);
  assert.equal(REQUEST_AUTO_APPROVE_DAYS, 3);
  assert.equal(requestOverdue(now - 3 * DAY + MIN, now), false);
  assert.equal(requestOverdue(now - 3 * DAY, now), true);
  assert.equal(requestOverdue(null, now), false);
});

test("a refund is refunded only once PayMongo says it succeeded", () => {
  assert.equal(isRefundSettled("succeeded"), true);
  assert.equal(isRefundSettled("pending"), false);
  assert.equal(isRefundSettled("processing"), false);
  assert.equal(isRefundSettled("failed"), false);
  assert.equal(isRefundSettled(undefined), false);
});

test("a refund that was sent still blocks deleting the account", () => {
  assert.match(
    driverDeletionDenial({ tickets: [], refunds: [{ status: "sent" }], passes: [] }),
    /refund/,
  );
});

test("facility hours: open all day or unset never closes", () => {
  assert.equal(facilityHours({ open24Hours: true }), null);
  assert.equal(facilityHours({}), null);
  assert.equal(facilityHours({ openTime: "06:00", closeTime: "06:00" }), null);
  assert.deepEqual(facilityHours({ openTime: "06:00", closeTime: "22:00" }), { open: 360, close: 1320 });
});

test("only open minutes count toward overtime", () => {
  const hours = { open: 6 * 60, close: 22 * 60 };
  // 9 pm to 7 am the next day: open 9-10 pm and 6-7 am.
  assert.equal(openMinutesBetween(manila(15, 21), manila(16, 7), hours), 120);
  assert.equal(openMinutesBetween(manila(15, 21), manila(16, 7), null), 600);
  // Open overnight (6 pm to 2 am): 1 am to 7 pm is open 1-2 am and 6-7 pm.
  assert.equal(openMinutesBetween(manila(15, 1), manila(15, 19), { open: 18 * 60, close: 2 * 60 }), 120);
  assert.equal(openMinutesBetween(manila(15, 9), manila(15, 8), hours), 0);
});

test("the overtime alert waits until the facility has reopened", () => {
  const hours = { open: 6 * 60, close: 22 * 60 };
  const prefs = prefsOf({});
  // In at 7 pm with 2 hours left: paid until 9 pm, 20-minute grace.
  const ticket = { entryAt: manila(15, 19), plan: "base", remainingHours: 2 };
  const at = (day, hour, minute) => dueNotices(ticket, prefs, 20, manila(day, hour, minute), hours);
  assert.deepEqual(at(15, 21, 10), []);
  assert.deepEqual(at(15, 21, 25), ["overtime"]);

  // Paid until 9:50 pm: only 10 open minutes before closing, so the grace
  // period runs out at 6:10 the next morning, not during the night.
  const late = { entryAt: manila(15, 19, 50), plan: "base", remainingHours: 2 };
  const lateAt = (day, hour, minute) => dueNotices(late, prefs, 20, manila(day, hour, minute), hours);
  assert.deepEqual(lateAt(16, 2, 0), []);
  assert.deepEqual(lateAt(16, 6, 5), []);
  assert.deepEqual(lateAt(16, 6, 15), ["overtime"]);
  // Without hours it would have been due that night.
  assert.deepEqual(dueNotices(late, prefs, 20, manila(15, 22, 30)), ["overtime"]);
});

test("the owner is told once about each notice to fix something", () => {
  const notice = { issuedAt: 1000, dueAt: 2000, reasons: ["Rates differ from the listing"] };
  assert.equal(isNewComplianceNotice({}, { complianceNotice: notice }), true);
  assert.equal(isNewComplianceNotice({ complianceNotice: notice }, { complianceNotice: notice }), false);
  assert.equal(isNewComplianceNotice({ complianceNotice: notice }, { complianceNotice: { ...notice, issuedAt: 3000 } }), true);
  assert.equal(isNewComplianceNotice({ complianceNotice: notice }, {}), false);
});
