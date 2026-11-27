// Facility ratings: after parking, a driver rates the facility 1-5 stars
// (with an optional comment), once per facility and editable. Ratings live
// in facility_ratings/{driverId}_{establishmentId}; security rules check
// the driver has a used ticket there. Older ratings were saved once per
// ticket, so a driver may have several: only their newest one counts. This module keeps each facility's average on
// establishment_details (rating, ratingCount), which only the server
// writes, so an owner can't set their own score.

const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions");

/** { rating, ratingCount } from star values: average to one decimal. */
function ratingSummary(stars) {
  const valid = stars
    .map(Number)
    .filter((s) => Number.isInteger(s) && s >= 1 && s <= 5);
  if (!valid.length) return { rating: 0, ratingCount: 0 };
  const sum = valid.reduce((a, b) => a + b, 0);
  return { rating: Math.round((sum / valid.length) * 10) / 10, ratingCount: valid.length };
}

function millis(value) {
  return value && typeof value.toMillis === "function" ? value.toMillis() : 0;
}

/** Each driver's newest rating among [ratings] (rating documents' data). */
function latestPerDriver(ratings) {
  const byDriver = new Map();
  let anonymous = 0;
  for (const r of ratings) {
    const key = r.driverId || `#${anonymous++}`;
    const kept = byDriver.get(key);
    const at = millis(r.updatedAt) || millis(r.createdAt);
    if (!kept || at > (millis(kept.updatedAt) || millis(kept.createdAt))) byDriver.set(key, r);
  }
  return [...byDriver.values()];
}

/** Trigger on facility_ratings: recounts the facility(ies) it touched. */
async function onRatingWritten(before, after) {
  const ids = new Set([before?.establishmentId, after?.establishmentId].filter(Boolean));
  const db = getFirestore();
  for (const id of ids) {
    try {
      const snap = await db.collection("facility_ratings").where("establishmentId", "==", id).get();
      const ratings = latestPerDriver(snap.docs.map((d) => d.data()));
      const summary = ratingSummary(ratings.map((r) => r.stars));
      await db
        .collection("establishment_details")
        .doc(id)
        .set(
          summary.ratingCount
            ? summary
            : { rating: FieldValue.delete(), ratingCount: FieldValue.delete() },
          { merge: true },
        );
    } catch (error) {
      logger.warn(`Could not update the rating of facility ${id}`, error);
    }
  }
}

module.exports = { ratingSummary, latestPerDriver, onRatingWritten };
