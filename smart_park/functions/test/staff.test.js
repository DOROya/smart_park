const test = require("node:test");
const assert = require("node:assert/strict");

const {
  staffSignInChange,
  staffResetDenial,
  generateStaffPassword,
  supervisorRename,
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

test("a supervisor resets gate staff of their own facility only", () => {
  const gate = { userId: "s1", ownerId: "owner1", facilityId: "f1", role: "staff" };
  const sup = { userId: "sup1", ownerId: "owner1", facilityId: "f1", role: "supervisor" };
  assert.equal(staffResetDenial("sup1", gate, sup), null);
  // Not another supervisor, not themselves, not another facility's staff.
  assert.match(staffResetDenial("sup1", { ...sup, userId: "sup2" }, sup)[1], /Only the owner/);
  assert.match(staffResetDenial("sup1", sup, sup)[1], /Only the owner/);
  assert.equal(staffResetDenial("sup1", { ...gate, facilityId: "f2" }, sup)[0], "permission-denied");
  // A deactivated supervisor, or gate staff, can't reset anyone.
  assert.equal(staffResetDenial("sup1", gate, { ...sup, active: false })[0], "permission-denied");
  assert.equal(staffResetDenial("s2", gate, { ...gate, userId: "s2" })[0], "permission-denied");
  // The owner still resets supervisors.
  assert.equal(staffResetDenial("owner1", sup), null);
});

test("only an active supervisor renames themselves, with a first and last name", () => {
  const sup = { role: "supervisor", ownerId: "o1", facilityId: "f1" };
  assert.deepEqual(supervisorRename(sup, { firstName: "  Ana ", lastName: "de  la Cruz" }), {
    firstName: "Ana",
    lastName: "de la Cruz",
    name: "Ana de la Cruz",
  });
  assert.equal(supervisorRename({ ...sup, role: "staff" }, { firstName: "A", lastName: "B" })[0], "permission-denied");
  assert.equal(supervisorRename({ ...sup, active: false }, { firstName: "A", lastName: "B" })[0], "permission-denied");
  assert.equal(supervisorRename(undefined, { firstName: "A", lastName: "B" })[0], "permission-denied");
  assert.equal(supervisorRename(sup, { firstName: "A", lastName: " " })[0], "invalid-argument");
  assert.equal(supervisorRename(sup, { firstName: "A".repeat(51), lastName: "B" })[0], "invalid-argument");
});
