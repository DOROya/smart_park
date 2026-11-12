const test = require("node:test");
const assert = require("node:assert/strict");
const sharp = require("sharp");

const {
  COMPRESSED_FLAG,
  MIN_BYTES,
  profileFor,
  shouldCompress,
  compressImage,
} = require("../src/photo_compress");

test("only the app's photo and document paths are compressed", () => {
  assert.equal(profileFor("establishments/abc/photo_1_0.jpg").maxSize, 1600);
  assert.equal(profileFor("establishments/abc/document_1_0.jpg").maxSize, 2400);
  assert.equal(profileFor("establishments/abc.jpg"), null);
  assert.equal(profileFor("receipts/abc/photo_1.jpg"), null);
  assert.equal(profileFor("establishments/abc/nested/photo_1.jpg"), null);
});

test("small, already-compressed or non-image objects are skipped", () => {
  const big = MIN_BYTES + 1;
  const name = "establishments/abc/photo_1_0.jpg";
  assert.equal(shouldCompress({ name, size: big, contentType: "image/jpeg" }), true);
  assert.equal(shouldCompress({ name, size: 1000, contentType: "image/jpeg" }), false);
  assert.equal(
    shouldCompress({
      name,
      size: big,
      contentType: "image/jpeg",
      metadata: { [COMPRESSED_FLAG]: "1" },
    }),
    false,
  );
  assert.equal(shouldCompress({ name, size: big, contentType: "application/pdf" }), false);
});

test("a large photo is shrunk to fit the cap as a JPEG", async () => {
  const original = await sharp({
    create: { width: 4000, height: 3000, channels: 3, background: "#3a7" },
  })
    .jpeg({ quality: 100 })
    .toBuffer();
  const out = await compressImage(original, { maxSize: 1600, quality: 80 });
  const meta = await sharp(out).metadata();
  assert.equal(meta.format, "jpeg");
  assert.equal(meta.width, 1600);
  assert.equal(meta.height, 1200);
  assert.ok(out.length < original.length);
});
