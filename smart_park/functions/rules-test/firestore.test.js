// Firestore security rules tests. Run with `npm run test:rules` (starts the
// Firestore + Storage emulators, runs these, and shuts them down).

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
  deleteDoc,
  collection,
  query,
  where,
  getDocs,
  writeBatch,
  serverTimestamp,
} = require("firebase/firestore");

const PROJECT_ID = "demo-smartpark";
let env;

const verified = (email) => ({ email, email_verified: true });
const staffToken = { email: "abc12_juan@staff.smartpark.internal", email_verified: false };

function db(uid, token) {
  return uid ? env.authenticatedContext(uid, token).firestore() : env.unauthenticatedContext().firestore();
}
const driver = () => db("driver1", verified("driver1@example.com"));
const otherDriver = () => db("driver2", verified("driver2@example.com"));
const owner = () => db("owner1", verified("owner1@example.com"));
const otherOwner = () => db("owner2", verified("owner2@example.com"));
const staff = () => db("staff1", staffToken);
const admin = () => db("admin1", verified("admin@example.com"));

test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
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
    await setDoc(doc(d, "users/driver1"), { role: "Driver", email: "driver1@example.com", userID: "driver1" });
    await setDoc(doc(d, "users/driver2"), { role: "Driver", email: "driver2@example.com" });
    await setDoc(doc(d, "users/owner1"), { role: "Parking Owner", email: "owner1@example.com" });
    await setDoc(doc(d, "users/owner2"), { role: "Parking Owner", email: "owner2@example.com" });
    await setDoc(doc(d, "users/admin1"), { role: "admin", email: "admin@example.com" });
    await setDoc(doc(d, "users/staff1"), { role: "staff" });
    await setDoc(doc(d, "establishments/est1"), { ownerId: "owner1", name: "Lot 1" });
    await setDoc(doc(d, "establishments/est2"), { ownerId: "owner2", name: "Lot 2" });
    await setDoc(doc(d, "establishment_details/est1"), { status: "pending", rates: {} });
    await setDoc(doc(d, "establishment_private/est1"), { businessDocumentUrls: ["u"] });
    await setDoc(doc(d, "staff_accounts/staff1"), {
      userId: "staff1", ownerId: "owner1", facilityId: "est1",
      email: "abc12_juan@staff.smartpark.internal",
    });
    await setDoc(doc(d, "transactions/tx1"), {
      driverId: "driver1", establishmentId: "est1", status: "paid",
      vehiclePlate: "ABC123", amount: 50,
    });
    await setDoc(doc(d, "transactions/tx2"), {
      driverId: "driver2", establishmentId: "est2", status: "paid", vehiclePlate: "XYZ9",
    });
    await setDoc(doc(d, "payment_splits/tx1"), { establishmentId: "est1", platformFeeCentavos: 250 });
    await setDoc(doc(d, "payment_splits/tx2"), { establishmentId: "est2", platformFeeCentavos: 100 });
    await setDoc(doc(d, "payments/tx1"), { driverId: "driver1", establishmentId: "est1", amount: 50 });
    await setDoc(doc(d, "activity_logs/log1"), {
      establishmentID: "est1", transactionId: "tx1", scanType: "entry", isActive: true, staffId: "staff1",
    });
  });
});

// ---------- users & roles ----------

test("a new user can pick Driver or Parking Owner", async () => {
  await assertSucceeds(setDoc(doc(db("new1", verified("n1@x.com")), "users/new1"), { role: "Driver" }));
  await assertSucceeds(setDoc(doc(db("new2", verified("n2@x.com")), "users/new2"), { role: "Parking Owner" }));
});

test("nobody can make themselves admin", async () => {
  await assertFails(setDoc(doc(db("new1", verified("n1@x.com")), "users/new1"), { role: "admin" }));
  await assertFails(setDoc(doc(db("new1", verified("n1@x.com")), "users/new1"), { Role: "admin" }));
  await assertFails(updateDoc(doc(driver(), "users/driver1"), { role: "admin" }));
  await assertFails(updateDoc(doc(driver(), "users/driver1"), { userRole: "admin" }));
  await assertFails(updateDoc(doc(driver(), "users/driver1"), { role: "Parking Owner" }));
});

test("users can edit their own profile but not others'", async () => {
  await assertSucceeds(updateDoc(doc(driver(), "users/driver1"), { firstName: "A", role: "Driver" }));
  await assertFails(updateDoc(doc(driver(), "users/driver2"), { firstName: "B" }));
  await assertFails(getDoc(doc(driver(), "users/driver2")));
  await assertSucceeds(getDoc(doc(admin(), "users/driver2")));
});

