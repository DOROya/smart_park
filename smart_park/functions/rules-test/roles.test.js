// Rules tests for admin access levels and the supervisor role
// (docs/admin-roles.md, docs/supervisor-role.md). Run with `npm run test:rules`.

const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  collection,
  query,
  where,
  getDocs,
  serverTimestamp,
} = require("firebase/firestore");

let env;
const verified = (email) => ({ email, email_verified: true });
const staffToken = (name) => ({ email: `abc12_${name}@staff.smartpark.internal`, email_verified: false });

function db(uid, token) {
  return env.authenticatedContext(uid, token).firestore();
}
const driver = () => db("driver1", verified("driver1@example.com"));
const owner = () => db("owner1", verified("owner1@example.com"));
const admin = () => db("admin1", verified("admin@example.com"));
const superAdmin = () => db("super1", verified("super@example.com"));
const supervisor = () => db("sup1", staffToken("sup"));
const otherSupervisor = () => db("sup2", staffToken("sup2"));
const staff = () => db("staff1", staffToken("juan"));

test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-smartpark-roles",
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8"),
    },
  });
});

test.after(async () => {
  await env.cleanup();
});

test.beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, "users/driver1"), { role: "Driver", email: "driver1@example.com" });
    await setDoc(doc(d, "users/owner1"), { role: "Parking Owner", email: "owner1@example.com" });
    await setDoc(doc(d, "users/admin1"), { role: "admin", adminLevel: "admin" });
    await setDoc(doc(d, "users/super1"), { role: "admin", adminLevel: "super" });
    await setDoc(doc(d, "users/sup1"), { role: "supervisor" });
    await setDoc(doc(d, "users/staff1"), { role: "staff" });
    await setDoc(doc(d, "establishments/est1"), { ownerId: "owner1", name: "Lot 1" });
    await setDoc(doc(d, "establishments/est2"), { ownerId: "owner2", name: "Lot 2" });
    await setDoc(doc(d, "establishment_details/est1"), { status: "approved", rates: {} });
    await setDoc(doc(d, "establishment_private/est1"), { businessDocumentUrls: ["u"] });
    await setDoc(doc(d, "staff_accounts/sup1"), {
      userId: "sup1", ownerId: "owner1", facilityId: "est1", role: "supervisor", name: "Sup",
    });
    await setDoc(doc(d, "staff_accounts/sup2"), {
      userId: "sup2", ownerId: "owner2", facilityId: "est2", role: "supervisor", name: "Sup2",
    });
    await setDoc(doc(d, "staff_accounts/staff1"), {
      userId: "staff1", ownerId: "owner1", facilityId: "est1", role: "staff", name: "Juan",
    });
    await setDoc(doc(d, "transactions/tx1"), {
      driverId: "driver1", establishmentId: "est1", status: "paid", vehiclePlate: "ABC123",
    });
    await setDoc(doc(d, "payment_splits/tx1"), { establishmentId: "est1" });
    await setDoc(doc(d, "payments/tx1"), { driverId: "driver1", establishmentId: "est1" });
    await setDoc(doc(d, "refunds/tx1"), { driverId: "driver1", ownerId: "owner1" });
    await setDoc(doc(d, "audit_logs/a1"), { ownerId: "owner1", summary: "x" });
    await setDoc(doc(d, "activity_logs/exit1"), {
      establishmentID: "est1", scanType: "exit", staffId: "staff1",
      overtimeStatus: "cash_due", overtimeAmount: 40,
    });
    await setDoc(doc(d, "activity_logs/exit2"), {
      establishmentID: "est2", scanType: "exit", staffId: "x", overtimeStatus: "cash_due",
    });
    await setDoc(doc(d, "staff_shifts/shift1"), {
      establishmentId: "est1", staffId: "staff1", startedAt: serverTimestamp(), endedAt: null,
    });
    await setDoc(doc(d, "staff_incidents/inc1"), {
      establishmentId: "est1", staffId: "staff1", driverId: "driver1", status: "open",
    });
    await setDoc(doc(d, "driver_reports/rep1"), { driverId: "admin1", reporterId: "owner1", status: "open" });
    await setDoc(doc(d, "driver_reports/rep2"), { driverId: "driver1", reporterId: "owner1", status: "open" });
  });
});

