// Audit trail: who did what, and when, to facilities, staff, refunds,
// warnings and reports. Entries live in `audit_logs`, written only here
// (the rules deny every client write) and never edited or deleted.
// Admins read all of them; a parking owner reads the ones about their own
// facility and staff (entries carrying their ownerId).
//
// Two sources:
//  - Firestore triggers with auth context, for changes the app writes
//    directly (an owner editing rates, an admin approving a facility).
//    In production a client write arrives as authType "api_key" with
//    authId = the user's uid. Writes by Cloud Functions themselves
//    ("service_account", "system") are skipped: the callables below log
//    those with their reason.
//  - Callables wrapped with `audited`, which log after the work succeeds.
//
// Logging is best effort: a failed audit write never fails the work.

const { getFirestore, FieldValue, Timestamp, GeoPoint } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions");

const COLLECTION = "audit_logs";

// Changes to these alone are bookkeeping, not actions worth recording.
const IGNORED_FIELDS = new Set([
  "updatedAt",
  "createdAt",
  "isOnline",
  "lastSeen",
  "lastSeenAt",
  "lastActiveAt",
  "rating",
  "ratingCount",
  "fcmTokens",
]);

const MAX_CHANGED_FIELDS = 25;
const MAX_VALUE_CHARS = 300;

/** A value as it is shown in an entry: short, and plain JSON. */
function summarizeValue(value) {
  if (value === undefined || value === null) return null;
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (value instanceof GeoPoint) return `${value.latitude}, ${value.longitude}`;
  if (typeof value === "string") {
    return value.length > MAX_VALUE_CHARS ? `${value.slice(0, MAX_VALUE_CHARS)}...` : value;
  }
  if (typeof value === "number" || typeof value === "boolean") return value;
  let text;
  try {
    text = JSON.stringify(value, (_, v) =>
      v instanceof Timestamp ? v.toDate().toISOString() : v,
    );
  } catch (_) {
    text = String(value);
  }
  return text.length > MAX_VALUE_CHARS ? `${text.slice(0, MAX_VALUE_CHARS)}...` : text;
}

function sameValue(a, b) {
  if (a instanceof Timestamp && b instanceof Timestamp) return a.isEqual(b);
  if (a === b) return true;
  if (a === undefined || b === undefined || a === null || b === null) {
    return (a ?? null) === (b ?? null);
  }
  try {
    return JSON.stringify(a) === JSON.stringify(b);
  } catch (_) {
    return false;
  }
}

/**
 * The fields that changed between [before] and [after] (either may be
 * missing), as { field: { from, to } }, leaving out bookkeeping fields.
 */
function fieldChanges(before, after) {
  const changes = {};
  const keys = new Set([...Object.keys(before || {}), ...Object.keys(after || {})]);
  for (const key of [...keys].sort()) {
    if (IGNORED_FIELDS.has(key)) continue;
    const from = before?.[key];
    const to = after?.[key];
    if (sameValue(from, to)) continue;
    if (Object.keys(changes).length >= MAX_CHANGED_FIELDS) {
      changes["..."] = { from: null, to: "more fields changed" };
      break;
    }
    changes[key] = { from: summarizeValue(from), to: summarizeValue(to) };
  }
  return changes;
}

/**
 * Who made a direct Firestore write, from a trigger's auth context: their
 * uid, or "" when Firestore didn't say. null for writes made by the server
 * itself, which are not logged from triggers.
 */
function actorFromEvent(event) {
  const type = String(event?.authType || "");
  if (type === "service_account" || type === "system") return null;
  return String(event?.authId || "").trim();
}

const FACILITY_STATUS_ACTIONS = {
  approved: ["facility.approved", "Approved the facility"],
  rejected: ["facility.rejected", "Rejected the facility"],
  suspended: ["facility.suspended", "Suspended the facility"],
  deactivated: ["facility.deactivated", "Deactivated the facility"],
  pending: ["facility.submitted", "Submitted the facility for review"],
};

/** establishment_details: review decisions, notices and edits. */
function describeFacilityDetails(before, after, changes) {
  if (!before && after) {
    return { action: "facility.submitted", summary: "Submitted a new facility for review" };
  }
  if (before && !after) return { action: "facility.deleted", summary: "Deleted the facility" };
  if (Object.keys(changes).length === 0) return null;
  const status = String(after.status || "pending").toLowerCase();
  if (changes.status) {
    const [action, summary] = FACILITY_STATUS_ACTIONS[status] || [
      "facility.status_changed",
      `Changed the facility's status to ${status}`,
    ];
    const reason = after.rejectionReason || after.restrictionReason;
    return { action, summary: reason && status !== "approved" ? `${summary}: ${reason}` : summary };
  }
  if (changes.complianceNotice) {
    return after.complianceNotice
      ? { action: "facility.notice_given", summary: "Gave the facility a notice to fix something" }
      : { action: "facility.notice_cleared", summary: "Cleared the facility's notice" };
  }
  return {
    action: "facility.details_updated",
    summary: `Edited facility details (${Object.keys(changes).join(", ")})`,
  };
}

