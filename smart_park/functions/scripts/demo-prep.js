// Final-defense showcase data for the test facility and test driver.
//
//   cd functions && node scripts/demo-prep.js            # full cleanup + setup
//   cd functions && node scripts/demo-prep.js overtime   # only refresh the overtime ticket
//   cd functions && node scripts/demo-prep.js policies   # only rewrite the posted policies
//   cd functions && node scripts/demo-prep.js logs       # close gate entries left open by tickets that left
//
// Uses the Firebase CLI login (firebase login), through the Firestore REST
// API, since this PC has no gcloud Application Default Credentials.
// Safe to run again.

const path = require("path");
const { execSync } = require("child_process");

const PROJECT = "smartpark-87e3d";
const FACILITY = "T5Zp8aIeuA1Hc8itSu7M";
const DRIVER = "ic9RV61N66YSAwc0j3MxX8gjDrH3";
const OVERTIME_TICKET = "9xxcMbvEDNHsx59MjQeN"; // base stay, motorcycle ABC 1234
const OVERTIME_MINUTES = 75; // how far past the paid time it is when run

const NAME = "Juliville Parking";
const POLICIES = [
  "1. Present your SmartPark QR or ticket to the gate staff on entry and exit.",
  "2. The base stay covers the first 2 hours. Overtime is charged per hour at the posted rate and paid in cash at the exit gate.",
  "3. A ticket pays for parking time; it does not reserve a slot. Parking is first come, first served.",
  "4. Park only within marked slots. Motorcycles use the motorcycle area.",
  "5. Lock your vehicle and do not leave valuables inside. The management is not liable for loss or damage.",
  "6. Follow the staff's directions and the 10 km/h speed limit inside the lot.",
  "7. Vehicles left past 30 days without a valid ticket may be reported to the barangay.",
].join("\n");

const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
let H;

async function token() {
  const root = execSync("npm root -g").toString().trim();
  const auth = require(path.join(root, "firebase-tools/lib/auth"));
  const { configstore } = require(path.join(root, "firebase-tools/lib/configstore"));
  const r = await auth.getAccessToken(configstore.get("tokens").refresh_token, []);
  return r.access_token;
}

function dec(v) {
  const k = Object.keys(v)[0];
  const x = v[k];
  if (k === "integerValue") return Number(x);
  if (k === "mapValue") return decF(x.fields || {});
  if (k === "arrayValue") return (x.values || []).map(dec);
  return x;
}
function decF(f) {
  const o = {};
  for (const k in f) o[k] = dec(f[k]);
  return o;
}
function enc(v) {
  if (v === null) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "boolean") return { booleanValue: v };
  if (Number.isInteger(v)) return { integerValue: String(v) };
  if (typeof v === "number") return { doubleValue: v };
  if (typeof v === "string") return { stringValue: v };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, enc(x)])) } };
}
async function call(url, opts = {}) {
  const r = await fetch(url, { headers: H, ...opts });
  const t = await r.text();
  if (!r.ok) throw new Error(`${r.status} ${t}`);
  return t ? JSON.parse(t) : {};
}
async function query(col, field, value) {
  const body = {
    structuredQuery: {
      from: [{ collectionId: col }],
      where: { fieldFilter: { field: { fieldPath: field }, op: "EQUAL", value: enc(value) } },
    },
  };
  const rows = await call(`${BASE}:runQuery`, { method: "POST", body: JSON.stringify(body) });
  return rows
    .filter((x) => x.document)
    .map((x) => ({ id: x.document.name.split("/").pop(), ...decF(x.document.fields || {}) }));
}
async function queryWhere(col, equals) {
  const filters = Object.entries(equals).map(([field, value]) => ({
    fieldFilter: { field: { fieldPath: field }, op: "EQUAL", value: enc(value) },
  }));
  const body = {
    structuredQuery: {
      from: [{ collectionId: col }],
      where: filters.length === 1 ? filters[0] : { compositeFilter: { op: "AND", filters } },
    },
  };
  const rows = await call(`${BASE}:runQuery`, { method: "POST", body: JSON.stringify(body) });
  return rows
    .filter((x) => x.document)
    .map((x) => ({ id: x.document.name.split("/").pop(), ...decF(x.document.fields || {}) }));
}

// The app shows a facility's posted policies from establishment_details
// (laid over establishments), so both must be written.
async function writePolicies() {
  await patch(`establishments/${FACILITY}`, { policies: POLICIES });
  await patch(`establishment_details/${FACILITY}`, { policies: POLICIES, updatedAt: new Date() });
}

