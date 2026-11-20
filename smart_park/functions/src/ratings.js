// Facility ratings: after parking, a driver rates the facility 1-5 stars
// (with an optional comment), once per ticket and editable. Ratings live in
// facility_ratings/{ticketId}; security rules check the ticket is the
// driver's and has been used. This module keeps each facility's average on
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

/** Trigger on facility_ratings: recounts the facility(ies) it touched. */
async function onRatingWritten(before, after) {
  const ids = new Set([before?.establishmentId, after?.establishmentId].filter(Boolean));
  const db = getFirestore();
  for (const id of ids) {
    try {
      const snap = await db.collection("facility_ratings").where("establishmentId", "==", id).get();
      const summary = ratingSummary(snap.docs.map((d) => d.data().stars));
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

module.exports = { ratingSummary, onRatingWritten };