// ---------- admin access levels ----------

test("nobody writes admin access fields on their own profile", async () => {
  for (const field of ["adminLevel", "formerRole", "adminSince", "promotedBy"]) {
    await assertFails(updateDoc(doc(driver(), "users/driver1"), { [field]: "super" }));
    await assertFails(updateDoc(doc(admin(), "users/admin1"), { [field]: "super" }));
  }
  // Not on create either, even with an allowed role.
  await assertFails(
    setDoc(doc(db("new1", verified("n@x.com")), "users/new1"), { role: "Driver", adminLevel: "super" }),
  );
  await assertSucceeds(setDoc(doc(db("new1", verified("n@x.com")), "users/new1"), { role: "Driver" }));
  // Other edits still work.
  await assertSucceeds(updateDoc(doc(admin(), "users/admin1"), { firstName: "A" }));
});

test("every admin reads users' access levels; nobody writes another's", async () => {
  await assertSucceeds(getDoc(doc(admin(), "users/super1")));
  await assertSucceeds(getDoc(doc(superAdmin(), "users/driver1")));
  await assertFails(updateDoc(doc(superAdmin(), "users/driver1"), { role: "admin" }));
});

test("no admin decides a report about their own account", async () => {
  await assertFails(updateDoc(doc(admin(), "driver_reports/rep1"), { status: "resolved" }));
  await assertSucceeds(updateDoc(doc(admin(), "driver_reports/rep2"), { status: "resolved" }));
  await assertFails(
    setDoc(doc(admin(), "driver_warnings/w1"), { driverId: "admin1", reason: "x" }),
  );
  await assertSucceeds(
    setDoc(doc(admin(), "driver_warnings/w2"), { driverId: "driver1", reason: "x" }),
  );
});

// ---------- supervisors ----------

test("only a supervisor record may take the supervisor role", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/sup1"), {});
    await setDoc(doc(ctx.firestore(), "users/staff1"), {});
  });
  await assertSucceeds(updateDoc(doc(supervisor(), "users/sup1"), { role: "supervisor" }));
  await assertFails(updateDoc(doc(staff(), "users/staff1"), { role: "supervisor" }));
  // A supervisor can't pose as gate staff either.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/sup1"), {});
  });
  await assertFails(updateDoc(doc(supervisor(), "users/sup1"), { role: "staff" }));
  await assertSucceeds(updateDoc(doc(staff(), "users/staff1"), { role: "staff" }));
});

test("the owner adds a supervisor; the role can't change afterwards", async () => {
  await assertSucceeds(
    setDoc(doc(owner(), "staff_accounts/new1"), {
      userId: "new1", ownerId: "owner1", facilityId: "est1", role: "supervisor",
    }),
  );
  await assertFails(
    setDoc(doc(owner(), "staff_accounts/new2"), {
      userId: "new2", ownerId: "owner1", facilityId: "est1", role: "admin",
    }),
  );
  await assertFails(updateDoc(doc(owner(), "staff_accounts/staff1"), { role: "supervisor" }));
  await assertSucceeds(updateDoc(doc(owner(), "staff_accounts/staff1"), { name: "Juan C" }));
});

test("a supervisor reads their facility's staff, and changes none", async () => {
  await assertSucceeds(
    getDocs(query(collection(supervisor(), "staff_accounts"), where("facilityId", "==", "est1"))),
  );
  await assertFails(
    getDocs(query(collection(supervisor(), "staff_accounts"), where("facilityId", "==", "est2"))),
  );
  await assertFails(updateDoc(doc(supervisor(), "staff_accounts/staff1"), { active: false }));
  await assertFails(
    setDoc(doc(supervisor(), "staff_accounts/new3"), {
      userId: "new3", ownerId: "owner1", facilityId: "est1", role: "staff",
    }),
  );
  await assertFails(updateDoc(doc(supervisor(), "staff_accounts/sup1"), { role: "staff" }));
});

