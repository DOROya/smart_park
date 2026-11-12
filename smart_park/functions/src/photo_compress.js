// Shrinks facility photos and business-document photos in Storage.
//
// Owners used to upload camera originals (6-7 MB, 4000 px+), which drivers
// on mobile data waited seconds for. Each upload is now re-encoded in place
// to a phone-sized JPEG. The object keeps its path and its download token,
// so every saved URL in Firestore keeps working.

const sharp = require("sharp");

/** Marks an object this module already wrote, so its own save is skipped. */
const COMPRESSED_FLAG = "smartparkCompressed";

/** Objects under this size are left alone; re-encoding saves too little. */
const MIN_BYTES = 400 * 1024;

const PROFILES = {
  // Same cap the app applies when an owner picks a photo.
  photo: { maxSize: 1600, quality: 80 },
  // Larger so permit text stays readable when an admin zooms in.
  document: { maxSize: 2400, quality: 85 },
};

/**
 * Which profile an object path gets, or null to leave it alone. Only the
 * paths the app uploads to: establishments/{id}/photo_*.jpg and
 * establishments/{id}/document_*.jpg.
 */
function profileFor(objectName) {
  const match = /^establishments\/[^/]+\/(photo|document)_[^/]+$/.exec(
    String(objectName || ""),
  );
  return match ? PROFILES[match[1]] : null;
}

/** Whether a finalized object should be compressed. */
function shouldCompress({ name, size, contentType, metadata }) {
  if (!profileFor(name)) return false;
  if (metadata && metadata[COMPRESSED_FLAG]) return false;
  if (contentType && !String(contentType).startsWith("image/")) return false;
  return Number(size) >= MIN_BYTES;
}

/** Re-encodes JPEG/PNG/HEIC bytes as an upright, size-capped JPEG. */
async function compressImage(buffer, { maxSize, quality }) {
  return sharp(buffer, { failOn: "none" })
    .rotate() // apply the camera's EXIF orientation before it is stripped
    .resize({
      width: maxSize,
      height: maxSize,
      fit: "inside",
      withoutEnlargement: true,
    })
    .jpeg({ quality, mozjpeg: true })
    .toBuffer();
}

/**
 * Compresses one Storage object in place. Returns
 * { name, before, after, skipped } for logging and the backfill summary.
 */
async function compressObject(file) {
  const [meta] = await file.getMetadata();
  const info = {
    name: file.name,
    size: meta.size,
    contentType: meta.contentType,
    metadata: meta.metadata,
  };
  if (!shouldCompress(info)) {
    return { name: file.name, before: Number(meta.size), skipped: true };
  }

  const [original] = await file.download();
  const compressed = await compressImage(original, profileFor(file.name));
  // Keep the custom metadata, above all firebaseStorageDownloadTokens: the
  // app's saved download URLs depend on it.
  const customMetadata = { ...(meta.metadata || {}), [COMPRESSED_FLAG]: "1" };

  if (compressed.length >= original.length * 0.9) {
    // Already efficient; just mark it so it isn't looked at again.
    await file.setMetadata({ metadata: customMetadata });
    return {
      name: file.name,
      before: original.length,
      after: original.length,
      skipped: true,
    };
  }

  await file.save(compressed, {
    resumable: false,
    contentType: "image/jpeg",
    metadata: {
      cacheControl: meta.cacheControl,
      metadata: customMetadata,
    },
  });
  return {
    name: file.name,
    before: original.length,
    after: compressed.length,
    skipped: false,
  };
}

/** Compresses every facility photo and document already in the bucket. */
async function compressAllExisting(bucket) {
  const [files] = await bucket.getFiles({ prefix: "establishments/" });
  const summary = { checked: 0, compressed: 0, bytesBefore: 0, bytesAfter: 0 };
  for (const file of files) {
    if (!profileFor(file.name)) continue;
    summary.checked += 1;
    try {
      const result = await compressObject(file);
      if (!result.skipped) {
        summary.compressed += 1;
        summary.bytesBefore += result.before;
        summary.bytesAfter += result.after;
      }
    } catch (error) {
      console.error(`Could not compress ${file.name}`, error);
    }
  }
  return summary;
}

module.exports = {
  COMPRESSED_FLAG,
  MIN_BYTES,
  profileFor,
  shouldCompress,
  compressImage,
  compressObject,
  compressAllExisting,
};
