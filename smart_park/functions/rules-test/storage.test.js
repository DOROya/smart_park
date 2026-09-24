// Storage security rules tests (run under the Firestore + Storage emulators;
// the storage rules look up establishment owners in Firestore).

const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { doc, setDoc } = require("firebase/firestore");
const { ref, uploadBytes, getBytes, deleteObject } = require("firebase/storage");

let env;
const image = new Uint8Array([0xff, 0xd8, 0xff]);
const jpeg = { contentType: "image/jpeg" };

const storageFor = (uid) =>
  uid
    ? env.authenticatedContext(uid, { email_verified: true }).storage()
    : env.unauthenticatedContext().storage();

test.before(async () => {
  const root = path.join(__dirname, "..", "..");
  env = await initializeTestEnvironment({
    projectId: "demo-smartpark",
    firestore: { rules: fs.readFileSync(path.join(root, "firestore.rules"), "utf8") },
    storage: { rules: fs.readFileSync(path.join(root, "storage.rules"), "utf8") },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, "establishments/est1"), { ownerId: "owner1" });
    await setDoc(doc(d, "users/admin1"), { role: "admin" });
    await setDoc(doc(d, "users/driver1"), { role: "Driver" });
    const s = ctx.storage();
    await uploadBytes(ref(s, "establishments/est1/photo_1.jpg"), image, jpeg);
    await uploadBytes(ref(s, "establishments/est1/document_1.jpg"), image, jpeg);
  });
});

test.after(async () => {
  await env.cleanup();
});

test("only the owner uploads photos and documents", async () => {
  await assertSucceeds(uploadBytes(ref(storageFor("owner1"), "establishments/est1/photo_2.jpg"), image, jpeg));
  await assertSucceeds(uploadBytes(ref(storageFor("owner1"), "establishments/est1/document_2.jpg"), image, jpeg));
  await assertFails(uploadBytes(ref(storageFor("driver1"), "establishments/est1/photo_3.jpg"), image, jpeg));
  await assertFails(uploadBytes(ref(storageFor("owner1"), "establishments/est1/other.jpg"), image, jpeg));
  await assertFails(
    uploadBytes(ref(storageFor("owner1"), "establishments/est1/photo_4.jpg"), image, { contentType: "text/plain" }),
  );
});

test("photos are public, documents are owner/admin only", async () => {
  await assertSucceeds(getBytes(ref(storageFor(null), "establishments/est1/photo_1.jpg")));
  await assertSucceeds(getBytes(ref(storageFor("owner1"), "establishments/est1/document_1.jpg")));
  await assertSucceeds(getBytes(ref(storageFor("admin1"), "establishments/est1/document_1.jpg")));
  await assertFails(getBytes(ref(storageFor("driver1"), "establishments/est1/document_1.jpg")));
});

test("other users cannot delete an establishment's files", async () => {
  await assertFails(deleteObject(ref(storageFor("driver1"), "establishments/est1/photo_1.jpg")));
  await assertSucceeds(deleteObject(ref(storageFor("owner1"), "establishments/est1/photo_1.jpg")));
});
