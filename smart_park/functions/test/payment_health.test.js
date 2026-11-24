const test = require("node:test");
const assert = require("node:assert/strict");
const { Timestamp } = require("firebase-admin/firestore");

const { summarizePaymentHealth, COUNTERS } = require("../src/payment_health");

const NOW = Date.parse("2026-11-22T06:00:00Z");
const minutesAgo = (m) => Timestamp.fromMillis(NOW - m * 60000);
const daysAgo = (d) => Timestamp.fromMillis(NOW - d * 24 * 60 * 60000);
const healthyRun = { lastRunAt: minutesAgo(5), paid: 1, errors: 0 };

function summary(input) {
  return summarizePaymentHealth({ nowMs: NOW, periodDays: 7, lastRun: healthyRun, ...input });
}

test("totals the period and works out the rescued share", () => {
  const s = summary({
    days: [
      { date: "2026-11-21", confirmedInApp: 18, rescued: 2, gateTimedOut: 1 },
      { date: "2026-11-20", confirmedInApp: 19, rescued: 1, gateCancelled: 2, checkoutsAbandoned: 1 },
    ],
  });
  assert.equal(s.paid, 40);
  assert.equal(s.rescued, 3);
  assert.equal(s.rescuedPercent, 7.5);
  assert.deepEqual(s.unfinished, {
    gateTimedOut: 1,
    gateCancelled: 2,
    gateFailedToStart: 0,
    checkoutsAbandoned: 1,
  });
  // Every day of the period, oldest first, quiet days at zero.
  assert.deepEqual(
    s.series.map((d) => [d.date, d.confirmedInApp, d.rescued, d.unfinished]),
    [
      ["2026-11-16", 0, 0, 0],
      ["2026-11-17", 0, 0, 0],
      ["2026-11-18", 0, 0, 0],
      ["2026-11-19", 0, 0, 0],
      ["2026-11-20", 19, 1, 3],
      ["2026-11-21", 18, 2, 1],
      ["2026-11-22", 0, 0, 0],
    ],
  );
  assert.equal(s.status, "ok");
  assert.deepEqual(s.problems, []);
});

test("nothing paid yet is not a division by zero", () => {
  const s = summary({});
  assert.equal(s.paid, 0);
  assert.equal(s.rescuedPercent, 0);
  assert.equal(s.status, "ok");
});

test("a gate payment pending for half an hour is stuck; a fresh one is not", () => {
  const s = summary({
    pending: [
      { kind: "gate_pass", gatePaymentStartedAt: minutesAgo(3) },
      { kind: "gate_pass", gatePaymentStartedAt: minutesAgo(45) },
      // In-app checkouts get a day before the job expires them.
      { kind: "add_hours", createdAt: minutesAgo(120) },
    ],
  });
  assert.equal(s.inProgress, 3);
  assert.equal(s.stuck, 1);
  assert.equal(s.oldestPendingMinutes, 120);
  assert.equal(s.status, "attention");
  assert.match(s.problems[0], /1 payment is stuck/);
});

test("an overdue or never-run 15-minute check needs attention", () => {
  const late = summary({ lastRun: { lastRunAt: minutesAgo(50) } });
  assert.equal(late.reconcile.overdue, true);
  assert.equal(late.reconcile.lastRunMinutesAgo, 50);
  assert.match(late.problems[0], /last ran 50 minutes ago/);

  const never = summary({ lastRun: null });
  assert.equal(never.reconcile.overdue, true);
  assert.match(never.problems[0], /has not run yet/);

  assert.equal(summary({}).reconcile.overdue, false);
});

test("refunds: in flight, failed, and sent but unconfirmed for a week", () => {
  const s = summary({
    refunds: [
      { status: "approved" },
      { status: "processing" },
      { status: "sent", sentAt: daysAgo(2) },
      { status: "sent", sentAt: daysAgo(9) },
      { status: "failed" },
    ],
  });
  assert.deepEqual(s.refunds, { inFlight: 4, failed: 1, slow: 1 });
  assert.equal(s.problems.length, 2);
  assert.equal(s.status, "attention");
});

test("rescued examples carry no driver details", () => {
  const s = summary({
    rescuedRecent: [
      {
        establishmentName: "Lot A",
        amount: 60,
        kind: "gate_pass",
        paidAt: minutesAgo(30),
        driverId: "d1",
        driverEmail: "x@y.z",
        vehiclePlate: "ABC123",
      },
    ],
  });
  assert.deepEqual(s.rescuedRecent, [
    { establishmentName: "Lot A", amount: 60, kind: "gate", paidAt: "2026-11-22T05:30:00.000Z" },
  ]);
});

test("every counter is summed", () => {
  const day = Object.fromEntries(COUNTERS.map((c) => [c, 1]));
  const s = summary({ days: [{ date: "2026-11-22", ...day }] });
  assert.equal(s.paid, 2);
  assert.equal(Object.values(s.unfinished).reduce((a, b) => a + b, 0), COUNTERS.length - 2);
});

test("admins are alerted about stuck payments, at most every 6 hours", () => {
  const { alertProblems, alertDue, summarizePaymentHealth, ALERT_EVERY_MS } = require("../src/payment_health");
  const now = Date.UTC(2026, 10, 23, 4);
  const healthy = summarizePaymentHealth({ lastRun: { lastRunAt: now - 60000 }, nowMs: now, periodDays: 1 });
  assert.deepEqual(alertProblems(healthy), []);
  assert.equal(alertDue(alertProblems(healthy), null, now), false);

  const stuck = summarizePaymentHealth({
    pending: [{ status: "pending", kind: "gate_pass", gatePaymentStartedAt: now - 60 * 60 * 1000 }],
    lastRun: { lastRunAt: now - 60000 },
    nowMs: now,
    periodDays: 1,
  });
  const problems = alertProblems(stuck);
  assert.match(problems[0], /stuck/);
  assert.equal(alertDue(problems, null, now), true);
  assert.equal(alertDue(problems, now - ALERT_EVERY_MS + 1, now), false);
  assert.equal(alertDue(problems, now - ALERT_EVERY_MS, now), true);

  const overdue = summarizePaymentHealth({ lastRun: { lastRunAt: now - 60 * 60 * 1000 }, nowMs: now, periodDays: 1 });
  assert.match(alertProblems(overdue)[0], /last ran 60 minutes ago/);
});
