// Live slot occupancy per establishment, readable by every signed-in user
// (drivers cannot read other people's tickets, so they cannot count them).
// Recounted from the checked-in tickets on every relevant ticket change, so
// the numbers heal themselves instead of drifting.

const { FieldValue } = require("firebase-admin/firestore");

const OCCUPANCY = "establishment_occupancy";

function vehicleKey(value) {
  const key = String(value || "car").trim().toLowerCase();
  return key === "motor" ? "motorcycle" : key;
}

/** Counts checked-in tickets per vehicle type: { car: n, motorcycle: m }. */
function tallyOccupancy(tickets) {
  const occupied = { car: 0, motorcycle: 0 };
  for (const ticket of tickets) {
    const key = vehicleKey(ticket.vehicleType);
    occupied[key] = (occupied[key] || 0) + 1;
  }
  return occupied;
}

async function recountOccupancy(db, establishmentId) {
  if (!establishmentId) return;
  const snapshot = await db
    .collection("transactions")
    .where("establishmentId", "==", establishmentId)
    .where("entryStatus", "==", "checked_in")
    .get();
  const occupied = tallyOccupancy(snapshot.docs.map((d) => d.data()));
  const total = Object.values(occupied).reduce((sum, n) => sum + n, 0);
  await db.collection(OCCUPANCY).doc(establishmentId).set({
    establishmentId,
    occupied,
    total,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

/** Establishments whose occupancy a ticket change can affect. */
function affectedEstablishments(before, after) {
  const relevant = (t) => [t?.establishmentId, t?.entryStatus, vehicleKey(t?.vehicleType)];
  const a = relevant(before);
  const b = relevant(after);
  if (before && after && a.every((v, i) => v === b[i])) return [];
  return [...new Set([before?.establishmentId, after?.establishmentId].filter(Boolean))];
}

module.exports = {
  OCCUPANCY,
  tallyOccupancy,
  recountOccupancy,
  affectedEstablishments,
};
