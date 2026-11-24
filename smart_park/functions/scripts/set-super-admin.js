// One-time setup for admin access levels (docs/admin-roles.md, section 0).
// Makes the first super admin, and gives every other existing admin the
// normal level so they are the only super admin at the start.
//
//   cd functions && node scripts/set-super-admin.js
//
// Needs Application Default Credentials for smartpark-87e3d
// (gcloud auth application-default login). Safe to run again.

const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const PROJECT = "smartpark-87e3d";
const FIRST_SUPER_ADMIN = "GWBK5QsdMNMHdPDjiPgrd7g3u3C2";

async function main() {
  initializeApp({ projectId: PROJECT });
  const db = getFirestore();
  const admins = await db.collection("users").where("role", "==", "admin").get();
  const batch = db.batch();
  let normal = 0;
  for (const doc of admins.docs) {
    if (doc.id === FIRST_SUPER_ADMIN || doc.data().adminLevel) continue;
    batch.update(doc.ref, { adminLevel: "admin" });
    normal++;
  }
  batch.set(
    db.collection("users").doc(FIRST_SUPER_ADMIN),
    {
      role: "admin",
      adminLevel: "super",
      adminSince: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await batch.commit();
  console.log(`Super admin set for ${FIRST_SUPER_ADMIN}; ${normal} other admin(s) set to "admin".`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
