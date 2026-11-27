// Push alerts for admins and owners, so time-sensitive work doesn't wait
// for someone to happen to open the app:
//   - admins: new and resubmitted facility applications, review requests,
//     driver refund requests (approved by themselves after 3 days),
//     driver reports and facility reports
//   - owners: their facility approved, rejected, suspended, deactivated or
//     reinstated, and drivers flagged by their staff
// Each alert's data carries a `kind` the app uses to open the right tab.
// Alerts are best effort (see notify.js): one that can't be sent never
// fails the work it is about.

const { getFirestore } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions");

const { notifyUser } = require("./notify");

const KINDS = {
  facilityReview: "admin_facility_review",
  refundRequest: "admin_refund_request",
  report: "admin_report",
  facilityStatus: "owner_facility_status",
  staffFlag: "owner_staff_flag",
};

function status(details) {
  return String(details?.status || "").trim().toLowerCase();
}

function millis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return typeof value === "number" ? value : null;
}

function reasonText(data) {
  if (Array.isArray(data?.reasons) && data.reasons.length) return data.reasons.join(", ");
  return String(data?.reason || "").trim();
}

/**
 * The admins' alert for a change to establishment_details, or null:
 * a new application, a resubmission, new documents on a reviewed facility,
 * or an owner asking for review.
 */
function facilityReviewAlert(before, after, name) {
  if (!after) return null;
  const facility = name || "A facility";
  const data = { kind: KINDS.facilityReview };
  if (status(after) === "pending") {
    if (!before) {
      return { title: "New facility to review", body: `${facility} applied to join SmartPark.`, data };
    }
    const resubmitted = millis(after.resubmittedAt);
    if (status(before) !== "pending" || (resubmitted && resubmitted !== millis(before.resubmittedAt))) {
      return { title: "Facility resubmitted", body: `${facility} sent its application again for review.`, data };
    }
  }
  // New documents on a reviewed facility: it stays as it is (an approved
  // one stays open) until an admin checks them.
  const docs = millis(after.documentsUpdatedAt);
  if (docs && status(after) !== "pending" && docs !== millis(before?.documentsUpdatedAt)) {
    return {
      title: "New documents to check",
      body: `${facility} uploaded new business documents. Check them, or suspend it if they are invalid.`,
      data,
    };
  }
  if (after.appealedAt && !before?.appealedAt) {
    return {
      title: "Review requested",
      body: `${facility} asked SmartPark to review its ${status(after) || "status"}.`,
      data,
    };
  }
  return null;
}

/** The owner's alert when an admin decides on their facility, or null. */
function facilityStatusAlert(before, after, name) {
  const was = status(before);
  const now = status(after);
  if (!after || !before || was === now) return null;
  const facility = name || "Your facility";
  const data = { kind: KINDS.facilityStatus };
  const reason = String(after.rejectionReason || after.restrictionReason || "").trim();
  const why = reason ? ` Reason: ${reason}.` : "";
  if (now === "approved") {
    return was === "suspended" || was === "deactivated"
      ? { title: "Facility reinstated", body: `${facility} is open to drivers again.`, data }
      : { title: "Facility approved", body: `${facility} is now listed on SmartPark. Drivers can find and pay for it.`, data };
  }
  if (now === "rejected") {
    return { title: "Application not approved", body: `${facility} was not approved.${why} Fix it and resubmit from the app.`, data };
  }
  if (now === "suspended") {
    return { title: "Facility suspended", body: `${facility} is hidden from drivers for now.${why} Open the app for details.`, data };
  }
  if (now === "deactivated") {
    return { title: "Facility deactivated", body: `${facility} was deactivated.${why} Open the app for details.`, data };
  }
  return null;
}