test("only real staff may take the staff role", async () => {
  await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), "users/staff1")));
  await assertSucceeds(setDoc(doc(staff(), "users/staff1"), { role: "staff" }));
  await assertFails(setDoc(doc(db("fake", staffToken), "users/fake"), { role: "staff" }));
});

test("legacy lookups only return the caller's own records", async () => {
  await assertSucceeds(getDocs(query(collection(driver(), "users"), where("userID", "==", "driver1"))));
  await assertSucceeds(getDocs(query(collection(driver(), "users"), where("email", "==", "driver1@example.com"))));
  await assertFails(getDocs(query(collection(driver(), "users"), where("email", "==", "driver2@example.com"))));
  await assertFails(getDocs(collection(driver(), "users")));
  await assertSucceeds(getDocs(collection(admin(), "users")));
});

// ---------- establishments ----------

test("owners create an establishment and details in one batch", async () => {
  const d = db("owner3", verified("o3@x.com"));
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), "users/owner3"), { role: "Parking Owner" }));
  const batch = writeBatch(d);
  batch.set(doc(d, "establishments/est3"), { ownerId: "owner3", name: "New" });
  batch.set(doc(d, "establishment_details/est3"), { status: "pending", reviewedBy: null, rejectionReason: null });
  await assertSucceeds(batch.commit());
});

test("drivers cannot create establishments", async () => {
  await assertFails(setDoc(doc(driver(), "establishments/estX"), { ownerId: "driver1" }));
});

test("owners cannot approve their own facility", async () => {
  await assertFails(updateDoc(doc(owner(), "establishment_details/est1"), { status: "approved" }));
  await assertFails(updateDoc(doc(owner(), "establishment_details/est1"), { reviewedBy: "owner1" }));
  await assertSucceeds(updateDoc(doc(owner(), "establishment_details/est1"), { rates: { car: 50 } }));
  await assertSucceeds(
    updateDoc(doc(owner(), "establishment_details/est1"), {
      status: "pending", rejectionReason: null, reviewedBy: null, resubmittedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(updateDoc(doc(admin(), "establishment_details/est1"), { status: "approved", reviewedBy: "admin1" }));
});

test("owners cannot edit someone else's establishment", async () => {
  await assertFails(updateDoc(doc(otherOwner(), "establishments/est1"), { name: "Mine now" }));
  await assertFails(updateDoc(doc(owner(), "establishments/est1"), { ownerId: "owner2" }));
  await assertFails(updateDoc(doc(otherOwner(), "establishment_details/est1"), { rates: {} }));
});

test("business documents are private to the owner and admins", async () => {
  await assertSucceeds(getDoc(doc(owner(), "establishment_private/est1")));
  await assertSucceeds(getDoc(doc(admin(), "establishment_private/est1")));
  await assertFails(getDoc(doc(driver(), "establishment_private/est1")));
  await assertFails(getDoc(doc(otherOwner(), "establishment_private/est1")));
});

test("drivers can browse establishments", async () => {
  await assertSucceeds(getDocs(query(collection(driver(), "establishment_details"), where("status", "==", "approved"))));
  await assertSucceeds(getDocs(collection(driver(), "establishments")));
});

// ---------- tickets & money ----------

test("no client can create tickets, payments or splits", async () => {
  await assertFails(setDoc(doc(driver(), "transactions/fake"), { driverId: "driver1", establishmentId: "est1", status: "paid" }));
  await assertFails(setDoc(doc(driver(), "payments/fake"), { driverId: "driver1", amount: 1 }));
  await assertFails(setDoc(doc(owner(), "payment_splits/fake"), { establishmentId: "est1" }));
  await assertFails(updateDoc(doc(admin(), "payment_splits/tx1"), { platformFeeCentavos: 0 }));
  await assertFails(setDoc(doc(driver(), "parking_checkouts/c1"), { driverId: "driver1", status: "paid" }));
});

test("drivers see only their own tickets", async () => {
  await assertSucceeds(getDocs(query(collection(driver(), "transactions"), where("driverId", "==", "driver1"))));
  await assertFails(getDoc(doc(driver(), "transactions/tx2")));
  await assertFails(getDocs(collection(driver(), "transactions")));
});

test("owners see only their own establishment's tickets and splits", async () => {
  await assertSucceeds(getDocs(query(collection(owner(), "transactions"), where("establishmentId", "==", "est1"))));
  await assertSucceeds(getDocs(query(collection(owner(), "payment_splits"), where("establishmentId", "==", "est1"))));
  await assertFails(getDocs(query(collection(owner(), "transactions"), where("establishmentId", "==", "est2"))));
  await assertFails(getDocs(collection(owner(), "payment_splits")));
  await assertSucceeds(getDocs(collection(admin(), "payment_splits")));
});

test("staff read and check in their facility's tickets only", async () => {
  await assertSucceeds(getDoc(doc(staff(), "transactions/tx1")));
  await assertFails(getDoc(doc(staff(), "transactions/tx2")));
  await assertFails(getDoc(doc(staff(), "transactions/missing")));
  await assertSucceeds(
    getDocs(query(collection(staff(), "transactions"),
      where("establishmentId", "==", "est1"), where("vehiclePlate", "in", ["ABC123", "abc123"]))),
  );
  await assertSucceeds(
    setDoc(doc(staff(), "transactions/tx1"),
      { entryStatus: "checked_in", entryAt: serverTimestamp(), entryStaffId: "staff1", entryLogId: "l", updatedAt: serverTimestamp() },
      { merge: true }),
  );
  await assertFails(updateDoc(doc(staff(), "transactions/tx1"), { status: "refunded" }));
  await assertFails(updateDoc(doc(staff(), "transactions/tx1"), { amount: 0 }));
  await assertFails(updateDoc(doc(staff(), "transactions/tx2"), { entryStatus: "checked_in" }));
});

test("staff record overtime cash as collected in their own name only", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, "transactions/tx1"), { overtimeStatus: "cash_due", overtimeAmount: 40 }, { merge: true });
    await setDoc(doc(d, "activity_logs/exit1"), {
      establishmentID: "est1", transactionId: "tx1", scanType: "exit", staffId: "staff1", overtimeStatus: "cash_due",
    });
  });
  const collectedBy = (uid) => ({
    overtimeStatus: "collected", overtimeCollectedBy: uid, overtimeCollectedAt: serverTimestamp(),
  });
  await assertFails(setDoc(doc(staff(), "transactions/tx1"), collectedBy("staff2"), { merge: true }));
  await assertFails(setDoc(doc(staff(), "activity_logs/exit1"), collectedBy("staff2"), { merge: true }));
  await assertFails(setDoc(doc(owner(), "transactions/tx1"), collectedBy("owner1"), { merge: true }));
  await assertSucceeds(
    setDoc(doc(staff(), "transactions/tx1"), { ...collectedBy("staff1"), updatedAt: serverTimestamp() }, { merge: true }),
  );
  await assertSucceeds(setDoc(doc(staff(), "activity_logs/exit1"), collectedBy("staff1"), { merge: true }));
  // The owner's live overtime card lists vehicles still checked in.
  await assertSucceeds(
    getDocs(query(collection(owner(), "transactions"),
      where("establishmentId", "==", "est1"), where("entryStatus", "==", "checked_in"))),
  );
});

