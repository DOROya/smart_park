const test = require("node:test");
const assert = require("node:assert/strict");

const {
  dailySummaryPrefs,
  manilaHour,
  summarizeOwnerDay,
  summaryMessage,
} = require("../src/owner_summary");
const { dayKeyManila } = require("../src/dates");

test("a sample day: sales, walk-in cash, uncollected overtime, cash per staff", () => {
  const s = summarizeOwnerDay({
    dayLogs: [
      { scanType: "entry", status: "ALLOWED" },
      { scanType: "entry", status: "DENIED" },
      { scanType: "exit", walkInFee: 60 },
      { scanType: "exit", overtimeStatus: "cash_due", overtimeAmount: 60 },
    ],
    inside: 2,
    splits: [{ grossAmountCentavos: 320000 }, { grossAmountCentavos: 5000, status: "refunded" }],
    cashLogs: [
      { staffId: "s1", staffName: "Juan Dela Cruz", overtimeStatus: "collected", overtimeAmount: 200 },
      { staffId: "s1", staffName: "Juan Dela Cruz", walkInFee: 100 },
      { staffId: "s2", staffName: "Ana", walkInFee: 50, cashHandoverId: "h1" },
    ],
    openShifts: [{ staffName: "Pedro" }],
  });
  assert.equal(s.entries, 1);
  assert.equal(s.exits, 2);
  assert.equal(s.salesCentavos, 320000);
  assert.equal(s.walkInCashCentavos, 6000);
  assert.equal(s.overtimeUncollectedCentavos, 6000);
  assert.deepEqual(s.cashOwed, [{ name: "Juan Dela Cruz", centavos: 30000 }]);
  assert.deepEqual(s.onDuty, ["Pedro"]);
  const m = summaryMessage("Juliville Parking", s);
  assert.equal(m.title, "Juliville Parking — today");
  assert.match(m.body, /1 entry, 2 exits, 2 still inside · PHP 3,200 sales · PHP 60 walk-in cash/);
  assert.match(m.body, /Juan Dela Cruz hasn't handed over PHP 300 · Pedro is still clocked in/);
  assert.equal(m.data.tab, "staff");
});

test("a quiet day sends nothing", () => {
  assert.equal(summarizeOwnerDay({ inside: 3 }).quiet, true);
  assert.equal(summarizeOwnerDay({ dayLogs: [{ scanType: "exit" }] }).quiet, false);
});

test("the Manila day boundary and the chosen hour", () => {
  // 11:30 PM Manila is today; 12:10 AM is tomorrow.
  assert.equal(dayKeyManila(new Date(Date.UTC(2026, 10, 23, 15, 30))), "2026-11-23");
  assert.equal(dayKeyManila(new Date(Date.UTC(2026, 10, 23, 16, 10))), "2026-11-24");
  assert.equal(manilaHour(Date.UTC(2026, 10, 23, 13, 0)), 21);
  assert.deepEqual(dailySummaryPrefs({}), { enabled: true, hour: 21 });
  assert.deepEqual(
    dailySummaryPrefs({ notificationPrefs: { dailySummary: { enabled: false, hour: 7 } } }),
    { enabled: false, hour: 7 },
  );
  assert.equal(dailySummaryPrefs({ notificationPrefs: { dailySummary: { hour: 30 } } }).hour, 21);
});