/** Admins' alert for a new report: by an owner on a driver, or the reverse. */
function reportAlert(collection, report) {
  const reasons = reasonText(report);
  const data = { kind: KINDS.report };
  if (collection === "driver_reports") {
    return {
      title: "Driver reported",
      body: `${report.establishmentName || "A facility"} reported ${report.driverName || "a driver"}${reasons ? `: ${reasons}` : ""}.`,
      data,
    };
  }
  return {
    title: "Facility reported",
    body: `A driver reported ${report.establishmentName || "a facility"}${reasons ? `: ${reasons}` : ""}.`,
    data,
  };
}

/** The owner's alert when one of their staff flags a driver. */
function staffFlagAlert(incident) {
  const reasons = reasonText(incident);
  const plate = String(incident.vehiclePlate || "").trim();
  return {
    title: "Staff flagged a driver",
    body:
      `${incident.staffName || "Your staff"} flagged ${incident.driverName || "a driver"}` +
      `${plate ? ` (${plate})` : ""}${reasons ? `: ${reasons}` : ""}. Review it in the app.`,
    data: { kind: KINDS.staffFlag },
  };
}

/** Admins' alert for a driver's refund request. */
function refundRequestAlert(refund, autoApproveDays) {
  return {
    title: "Refund request to review",
    body:
      `${refund.establishmentName || "A suspended facility"}: a driver asked for a refund. ` +
      `It is approved automatically in ${autoApproveDays} days if nobody decides.`,
    data: { kind: KINDS.refundRequest },
  };
}

/** Sends [message] to every admin. */
async function notifyAdmins(db, message) {
  try {
    const admins = await db.collection("users").where("role", "==", "admin").get();
    let sent = 0;
    for (const doc of admins.docs) sent += await notifyUser(db, doc.id, message);
    return sent;
  } catch (error) {
    logger.warn("Could not notify admins", error);
    return 0;
  }
}

/** The facility's name and owner, from the establishments record. */
async function facilityBase(db, establishmentId, details) {
  try {
    const base = (await db.collection("establishments").doc(establishmentId).get()).data() || {};
    return {
      name: String(base.name || details?.name || "").trim(),
      ownerId: String(base.ownerId || details?.ownerId || "").trim(),
    };
  } catch (error) {
    logger.warn(`Could not load facility ${establishmentId} for an alert`, error);
    return { name: String(details?.name || ""), ownerId: String(details?.ownerId || "") };
  }
}

/** Trigger on establishment_details: alerts admins and the owner. */
async function onFacilityChange(establishmentId, before, after) {
  const forAdmins = facilityReviewAlert(before, after, "");
  const forOwner = facilityStatusAlert(before, after, "");
  if (!forAdmins && !forOwner) return;
  const db = getFirestore();
  const base = await facilityBase(db, establishmentId, after);
  if (forAdmins) await notifyAdmins(db, facilityReviewAlert(before, after, base.name));
  if (forOwner && base.ownerId) {
    await notifyUser(db, base.ownerId, facilityStatusAlert(before, after, base.name));
  }
}

/** Trigger on a new driver_reports or facility_reports document. */
async function onReportCreated(collection, report) {
  if (!report) return;
  await notifyAdmins(getFirestore(), reportAlert(collection, report));
}

/** Trigger on a new staff_incidents document. */
async function onStaffFlagCreated(incident) {
  if (!incident?.ownerId) return;
  const db = getFirestore();
  await notifyUser(db, incident.ownerId, staffFlagAlert(incident));
  // Supervisors handle flags too.
  try {
    const supervisors = await db
      .collection("staff_accounts")
      .where("facilityId", "==", incident.establishmentId || "-")
      .where("role", "==", "supervisor")
      .get();
    for (const doc of supervisors.docs) {
      if (doc.data().active === false) continue;
      await notifyUser(db, doc.id, staffFlagAlert(incident));
    }
  } catch (error) {
    logger.warn("Could not notify supervisors of a staff flag", error);
  }
}

module.exports = {
  KINDS,
  facilityReviewAlert,
  facilityStatusAlert,
  reportAlert,
  staffFlagAlert,
  refundRequestAlert,
  notifyAdmins,
  onFacilityChange,
  onReportCreated,
  onStaffFlagCreated,
};
