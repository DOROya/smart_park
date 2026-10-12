const test = require("node:test");
const assert = require("node:assert/strict");

const {
  staffSignInChange,
  staffResetDenial,
  generateStaffPassword,
} = require("../src/staff");

test("deactivating a staff record disables their sign-in", () => {
  assert.deepEqual(
    staffSignInChange("s1", { userId: "s1" }, { userId: "s1", active: false }),
    { uid: "s1", disabled: true },
  );
});

test("reactivating re-enables it", () => {
  assert.deepEqual(
    staffSignInChange("s1", { userId: "s1", active: false }, { userId: "s1", active: true }),
    { uid: "s1", disabled: false },
  );
});

test("records without the field count as active", () => {
  assert.equal(staffSignInChange("s1", { userId: "s1" }, { userId: "s1", name: "B" }), null);
  assert.equal(staffSignInChange("s1", undefined, { userId: "s1" }), null);
});

test("a record created already deactivated disables the sign-in", () => {
  assert.deepEqual(
    staffSignInChange("s1", undefined, { userId: "s1", active: false }),
    { uid: "s1", disabled: true },
  );
});

test("deleting a record (legacy migration) leaves the sign-in alone", () => {
  assert.equal(staffSignInChange("old", { userId: "s1" }, undefined), null);
});

test("uses userId over a legacy random doc id", () => {
  assert.deepEqual(
    staffSignInChange("random", { userId: "s1" }, { userId: "s1", active: false }),
    { uid: "s1", disabled: true },
  );
});

test("only the owning owner may reset an active staff password", () => {
  const record = { userId: "s1", ownerId: "owner1" };
  assert.equal(staffResetDenial("owner1", record), null);
  assert.equal(staffResetDenial("owner2", record)[0], "permission-denied");
  assert.equal(staffResetDenial("", record)[0], "permission-denied");
  assert.equal(staffResetDenial("owner1", undefined)[0], "not-found");
  // A record with no owner can't be claimed by anyone.
  assert.equal(staffResetDenial("owner1", { userId: "s1" })[0], "permission-denied");
});

test("deactivated staff can't have their password reset", () => {
  assert.equal(
    staffResetDenial("owner1", { ownerId: "owner1", active: false })[0],
    "failed-precondition",
  );
});

test("generated passwords are 10 characters from the safe alphabet", () => {
  const password = generateStaffPassword();
  assert.equal(password.length, 10);
  assert.match(password, /^[A-HJ-NP-Za-km-z2-9!@#]+$/);
  assert.notEqual(generateStaffPassword(), generateStaffPassword());
  // Uses the picker it is given, so the alphabet mapping is checked exactly.
  assert.equal(generateStaffPassword(3, () => 0), "AAA");
});
