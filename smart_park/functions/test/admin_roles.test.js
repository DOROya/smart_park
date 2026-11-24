const test = require("node:test");
const assert = require("node:assert/strict");

const {
  adminLevelOf,
  signInIsFresh,
  promoteDenial,
  levelDenial,
  removeDenial,
  FRESH_SIGN_IN_SECONDS,
} = require("../src/admin_roles");
const { selfCaseCheck } = require("../src/refunds");

const driver = { role: "Driver" };
const owner = { role: "Parking Owner" };
const admin = { role: "admin", adminLevel: "admin" };
const legacyAdmin = { role: "admin" };
const superAdmin = { role: "admin", adminLevel: "super" };

test("admin levels: legacy admins are normal admins", () => {
  assert.equal(adminLevelOf(superAdmin), "super");
  assert.equal(adminLevelOf(admin), "admin");
  assert.equal(adminLevelOf(legacyAdmin), "admin");
  assert.equal(adminLevelOf(driver), "");
  // adminLevel on a non-admin means nothing.
  assert.equal(adminLevelOf({ role: "Driver", adminLevel: "super" }), "");
});

test("only a recent password sign-in may change access", () => {
  const now = 1_800_000_000;
  assert.equal(signInIsFresh({ auth_time: now - 60 }, now), true);
  assert.equal(signInIsFresh({ auth_time: now - FRESH_SIGN_IN_SECONDS - 1 }, now), false);
  assert.equal(signInIsFresh({}, now), false);
});

test("only verified drivers can be promoted, never yourself", () => {
  assert.equal(promoteDenial("s", "d", driver, "admin"), null);
  assert.equal(promoteDenial("s", "d", driver, "super"), null);
  assert.match(promoteDenial("s", "o", owner, "admin")[1], /owners can't be admins/);
  assert.match(promoteDenial("s", "x", { role: "staff" }, "admin")[1], /Only driver/);
  assert.match(promoteDenial("s", "a", admin, "admin")[1], /already an admin/);
  assert.match(promoteDenial("s", "s", driver, "admin")[1], /your own access/);
  assert.equal(promoteDenial("s", "d", driver, "owner")[0], "invalid-argument");
  assert.equal(promoteDenial("s", "d", null, "admin")[0], "not-found");
});

test("the last super admin can't be turned into a normal admin", () => {
  assert.equal(levelDenial("s1", "s2", superAdmin, "admin", 2), null);
  assert.match(levelDenial("s1", "s2", superAdmin, "admin", 1)[1], /at least one super admin/);
  assert.equal(levelDenial("s1", "a", admin, "super", 1), null);
  assert.match(levelDenial("s1", "s1", superAdmin, "admin", 3)[1], /your own access/);
  assert.match(levelDenial("s1", "a", admin, "admin", 2)[1], /Nothing to change/);
  assert.equal(levelDenial("s1", "d", driver, "super", 2)[0], "not-found");
});

test("a super admin is demoted in two steps; nobody removes themselves", () => {
  assert.equal(removeDenial("s", "a", admin), null);
  assert.equal(removeDenial("s", "a", legacyAdmin), null);
  assert.match(removeDenial("s", "s2", superAdmin)[1], /normal admin first/);
  assert.match(removeDenial("a", "a", admin)[1], /your own access/);
  assert.equal(removeDenial("s", "d", driver)[0], "not-found");
});

test("no admin decides a refund about their own account", () => {
  assert.throws(() => selfCaseCheck({ driverId: "a1" }, "a1"), /your own account/);
  assert.throws(() => selfCaseCheck({ ownerId: "a1" }, "a1"), /your own account/);
  assert.doesNotThrow(() => selfCaseCheck({ driverId: "d", ownerId: "o" }, "a1"));
});
