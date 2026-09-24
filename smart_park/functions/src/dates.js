// Daily stats are bucketed by Philippine calendar day (UTC+8, no DST).

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;

/** "YYYY-MM-DD" for the Manila calendar day containing [date]. */
function dayKeyManila(date) {
  return new Date(date.getTime() + MANILA_OFFSET_MS).toISOString().slice(0, 10);
}

/** Instant at which the Manila day [dayKey] starts. */
function dayStartManila(dayKey) {
  return new Date(Date.parse(`${dayKey}T00:00:00Z`) - MANILA_OFFSET_MS);
}

module.exports = { dayKeyManila, dayStartManila };
