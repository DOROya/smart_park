const test = require("node:test");
const assert = require("node:assert/strict");

const { staffSignInChange } = require("../src/staff");

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