/** establishments: the listing drivers see, including the rates. */
function describeEstablishment(before, after, changes) {
  if (!before && after) return { action: "facility.created", summary: "Created the facility listing" };
  if (before && !after) return { action: "facility.deleted", summary: "Deleted the facility listing" };
  const fields = Object.keys(changes);
  if (fields.length === 0) return null;
  const rateFields = fields.filter((f) => /rate|price|fee|grace|overtime/i.test(f));
  if (rateFields.length > 0) {
    return { action: "facility.rates_changed", summary: `Changed rates (${fields.join(", ")})` };
  }
  return { action: "facility.updated", summary: `Edited the facility listing (${fields.join(", ")})` };
}

/** staff_accounts: added, deactivated, reactivated, removed. */
function describeStaff(before, after, changes) {
  const name = (after || before)?.name || "a staff member";
  if (!before && after) return { action: "staff.added", summary: `Added staff member ${name}` };
  if (before && !after) return { action: "staff.removed", summary: `Removed staff member ${name}` };
  if (Object.keys(changes).length === 0) return null;
  if (changes.active) {
    return after.active === false
      ? { action: "staff.deactivated", summary: `Deactivated staff member ${name}` }
      : { action: "staff.reactivated", summary: `Reactivated staff member ${name}` };
  }
  return {
    action: "staff.updated",
    summary: `Edited staff member ${name} (${Object.keys(changes).join(", ")})`,
  };
}

/** driver_warnings: an admin warns, a driver contests, an admin decides. */
function describeWarning(before, after, changes) {
  const driver = (after || before)?.driverName || "a driver";
  if (!before && after) return { action: "driver.warned", summary: `Warned ${driver}` };
  if (before && !after) return { action: "driver.warning_withdrawn", summary: `Withdrew a warning to ${driver}` };
  const fields = Object.keys(changes).filter((f) => f !== "acknowledgedAt");
  if (fields.length === 0) return null;
  if (changes.contestMessage) {
    return { action: "driver.warning_contested", summary: `${driver} contested a warning` };
  }
  return { action: "driver.warning_updated", summary: `Updated a warning to ${driver} (${fields.join(", ")})` };
}

/** driver_reports / facility_reports: an admin handles a report. */
function describeReport(kind) {
  return (before, after, changes) => {
    if (!before || !after) return null; // creation already alerts admins
    if (Object.keys(changes).length === 0) return null;
    const subject =
      kind === "driver" ? after.driverName || "a driver" : after.establishmentName || "a facility";
    const status = String(after.status || "");
    if (changes.status) {
      return {
        action: `report.${status || "updated"}`,
        summary: `Marked a report about ${subject} as ${status}`,
      };
    }
    return { action: "report.updated", summary: `Updated a report about ${subject}` };
  };
}

/** Name and role of [uid], for showing in an entry. */
async function resolveActor(db, uid) {
  if (!uid) return { actorId: "", actorName: "Unknown", actorRole: "" };
  try {
    const profile = (await db.collection("users").doc(uid).get()).data();
    if (profile) {
      const name = [profile.firstName, profile.lastName].filter(Boolean).join(" ").trim();
      return {
        actorId: uid,
        actorName: name || profile.email || profile.name || uid,
        actorRole: String(profile.role || profile.Role || profile.userRole || ""),
      };
    }
    const staff = (await db.collection("staff_accounts").doc(uid).get()).data();
    if (staff) return { actorId: uid, actorName: staff.name || uid, actorRole: "staff" };
  } catch (error) {
    logger.warn(`Could not load audit actor ${uid}`, error);
  }
  return { actorId: uid, actorName: uid, actorRole: "" };
}

/** Owner and name of a facility, for entries about it. */
async function facilityInfo(db, establishmentId, data) {
  if (!establishmentId) return { ownerId: "", establishmentName: "" };
  let base = {};
  try {
    base = (await db.collection("establishments").doc(establishmentId).get()).data() || {};
  } catch (error) {
    logger.warn(`Could not load facility ${establishmentId} for the audit log`, error);
  }
  return {
    ownerId: String(base.ownerId || data?.ownerId || "").trim(),
    establishmentName: String(base.name || data?.name || data?.establishmentName || "").trim(),
  };
}

