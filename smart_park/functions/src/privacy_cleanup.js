// Business documents (permits, registrations) of a facility SmartPark
// rejected or deactivated are deleted 90 days after that decision, as the
// Privacy Notice says. Until then the owner can still ask for a review or
// resubmit with them. After it, resubmitting asks for new documents (the
// registration form requires at least one). Runs in the daily 06:00 job.
//
// Deleted: establishment_private/{id} (document links, permit expiry) and
// the files establishments/{id}/document_* in Storage. The facility's
// public listing and its ticket and payment records are kept.

const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { logger } = require("firebase-functions");

const audit = require("./audit");

const DOCUMENT_RETENTION_DAYS = 90;
const RETENTION_MS = DOCUMENT_RETENTION_DAYS * 24 * 60 * 60 * 1000;
const CLOSED_STATUSES = ["rejected", "deactivated"];

function millis(value) {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  return null;
}

/**
 * Whether a facility's business documents are due for deletion: it has
 * been rejected or deactivated for [DOCUMENT_RETENTION_DAYS] days, counted
 * from the decision (reviewedAt, else the last update). Pure.
 */
function documentsDue(details, nowMs) {
  const status = String(details?.status || "").toLowerCase();
  if (!CLOSED_STATUSES.includes(status)) return false;
  const since = millis(details.reviewedAt) ?? millis(details.updatedAt);
  if (since === null) return false;
  return nowMs - since >= RETENTION_MS;
}

/** The daily job. Never throws; returns how many facilities it cleared. */
async function deleteStaleBusinessDocuments(nowMs = Date.now()) {
  const db = getFirestore();
  let cleared = 0;
  let closed;
  try {
    closed = await db.collection("establishment_details").where("status", "in", CLOSED_STATUSES).get();
  } catch (error) {
    logger.error("Could not list closed facilities for document cleanup", error);
    return 0;
  }
  for (const doc of closed.docs) {
    const details = doc.data();
    if (!documentsDue(details, nowMs)) continue;
    try {
      const privateRef = db.collection("establishment_private").doc(doc.id);
      const hadRecord = (await privateRef.get()).exists;
      const [files] = await getStorage()
        .bucket()
        .getFiles({ prefix: `establishments/${doc.id}/document_` });
      if (!hadRecord && files.length === 0) continue; // already cleared

      await Promise.all(files.map((f) => f.delete({ ignoreNotFound: true })));
      if (hadRecord) await privateRef.delete();
      await doc.ref.update({
        businessDocumentsDeletedAt: FieldValue.serverTimestamp(),
      });
      const base = (await db.collection("establishments").doc(doc.id).get()).data() || {};
      await audit.record(db, {
        action: "privacy.documents_deleted",
        summary:
          `Deleted the business documents ${DOCUMENT_RETENTION_DAYS} days after the facility was ` +
          `${String(details.status).toLowerCase()}`,
        actorName: "SmartPark (automatic)",
        actorRole: "system",
        targetType: "facility",
        targetId: doc.id,
        establishmentId: doc.id,
        establishmentName: String(base.name || details.name || ""),
        ownerId: String(base.ownerId || details.ownerId || ""),
        details: { files: files.length },
      });
      cleared++;
    } catch (error) {
      logger.warn(`Could not delete business documents of ${doc.id}`, error);
    }
  }
  if (cleared > 0) logger.info(`Deleted business documents of ${cleared} closed facilities.`);
  return cleared;
}

module.exports = {
  DOCUMENT_RETENTION_DAYS,
  documentsDue,
  deleteStaleBusinessDocuments,
};
