# Supervisor role: implementation plan

**Status:** planned, not built. Written November 23, 2026 for a later implementation session.
**Goal:** an on-site supervisor gets their own login to run the facility day to day, instead of borrowing the
owner account. The owner keeps pricing, legal documents, earnings, refunds and hiring. Every supervisor action is
logged under the supervisor's own name.

Keep these rules unchanged:
- **One facility per owner account.** A supervisor belongs to exactly one facility, like gate staff.
- **The security rules enforce the split, not just the screens.** Hiding a button is not enough. A modified app
  must still be refused.
- **PayMongo stays in test mode** (capstone). Don't add anything that needs a live merchant account.

---

## 1. What the supervisor may and may not do

### Supervisor keeps (operations)

| Feature | Owner screen today | Notes |
|---|---|---|
| Facility home: vehicles inside, live overtime, admin notices (read only) | Facility Details | Notices are read only; fixing them stays with the owner |
| Gate Activity: list, search, trace a scan | Activity | |
| Change an exit's overtime status | Activity › scan details | Audit-logged with the supervisor's name |
| Report a driver; resolve (report or dismiss) staff flags | Activity, Facility home | `driver_reports.reporterId` becomes the supervisor |
| Driver Reports card (their own facility's reports) | Activity | |
| Cash handovers: **Mark received** | Staff | `cash_handovers.receivedBy` becomes the supervisor |
| Duty log: who is on duty; **End shift** for a forgotten shift | Staff | `staff_shifts.endedBy` becomes the supervisor |
| Reset a staff member's password | Staff › details | Only staff, never another supervisor or the owner |
| Driver Ratings card | Facility home | |
| Export gate activity (CSV) | Activity | The CSV holds scans and gate cash only, no sales totals |
| Own Profile: change password, Terms and Privacy, Download My Data for their own account | Profile | |

### Owner only (taken away from the supervisor)

| Feature | Why |
|---|---|
| Rates, packages, grace period | Prices are the owner's business decision |
| Slots, vehicle types, operating hours, policies, photos, name, address, map pin | They change what drivers are sold and what the listing promises |
| Business documents, permit expiry, register or resubmit the facility | The owner is the legally responsible party |
| Request a facility review; respond to an admin notice | Only the owner answers for the facility |
| **Reports:** gross sales, payout, commission, transactions, sales report PDF/Excel | Earnings are private to the owner |
| Refunds list, disputing a refund charge, refund balance | They come out of the owner's money |
| Add, edit or deactivate staff accounts | Hiring and firing |
| Add, edit, deactivate supervisors, or reset their passwords | Same reason |
| Change History (audit log) | The owner uses it to check everyone, the supervisor included |
| Delete Account and Download My Data **for the owner account** | They act on the owner's personal account |

Judgment calls (keep as decided unless the user says otherwise):
- **Overtime status:** the supervisor keeps it, because every change is audit-logged. The stricter alternative is
  owner-only, with the supervisor flagging it instead.
- **Gate cash:** the supervisor sees the cash staff collected (overtime and walk-in fees) so they can receive it,
  but never gross sales, payout or commission.

---

## 2. Data model

Reuse `staff_accounts` with a new role value, rather than a new collection. Supervisors are created, deactivated
and signed in exactly like staff (username sign-in, owner-created, owner-reset password), and `isStaffOf()`
already ties a staff record to one facility.

`staff_accounts/{uid}`: add

| Field | Type | Values | Notes |
|---|---|---|---|
| `role` | String | `staff` (default) or `supervisor` | Existing records without it are staff. Only the owner sets it, and only on create; it can't change afterward (make a new account instead) |

`users/{uid}.role` for a supervisor: `supervisor`. Extend `selfAssignableRole()` so that `supervisor` is allowed
only when `staff_accounts/{uid}.role == 'supervisor'`, just as `staff` is today.

No other collection needs new fields. `receivedBy`, `endedBy`, `reporterId`, `handledBy` and the audit log's
`actorId`, `actorName` and `actorRole` already record who acted. They will simply hold the supervisor's uid and
name.

---

## 3. Security rules (`smart_park/firestore.rules`)

Add helpers next to `isOwnerOf()` and `isStaffOf()`:

```
function isSupervisorOf(establishmentId) {
  return isStaffOf(establishmentId) &&
    get(staffPath(uid())).data.get('role', 'staff') == 'supervisor';
}
// Operations the owner or the facility's supervisor may do.
function canOperate(establishmentId) {
  return isOwnerOf(establishmentId) || isSupervisorOf(establishmentId);
}
```

Then go through every `isOwnerOf(` (21 uses today) and decide which ones become `canOperate(`:

| Collection / rule | Change |
|---|---|
| `activity_logs` read; overtime status update | `canOperate` |
| `staff_incidents` read and update (report or dismiss) | `canOperate` |
| `driver_reports` create (owner's own facility ticket) and read | `canOperate`, `reporterId == uid()` |
| `cash_handovers` read and create (`cashHandoverCreateOk`, `receivedBy == uid()`) | `canOperate` |
| `staff_shifts` read; owner "end a forgotten shift" update | `canOperate` (keep `endedBy == uid()`) |
| `transactions` read for the facility (gate and activity need it) | `canOperate` |
| `facility_ratings` list for the facility | `canOperate` |
| `establishment_occupancy` read | already readable; no change |
| `establishments`, `establishment_details` (rates, slots, hours, policies, status, review request) **writes** | stay `isOwnerOf` |
| `establishment_private` (business documents) read and write | stay `isOwnerOf` |
| `payments`, `payment_splits`, `refunds`, `owner_refund_balances` read | stay `isOwnerOf` |
| `audit_logs` read (`ownerId == uid()`) | no change; the owner only |
| `staff_accounts` create, update, delete | stay owner only; also require `request.resource.data.role in ['staff','supervisor']` on create and `unchanged('role')` on update |
| `staff_accounts` read | add: a supervisor may read the staff records of their own facility (needed for the duty log, cash handovers and password resets) |

Check `isStaffOf()` users still work: a supervisor *is* a staff record, so anything gate staff can already do
(scan, walk-ins) a supervisor can also do. That's intended: a supervisor can cover the gate.

Storage rules (`storage.rules`): the business documents and photos paths stay owner-only. No change needed
unless a path uses a staff check.

---

## 4. Cloud Functions (`smart_park/functions`)

| Function | Change |
|---|---|
| `resetStaffPassword` | Allow a supervisor of the same facility to reset **staff** passwords only (target `role != 'supervisor'`). The owner can reset both |
| `setStaffSignInState` | No change (triggered on staff record changes; supervisors are staff records) |
| `getPaymentHealth`, `exportMyData` | `exportMyData` for a supervisor exports only their own records, like staff |
| `src/audit.js` | `resolveActor` should label `actorRole` as `supervisor`. Check that supervisor writes to watched collections (`staff_accounts` isn't writable by them; `driver_reports` and similar) get logged with the supervisor as the actor and keep `ownerId` set, so the owner sees them in Change History |
| `src/alerts.js` | Staff flags currently notify the owner. Also notify the facility's supervisors (their push tokens), since they handle flags |
| `createParkingPass`, `startGatePayment`, `checkGatePayment` and the other gate functions | They check "staff of this facility". A supervisor passes, since it's a staff record. Confirm with a test |

---

## 5. App (`smart_park/lib`)

- **Routing (`screens/auth/role_based_home_page.dart`):** when the signed-in user's staff record has
  `role == 'supervisor'`, open a new **SupervisorHomePage** instead of the staff home.
- **SupervisorHomePage:** reuse the owner's widgets for the allowed features, with the owner-only actions removed.
  Suggested tabs: **Facility** (home without edit buttons, Driver Ratings, notices read only), **Staff** (cash
  handovers, duty log, staff list with Reset password only), **Activity** (gate activity, driver reports, export),
  **Scanner** (reuse the staff scanner, so a supervisor can cover the gate), **Profile**.
  Don't show Reports, Refunds, Change History, rates or facility editing at all.
- **Owner › Staff › Add staff member:** add a role choice, **Gate staff** or **Supervisor**. The supervisor's
  details screen shows Deactivate and Reset password, owner only.
- **Owner Change History:** filter or label entries by actor role so the owner can see what supervisors changed.
- **Terms (`content/terms_content.dart`):** supervisors accept the gate staff terms, plus one paragraph on handling
  cash handovers and incident reports. Bump the terms version so existing users accept again.

---

## 6. Tests to add

- **Rules tests (`functions/rules-test/firestore.test.js`):**
  - A supervisor can read activity logs, mark cash received, end a shift, and report a driver for their facility.
  - A supervisor **cannot**:
    - write rates, slots, hours or policies;
    - read `payment_splits` or `payments`;
    - read refunds or `audit_logs`;
    - read or write `establishment_private`;
    - create, edit or deactivate staff;
    - change their own `role`.
  - A supervisor of facility A can't read facility B's data.
  - A staff member can't do supervisor-only actions (mark cash received, end someone else's shift).
- **Functions tests:**
  - `resetStaffPassword`: a supervisor can reset staff but not another supervisor or the owner.
  - Audit entries made by a supervisor carry `actorRole: supervisor` and the owner's `ownerId`.
- **Flutter tests:**
  - Routing to SupervisorHomePage.
  - Owner-only actions aren't shown.
  - The add-staff form offers the role.

Run rules tests on port 8081 (port 8080 is taken on this PC), then restore `firebase.json`.

---

## 7. Paper updates once it's built (Chapters 1-5 only)

- **Scope:** add a supervisor role. **Limitations:** remove "supervisors use the owner account".
- **Requirements documentation:** a short Supervisor subsection with screenshots, and a new **Supervisor module
  use case diagram** in `paper-revision/scripts/diagrams/usecases.py`.
- **Data dictionary:** the `role` field on Staff Accounts (`staff` or `supervisor`) and its allowed values.
- **Development:** a new cycle. **Testing:** new rules and functions test rows, and the updated test totals.
- **Recommendations:** remove the supervisor role from future work if it was listed.
- **User's Guide:** an F.x Supervisors section.
- The UAT section stays as it is: the evaluation was done before this role existed.