test("a supervisor runs operations: overtime, cash, shifts, flags, reports", async () => {
  await assertSucceeds(
    updateDoc(doc(supervisor(), "activity_logs/exit1"), {
      overtimeStatus: "collected",
      overtimeStatusBy: "sup1",
      overtimeStatusAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(supervisor(), "activity_logs/exit2"), {
      overtimeStatus: "collected",
      overtimeStatusBy: "sup1",
    }),
  );
  await assertSucceeds(
    setDoc(doc(supervisor(), "cash_handovers/h1"), {
      establishmentId: "est1", staffId: "staff1", amount: 40, logCount: 1,
      receivedAt: serverTimestamp(), receivedBy: "sup1",
    }),
  );
  // Never their own cash.
  await assertFails(
    setDoc(doc(supervisor(), "cash_handovers/h2"), {
      establishmentId: "est1", staffId: "sup1", amount: 40, logCount: 1,
      receivedAt: serverTimestamp(), receivedBy: "sup1",
    }),
  );
  await assertSucceeds(
    updateDoc(doc(supervisor(), "staff_shifts/shift1"), { endedAt: serverTimestamp(), endedBy: "sup1" }),
  );
  await assertSucceeds(
    updateDoc(doc(supervisor(), "staff_incidents/inc1"), {
      status: "dismissed", handledAt: serverTimestamp(), handledBy: "sup1",
    }),
  );
  await assertSucceeds(
    setDoc(doc(supervisor(), "driver_reports/rep3"), {
      reporterId: "sup1", status: "open", reason: "Rude", establishmentId: "est1",
      transactionId: "tx1", driverId: "driver1",
    }),
  );
  // Gate staff can't do the supervisor's part.
  await assertFails(
    setDoc(doc(staff(), "cash_handovers/h3"), {
      establishmentId: "est1", staffId: "staff1", amount: 40, logCount: 1,
      receivedAt: serverTimestamp(), receivedBy: "staff1",
    }),
  );
  await assertFails(
    updateDoc(doc(staff(), "staff_incidents/inc1"), { status: "dismissed", handledAt: serverTimestamp() }),
  );
});

test("a supervisor never sees earnings, refunds, documents or the audit log", async () => {
  await assertFails(getDoc(doc(supervisor(), "payment_splits/tx1")));
  await assertFails(getDoc(doc(supervisor(), "payments/tx1")));
  await assertFails(getDoc(doc(supervisor(), "refunds/tx1")));
  await assertFails(getDoc(doc(supervisor(), "establishment_private/est1")));
  await assertFails(getDoc(doc(supervisor(), "audit_logs/a1")));
});

test("a supervisor can't change prices, the listing or the review status", async () => {
  await assertFails(updateDoc(doc(supervisor(), "establishment_details/est1"), { rates: { car: 1 } }));
  await assertFails(updateDoc(doc(supervisor(), "establishments/est1"), { name: "Mine" }));
  await assertFails(updateDoc(doc(supervisor(), "establishment_details/est1"), { status: "pending" }));
});

test("another facility's supervisor sees nothing of this one's operations", async () => {
  await assertFails(getDoc(doc(otherSupervisor(), "staff_shifts/shift1")));
  await assertFails(getDoc(doc(otherSupervisor(), "staff_incidents/inc1")));
  await assertFails(getDoc(doc(otherSupervisor(), "activity_logs/exit1")));
});

// ---------- quick fixes: contact number, closures, commission, announcements ----------

const { Timestamp } = require("firebase/firestore");
const inDays = (n) => Timestamp.fromMillis(Date.now() + n * 24 * 60 * 60 * 1000);

test("the owner sets a contact number of at most 20 characters", async () => {
  await assertSucceeds(updateDoc(doc(owner(), "establishments/est1"), { contactNumber: "+639171234567" }));
  await assertFails(updateDoc(doc(owner(), "establishments/est1"), { contactNumber: "1".repeat(21) }));
  await assertFails(updateDoc(doc(driver(), "establishments/est1"), { contactNumber: "0917" }));
});

test("a closure ends in the future within 30 days; owner or supervisor only", async () => {
  const close = (until) => ({
    closedUntil: until, closedReason: "Holiday", closedAt: serverTimestamp(),
  });
  await assertSucceeds(updateDoc(doc(owner(), "establishment_details/est1"), close(inDays(2))));
  await assertFails(updateDoc(doc(owner(), "establishment_details/est1"), close(inDays(31))));
  await assertFails(updateDoc(doc(owner(), "establishment_details/est1"), close(inDays(-1))));
  // The supervisor may close or reopen, and change nothing else.
  await assertSucceeds(
    updateDoc(doc(supervisor(), "establishment_details/est1"), { ...close(inDays(1)), closedBy: "sup1" }),
  );
  await assertSucceeds(updateDoc(doc(supervisor(), "establishment_details/est1"), { closedUntil: null }));
  await assertFails(
    updateDoc(doc(supervisor(), "establishment_details/est1"), { ...close(inDays(1)), gracePeriodMinutes: 10 }),
  );
  await assertFails(updateDoc(doc(staff(), "establishment_details/est1"), close(inDays(1))));
});

test("a closed facility refuses check-ins and walk-ins", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), "establishment_details/est1"), { closedUntil: inDays(1) });
  });
  await assertFails(
    updateDoc(doc(staff(), "transactions/tx1"), {
      entryStatus: "checked_in", entryAt: serverTimestamp(), entryStaffId: "staff1",
    }),
  );
  await assertFails(
    setDoc(doc(staff(), "transactions/walk1"), {
      establishmentId: "est1", source: "walk_in", status: "walk_in", entryStatus: "checked_in",
      entryStaffId: "staff1", vehicleType: "car",
    }),
  );
  // Reopened: entries work again.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), "establishment_details/est1"), { closedUntil: null });
  });
  await assertSucceeds(
    updateDoc(doc(staff(), "transactions/tx1"), {
      entryStatus: "checked_in", entryAt: serverTimestamp(), entryStaffId: "staff1",
    }),
  );
});

