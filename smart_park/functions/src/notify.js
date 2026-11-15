// Push notices to one account's phones (users/{uid}.fcmTokens, saved by the
// app's ParkingPush). Always best effort: a notice that can't be sent never
// fails the work it is about.

const { FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { logger } = require("firebase-functions");

/** Centavos as pesos, e.g. 12550 -> "PHP 125.50". */
function peso(centavos) {
  return `PHP ${(Math.max(0, Number(centavos) || 0) / 100).toFixed(2)}`;
}

const DEAD_TOKEN_CODES = [
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
];

/** FCM data values must all be strings. */
function stringData(data) {
  const out = {};
  for (const [key, value] of Object.entries(data || {})) {
    if (value !== undefined && value !== null) out[key] = String(value);
  }
  return out;
}

/** Sends { title, body, data } to every phone [uid] is signed in on. */
async function notifyUser(db, uid, { title, body, data }) {
  if (!uid) return 0;
  try {
    const ref = db.collection("users").doc(uid);
    const user = (await ref.get()).data() || {};
    const tokens = Array.isArray(user.fcmTokens) ? user.fcmTokens.filter(Boolean) : [];
    if (!tokens.length) return 0;
    const result = await getMessaging().sendEachForMulticast({
      notification: { title, body },
      data: stringData(data),
      android: { priority: "high" },
      tokens,
    });
    const dead = tokens.filter((_, i) =>
      DEAD_TOKEN_CODES.includes(result.responses[i]?.error?.code || ""),
    );
    if (dead.length) await ref.update({ fcmTokens: FieldValue.arrayRemove(...dead) });
    return result.successCount;
  } catch (error) {
    logger.warn(`Could not notify ${uid}`, error);
    return 0;
  }
}

module.exports = { peso, stringData, notifyUser };