// Gate entry logs still marked inside although their ticket has left count
// toward "Inside Now". Close them, as an exit scan would.
async function closeStaleEntryLogs() {
  const open = await queryWhere("activity_logs", { establishmentID: FACILITY, isActive: true });
  let closed = 0;
  for (const log of open) {
    if (log.scanType !== "entry" || !log.transactionId) continue;
    const ticket = await call(`${BASE}/transactions/${log.transactionId}`).catch(() => null);
    const entry = String(decF(ticket?.fields || {}).entryStatus || "").toLowerCase();
    if (entry === "checked_in" || entry === "inside") continue;
    await patch(`activity_logs/${log.id}`, { isActive: false, exitAt: new Date(), updatedAt: new Date() });
    closed++;
  }
  console.log(`Closed ${closed} gate entries left open.`);
}

async function patch(docPath, fields) {
  const mask = Object.keys(fields).map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join("&");
  const body = { fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, enc(v)])) };
  return call(`${BASE}/${docPath}?${mask}`, { method: "PATCH", body: JSON.stringify(body) });
}
const del = (docPath) => call(`${BASE}/${docPath}`, { method: "DELETE" });

async function refreshOvertime() {
  // remainingHours 2 + 75 minutes over: checked in 3h15m ago.
  const remaining = 2;
  const entryAt = new Date(Date.now() - (remaining * 60 + OVERTIME_MINUTES) * 60 * 1000);
  await patch(`transactions/${OVERTIME_TICKET}`, {
    entryStatus: "checked_in",
    entryAt,
    remainingHours: remaining,
    overtimeStatus: "none",
    overtimeHours: 0,
    overtimeAmount: 0,
    overtimeSentFor: null,
    reminderSentFor: null,
    exitAt: null,
    updatedAt: new Date(),
  });
  // Its latest entry log shows it as inside again (Inside Now, Activity).
  const entries = (await queryWhere("activity_logs", { transactionId: OVERTIME_TICKET, scanType: "entry" }))
    .filter((l) => l.establishmentID === FACILITY)
    .sort((a, b) => String(b.timestamp || "").localeCompare(String(a.timestamp || "")));
  if (entries.length > 0) {
    await patch(`activity_logs/${entries[0].id}`, {
      isActive: true,
      timestamp: entryAt,
      exitAt: null,
      exitLogId: null,
      updatedAt: new Date(),
    });
  }
  console.log(`Overtime ticket ${OVERTIME_TICKET}: entered ${entryAt.toLocaleString()}, ${OVERTIME_MINUTES} min over.`);
}

async function main() {
  H = { Authorization: `Bearer ${await token()}`, "Content-Type": "application/json" };
  if (process.argv[2] === "overtime") return refreshOvertime();
  // Only rewrite the facility's posted policies.
  if (process.argv[2] === "policies") {
    await writePolicies();
    console.log("Policies updated.");
    return;
  }
  if (process.argv[2] === "logs") return closeStaleEntryLogs();

  // 1. Facility name and policy.
  await patch(`establishments/${FACILITY}`, {
    name: NAME,
    contactNumber: "0912 345 6789",
  });
  await writePolicies();
  let renamed = 0;
  for (const col of ["transactions", "parking_checkouts", "staff_accounts"]) {
    for (const d of await query(col, "establishmentId", FACILITY)) {
      if (d.establishmentName && d.establishmentName !== NAME) {
        await patch(`${col}/${d.id}`, { establishmentName: NAME });
        renamed++;
      }
    }
  }
  console.log(`Facility renamed to "${NAME}" with policies; ${renamed} records updated.`);

  // 2. The test driver's unused or expired temporary QRs: delete.
  const checkouts = await query("parking_checkouts", "driverId", DRIVER);
  let deleted = 0;
  for (const c of checkouts) {
    if (["awaiting_gate", "pending", "expired", "cancelled", "failed"].includes(c.status)) {
      await del(`parking_checkouts/${c.id}`);
      deleted++;
    }
  }
  console.log(`Deleted ${deleted} unused/expired temporary QRs.`);

  // 3. Leftover open tickets (paid but never used, or still parked from
  // testing): close them so they are history, keeping the sales records.
  const tickets = await query("transactions", "driverId", DRIVER);
  let closed = 0;
  for (const t of tickets) {
    if (t.id === OVERTIME_TICKET) continue;
    const entry = String(t.entryStatus || "").toLowerCase();
    const open = entry === "checked_in" || entry === "inside" || (t.remainingHours ?? 1) > 0;
    if (t.status === "paid" && open) {
      await patch(`transactions/${t.id}`, {
        entryStatus: "checked_out",
        remainingHours: 0,
        exitAt: t.exitAt || new Date(),
        updatedAt: new Date(),
      });
      closed++;
    }
  }
  console.log(`Closed ${closed} leftover open tickets.`);
  await closeStaleEntryLogs();

  // 4. One parked ticket that is in overtime.
  await refreshOvertime();
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
