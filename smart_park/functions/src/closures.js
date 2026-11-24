// Temporary closures ("Closed until", docs/quick-fixes.md item 2). The owner
// or supervisor sets establishment_details.closedUntil; the app and the
// rules compare it with the current time, so the facility reopens by
// itself. Here: drivers holding the facility's tickets or temporary QRs get
// one push notice when a closure is set (tickets aren't reservations and
// their hours don't run down while not parked, so nothing is refunded).

const { getFirestore } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions");

const { notifyUser } = require("./notify");
const { hoursLeft } = require("./refunds");

function millis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  return typeof value === "number" ? value : null;
}

/** "Nov 25, 3:00 PM" in Philippine time. */
function manilaLabel(ms) {
  const d = new Date(ms);
  const date = d.toLocaleDateString("en-US", { timeZone: "Asia/Manila", month: "short", day: "numeric" });
  const time = d.toLocaleTimeString("en-US", { timeZone: "Asia/Manila", hour: "numeric", minute: "2-digit" });
  return `${date}, ${time}`;
}

/** The closure end to announce, or null: a new or moved closedUntil. */
function newClosureUntil(before, after, nowMs) {
  const until = millis(after?.closedUntil);
  if (until === null || until <= nowMs) return null;
  return until === millis(before?.closedUntil) ? null : until;
}

/** The notice for drivers of [name]. */
function closureNotice(name, untilMs, reason) {
  const why = String(reason || "").trim();
  return {
    title: `${name || "A facility"} is closed for now`,
    body:
      `Closed until ${manilaLabel(untilMs)}${why ? ` (${why})` : ""}. ` +
      "Your ticket or temporary QR stays valid for when it reopens.",
    data: { kind: "facility_closed" },
  };
}

/** Trigger part, on establishment_details writes. */
async function onClosureChange(establishmentId, before, after) {
  const until = newClosureUntil(before, after, Date.now());
  if (until === null) return 0;
  const db = getFirestore();
  try {
    const [tickets, passes, facility] = await Promise.all([
      db.collection("transactions").where("establishmentId", "==", establishmentId).where("status", "==", "paid").get(),
      db
        .collection("parking_checkouts")
        .where("establishmentId", "==", establishmentId)
        .where("kind", "==", "gate_pass")
        .where("status", "==", "awaiting_gate")
        .get(),
      db.collection("establishments").doc(establishmentId).get(),
    ]);
    const drivers = new Set();
    for (const d of tickets.docs) {
      if (d.data().driverId && hoursLeft(d.data()) > 0) drivers.add(d.data().driverId);
    }
    for (const d of passes.docs) if (d.data().driverId) drivers.add(d.data().driverId);
    const notice = closureNotice(facility.data()?.name || after?.name, until, after?.closedReason);
    let sent = 0;
    for (const driverId of drivers) sent += await notifyUser(db, driverId, notice);
    return sent;
  } catch (error) {
    logger.warn(`Could not tell drivers that ${establishmentId} closed`, error);
    return 0;
  }
}

module.exports = { newClosureUntil, closureNotice, manilaLabel, onClosureChange };