test("staff log gate scans for their facility only", async () => {
  await assertSucceeds(setDoc(doc(staff(), "activity_logs/new"), { establishmentID: "est1", staffId: "staff1", scanType: "entry" }));
  await assertFails(setDoc(doc(staff(), "activity_logs/new2"), { establishmentID: "est2", staffId: "staff1" }));
  await assertFails(setDoc(doc(driver(), "activity_logs/new3"), { establishmentID: "est1", staffId: "driver1" }));
  await assertSucceeds(
    getDocs(query(collection(staff(), "activity_logs"),
      where("establishmentID", "==", "est1"), where("transactionId", "==", "tx1"),
      where("scanType", "==", "entry"), where("isActive", "==", true))),
  );
  await assertSucceeds(setDoc(doc(staff(), "activity_logs/log1"), { isActive: false }, { merge: true }));
  await assertSucceeds(setDoc(doc(staff(), "StaffActivityLogs/s1"), { staffID: "staff1", establishmentID: "est1", action: "scan_entry" }));
  await assertSucceeds(getDocs(query(collection(owner(), "activity_logs"), where("establishmentID", "==", "est1"))));
  await assertFails(getDocs(query(collection(otherOwner(), "activity_logs"), where("establishmentID", "==", "est1"))));
});

test("deactivated staff lose gate access until reactivated", async () => {
  await assertFails(updateDoc(doc(otherOwner(), "staff_accounts/staff1"), { active: false }));
  await assertSucceeds(updateDoc(doc(owner(), "staff_accounts/staff1"), { active: false }));
  await assertFails(setDoc(doc(staff(), "activity_logs/new"), { establishmentID: "est1", staffId: "staff1", scanType: "entry" }));
  await assertFails(getDocs(query(collection(staff(), "activity_logs"), where("establishmentID", "==", "est1"))));
  await assertFails(setDoc(doc(staff(), "transactions/tx1"), { entryStatus: "checked_in" }, { merge: true }));
  // They can still read their own record, to see that they were deactivated.
  await assertSucceeds(getDoc(doc(staff(), "staff_accounts/staff1")));

  await assertSucceeds(updateDoc(doc(owner(), "staff_accounts/staff1"), { active: true }));
  await assertSucceeds(setDoc(doc(staff(), "activity_logs/new"), { establishmentID: "est1", staffId: "staff1", scanType: "entry" }));
});

