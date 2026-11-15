const test = require("node:test");
const assert = require("node:assert/strict");

const { prefsOf, paidUntilMs, dueNotices, noticeText } = require("../src/reminders");

const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const ENTRY = Date.UTC(2026, 10, 14, 1, 0);
// A daily ticket with 24 hours left, parked at ENTRY: paid until ENTRY + 24h.
const ticket = (extra = {}) => ({
  plan: "daily",
  duration: 1,
  entryAt: ENTRY,
  establishmentName: "Lot",
  ...extra,
});
const on = prefsOf({});

test("everything is on by default, 30 minutes ahead", () => {
  assert.deepEqual(on, { parkingReminders: true, leadMinutes: 30, overtimeAlerts: true });
  assert.equal(prefsOf({ notificationPrefs: { leadMinutes: 45 } }).leadMinutes, 30);
  assert.equal(prefsOf({ notificationPrefs: { leadMinutes: 60 } }).leadMinutes, 60);
});

test("paid time ends after the hours left on the ticket", () => {
  assert.equal(paidUntilMs(ticket()), ENTRY + 24 * HOUR);
  assert.equal(paidUntilMs(ticket({ remainingHours: 2 })), ENTRY + 2 * HOUR);
  assert.equal(paidUntilMs(ticket({ entryAt: null })), null);
});

test("the reminder comes in the last minutes, once per visit", () => {
  const until = ENTRY + 24 * HOUR;
  assert.deepEqual(dueNotices(ticket(), on, 20, until - 31 * MIN), []);
  assert.deepEqual(dueNotices(ticket(), on, 20, until - 29 * MIN), ["reminder"]);
  assert.deepEqual(dueNotices(ticket({ reminderSentFor: ENTRY }), on, 20, until - 29 * MIN), []);
  const off = { ...on, parkingReminders: false };
  assert.deepEqual(dueNotices(ticket(), off, 20, until - 10 * MIN), []);
});

test("the overtime alert waits for the grace period", () => {
  const until = ENTRY + 24 * HOUR;
  assert.deepEqual(dueNotices(ticket({ reminderSentFor: ENTRY }), on, 20, until + 10 * MIN), []);
  assert.deepEqual(dueNotices(ticket({ reminderSentFor: ENTRY }), on, 20, until + 21 * MIN), ["overtime"]);
  assert.deepEqual(
    dueNotices(ticket({ reminderSentFor: ENTRY, overtimeSentFor: ENTRY }), on, 20, until + 21 * MIN),
    [],
  );
  // Long-gone overstays are not announced.
  assert.deepEqual(dueNotices(ticket({ reminderSentFor: ENTRY }), on, 20, until + 7 * HOUR), []);
});

test("a new visit gets its own reminder", () => {
  const second = ENTRY + 48 * HOUR;
  const t = ticket({ entryAt: second, remainingHours: 2, reminderSentFor: ENTRY });
  assert.deepEqual(dueNotices(t, on, 20, second + 2 * HOUR - 15 * MIN), ["reminder"]);
});

test("the reminder says when the time ends", () => {
  const { title, body } = noticeText("reminder", ticket({ remainingHours: 2 }), ENTRY + 90 * MIN);
  assert.equal(title, "Parking time almost up");
  assert.match(body, /Lot ends at .* \(in 30 min\)/);
});