test("everyone reads the commission settings; nobody writes them", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "settings/platform"), { commissionRate: 0.05 });
    await setDoc(doc(ctx.firestore(), "announcements/a1"), { audience: "owners", title: "Rate" });
    await setDoc(doc(ctx.firestore(), "announcements/a2"), { audience: "drivers", title: "Hi" });
  });
  await assertSucceeds(getDoc(doc(driver(), "settings/platform")));
  await assertFails(setDoc(doc(superAdmin(), "settings/platform"), { commissionRate: 0.1 }));
  await assertFails(setDoc(doc(admin(), "announcements/a3"), { audience: "owners" }));
  // Owners read owners' announcements, not drivers'.
  await assertSucceeds(
    getDocs(query(collection(owner(), "announcements"), where("audience", "==", "owners"))),
  );
  await assertFails(getDoc(doc(owner(), "announcements/a2")));
  await assertSucceeds(getDoc(doc(driver(), "announcements/a2")));
});

test("a user records only their own announcement reads", async () => {
  await assertSucceeds(
    setDoc(doc(owner(), "users/owner1/announcement_reads/a1"), {
      announcementId: "a1", seenAt: serverTimestamp(), acknowledgedAt: serverTimestamp(), acknowledged: true,
    }),
  );
  await assertFails(
    setDoc(doc(owner(), "users/owner1/announcement_reads/a1"), { announcementId: "a1", extra: 1 }),
  );
  await assertFails(
    setDoc(doc(driver(), "users/owner1/announcement_reads/a1"), { announcementId: "a1", seenAt: serverTimestamp() }),
  );
  await assertSucceeds(getDoc(doc(admin(), "users/owner1/announcement_reads/a1")));
});