// ---------- staff accounts ----------

test("owners manage staff for their own facility only", async () => {
  await assertSucceeds(
    setDoc(doc(owner(), "staff_accounts/staff9"), { userId: "staff9", ownerId: "owner1", facilityId: "est1" }),
  );
  await assertFails(
    setDoc(doc(owner(), "staff_accounts/staff8"), { userId: "staff8", ownerId: "owner1", facilityId: "est2" }),
  );
  await assertFails(
    setDoc(doc(owner(), "staff_accounts/random"), { userId: "staff7", ownerId: "owner1", facilityId: "est1" }),
  );
  await assertFails(
    setDoc(doc(driver(), "staff_accounts/driver1"), { userId: "driver1", ownerId: "driver1", facilityId: "est1" }),
  );
  await assertSucceeds(getDocs(query(collection(owner(), "staff_accounts"), where("ownerId", "==", "owner1"))));
  await assertSucceeds(getDocs(query(collection(staff(), "staff_accounts"), where("userId", "==", "staff1"))));
  await assertFails(deleteDoc(doc(otherOwner(), "staff_accounts/staff1")));
  await assertSucceeds(deleteDoc(doc(owner(), "staff_accounts/staff1")));
});

test("stats are admin-only and read-only", async () => {
  await assertSucceeds(getDocs(collection(admin(), "stats_daily")));
  await assertFails(getDocs(collection(owner(), "stats_daily")));
  await assertFails(setDoc(doc(admin(), "stats/platform"), { commissionCentavos: 1 }));
});

test("occupancy is readable by signed-in users and written by the server only", async () => {
  await assertSucceeds(getDoc(doc(driver(), "establishment_occupancy/est1")));
  await assertSucceeds(getDoc(doc(staff(), "establishment_occupancy/est1")));
  await assertFails(getDoc(doc(db(null), "establishment_occupancy/est1")));
  await assertFails(setDoc(doc(owner(), "establishment_occupancy/est1"), { total: 0 }));
});

test("staff record walk-ins for their facility only", async () => {
  const walkIn = {
    establishmentId: "est1", ownerId: "owner1", source: "walk_in", status: "walk_in",
    entryStatus: "checked_in", entryAt: serverTimestamp(), entryStaffId: "staff1",
    entryLogId: "l1", vehicleType: "car", vehiclePlate: "", createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
  await assertSucceeds(setDoc(doc(staff(), "transactions/w1"), walkIn));
  await assertFails(setDoc(doc(staff(), "transactions/w2"), { ...walkIn, establishmentId: "est2" }));
  await assertFails(setDoc(doc(staff(), "transactions/w3"), { ...walkIn, status: "paid" }));
  await assertFails(setDoc(doc(staff(), "transactions/w4"), { ...walkIn, amount: 100 }));
  await assertFails(setDoc(doc(staff(), "transactions/w5"), { ...walkIn, driverId: "driver1" }));
  await assertFails(setDoc(doc(driver(), "transactions/w6"), { ...walkIn, entryStaffId: "driver1" }));
  await assertSucceeds(
    getDocs(query(collection(staff(), "transactions"),
      where("establishmentId", "==", "est1"), where("source", "==", "walk_in"),
      where("entryStatus", "==", "checked_in"))),
  );
  await assertSucceeds(
    updateDoc(doc(staff(), "transactions/w1"),
      { entryStatus: "checked_out", exitAt: serverTimestamp(), exitStaffId: "staff1",
        exitLogId: "l2", staySeconds: 60, updatedAt: serverTimestamp() }),
  );
});

test("unknown collections are closed", async () => {
  await assertFails(setDoc(doc(admin(), "anything/else"), { a: 1 }));
  await assertFails(getDoc(doc(driver(), "anything/else")));
});
