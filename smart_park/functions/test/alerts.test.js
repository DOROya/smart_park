const test = require("node:test");
const assert = require("node:assert/strict");

const {
  KINDS,
  facilityReviewAlert,
  facilityStatusAlert,
  reportAlert,
  staffFlagAlert,
  refundRequestAlert,
} = require("../src/alerts");
const { paymentStage } = require("../src/gate_pass");

const ts = (ms) => ({ toMillis: () => ms });

test("admins hear about a new application", () => {
  const a = facilityReviewAlert(undefined, { status: "pending" }, "Lot A");
  assert.equal(a.title, "New facility to review");
  assert.match(a.body, /Lot A/);
  assert.equal(a.data.kind, KINDS.facilityReview);
});

test("admins hear about a resubmission, once per resubmission", () => {
  const rejected = { status: "rejected" };
  assert.equal(facilityReviewAlert(rejected, { status: "pending" }, "Lot A").title, "Facility resubmitted");
  const first = { status: "pending", resubmittedAt: ts(1) };
  assert.equal(
    facilityReviewAlert(first, { status: "pending", resubmittedAt: ts(2) }, "Lot A").title,
    "Facility resubmitted",
  );
  // An unrelated edit to a pending application is not news.
  assert.equal(facilityReviewAlert(first, { ...first, slots: 3 }, "Lot A"), null);
});

test("admins hear when an owner asks for review", () => {
  const suspended = { status: "suspended" };
  const a = facilityReviewAlert(suspended, { ...suspended, appealedAt: ts(5) }, "Lot A");
  assert.equal(a.title, "Review requested");
  assert.match(a.body, /suspended/);
  assert.equal(facilityReviewAlert({ ...suspended, appealedAt: ts(5) }, { ...suspended, appealedAt: ts(5) }, "Lot A"), null);
});

test("owners hear every decision on their facility", () => {
  const titles = (was, now, extra = {}) =>
    facilityStatusAlert({ status: was }, { status: now, ...extra }, "Lot A")?.title;
  assert.equal(titles("pending", "approved"), "Facility approved");
  assert.equal(titles("suspended", "approved"), "Facility reinstated");
  assert.equal(titles("deactivated", "approved"), "Facility reinstated");
  assert.equal(titles("pending", "rejected"), "Application not approved");
  assert.equal(titles("approved", "suspended"), "Facility suspended");
  assert.equal(titles("approved", "deactivated"), "Facility deactivated");
  assert.equal(titles("approved", "approved"), undefined);
  assert.equal(facilityStatusAlert(undefined, { status: "pending" }, "Lot A"), null);
  const rejected = facilityStatusAlert(
    { status: "pending" },
    { status: "rejected", rejectionReason: "Blurry permit" },
    "Lot A",
  );
  assert.match(rejected.body, /Reason: Blurry permit\./);
  assert.equal(rejected.data.kind, KINDS.facilityStatus);
});

test("reports reach admins with their reasons", () => {
  const d = reportAlert("driver_reports", {
    establishmentName: "Lot A",
    driverName: "Juan",
    reasons: ["No-show", "Rude"],
  });
  assert.equal(d.title, "Driver reported");
  assert.equal(d.body, "Lot A reported Juan: No-show, Rude.");
  const f = reportAlert("facility_reports", { establishmentName: "Lot A", reason: "Overcharged" });
  assert.equal(f.title, "Facility reported");
  assert.equal(f.body, "A driver reported Lot A: Overcharged.");
  assert.equal(f.data.kind, KINDS.report);
});

test("an owner hears when staff flag a driver", () => {
  const a = staffFlagAlert({ staffName: "Ana", driverName: "Juan", vehiclePlate: "ABC123", reasons: ["Wrong vehicle"] });
  assert.equal(a.body, "Ana flagged Juan (ABC123): Wrong vehicle. Review it in the app.");
  assert.equal(a.data.kind, KINDS.staffFlag);
});

test("a refund request warns it approves itself", () => {
  const a = refundRequestAlert({ establishmentName: "Lot A" }, 3);
  assert.match(a.body, /approved automatically in 3 days/);
  assert.equal(a.data.kind, KINDS.refundRequest);
});

test("staff see whether the driver still has to confirm", () => {
  assert.equal(paymentStage({ gatePaymentMode: "direct" }), "confirm");
  assert.equal(paymentStage({ gatePaymentMode: "direct", paymongo: { intentId: "pi_1" } }), "approve");
  assert.equal(paymentStage({ gatePaymentMode: "checkout", paymongo: { sessionId: "cs_1" } }), "approve");
  assert.equal(paymentStage({ gatePaymentMode: "checkout" }), "approve");
});