/** Writes one entry. Never throws. */
async function record(db, entry) {
  try {
    await db.collection(COLLECTION).add({
      action: entry.action,
      summary: entry.summary || "",
      actorId: entry.actorId || "",
      actorName: entry.actorName || "",
      actorRole: entry.actorRole || "",
      targetType: entry.targetType || "",
      targetId: entry.targetId || "",
      establishmentId: entry.establishmentId || "",
      establishmentName: entry.establishmentName || "",
      // Lets the facility's owner read the entry; "" keeps it admin-only.
      ownerId: entry.ownerId || "",
      changes: entry.changes || {},
      details: entry.details || {},
      at: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    logger.error(`Could not write audit entry ${entry.action}`, error);
  }
}

// How each watched collection is described, and who may read its entries.
const WATCHED = {
  establishment_details: {
    targetType: "facility",
    describe: describeFacilityDetails,
    facilityId: (id) => id,
    ownerVisible: true,
  },
  establishments: {
    targetType: "facility",
    describe: describeEstablishment,
    facilityId: (id) => id,
    ownerVisible: true,
  },
  staff_accounts: {
    targetType: "staff",
    describe: describeStaff,
    facilityId: (_, data) => data?.facilityId || data?.establishmentID || "",
    ownerVisible: true,
  },
  driver_warnings: {
    targetType: "warning",
    describe: describeWarning,
    facilityId: () => "",
    ownerVisible: false,
  },
  driver_reports: {
    targetType: "driver_report",
    describe: describeReport("driver"),
    facilityId: (_, data) => data?.establishmentId || "",
    // The owner filed it, so they may see what became of it.
    ownerVisible: true,
  },
  facility_reports: {
    targetType: "facility_report",
    describe: describeReport("facility"),
    facilityId: (_, data) => data?.establishmentId || "",
    // Owners are never told a driver reported them.
    ownerVisible: false,
  },
};

/**
 * Builds the entry for a direct write to [collection]/[docId], or null when
 * there is nothing to log. Pure apart from the lookups in [lookup].
 */
async function entryForWrite(collection, docId, before, after, actorId, lookup) {
  const watched = WATCHED[collection];
  if (!watched) return null;
  const changes = fieldChanges(before, after);
  const described = watched.describe(before, after, changes);
  if (!described) return null;
  const data = after || before;
  const establishmentId = watched.facilityId(docId, data);
  const facility = await lookup.facility(establishmentId, data);
  const actor = await lookup.actor(actorId);
  return {
    ...described,
    ...actor,
    targetType: watched.targetType,
    targetId: docId,
    establishmentId,
    establishmentName: facility.establishmentName,
    ownerId: watched.ownerVisible ? facility.ownerId || data?.ownerId || "" : "",
    changes,
  };
}

/** Trigger handler for a watched collection's writes. */
async function onWatchedWrite(collection, event) {
  const actorId = actorFromEvent(event);
  if (actorId === null) return; // the server's own write
  const db = getFirestore();
  const entry = await entryForWrite(
    collection,
    event.params.docId,
    event.data?.before?.data(),
    event.data?.after?.data(),
    actorId,
    {
      actor: (uid) => resolveActor(db, uid),
      facility: (id, data) => facilityInfo(db, id, data),
    },
  );
  if (entry) await record(db, entry);
}

/**
 * Wraps a callable [handler] so that, once it succeeds, an entry built by
 * [describe](request, result) is logged for the caller. [describe] may
 * return null to log nothing. It must never copy secrets from [result]
 * (e.g. a reset password) into the entry.
 */
function audited(handler, describe) {
  return async (request) => {
    const result = await handler(request);
    try {
      const db = getFirestore();
      const entry = await describe(request, result, db);
      if (entry) {
        const actor = await resolveActor(db, request.auth?.uid || "");
        let facility = { ownerId: "", establishmentName: "" };
        if (entry.establishmentId) facility = await facilityInfo(db, entry.establishmentId);
        await record(db, {
          ...actor,
          establishmentName: facility.establishmentName,
          ...entry,
          ownerId: entry.ownerId ?? facility.ownerId,
        });
      }
    } catch (error) {
      logger.error("Could not log an audited call", error);
    }
    return result;
  };
}

/** Entry details for a refund decision, from the refund record itself. */
async function refundEntry(db, ticketId, action, summary, details) {
  const refund = (await db.collection("refunds").doc(ticketId).get()).data() || {};
  const amount = Number(refund.amountCentavos || 0);
  return {
    action,
    summary: `${summary}${refund.vehiclePlate ? ` for ${refund.vehiclePlate}` : ""}` +
      (amount > 0 ? ` (PHP ${(amount / 100).toFixed(2)})` : ""),
    targetType: "refund",
    targetId: ticketId,
    establishmentId: refund.establishmentId || "",
    ownerId: refund.ownerId || "",
    details,
  };
}

module.exports = {
  COLLECTION,
  WATCHED,
  summarizeValue,
  fieldChanges,
  actorFromEvent,
  describeFacilityDetails,
  describeEstablishment,
  describeStaff,
  describeWarning,
  describeReport,
  entryForWrite,
  onWatchedWrite,
  audited,
  refundEntry,
  record,
  resolveActor,
};
