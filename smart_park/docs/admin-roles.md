# Admin roles: super admin and admin, managed in the app

**Status:** built 2026-11-23. Still to do: add `adminLevel: "super"` to the first super admin in the console (README > Operations); paper updates (section 7).
**Goal:** stop editing the database by hand to add administrators. The **super admin** promotes regular users to
admin (or super admin) in the app and can remove admin access. A normal **admin** sees who is an admin but can't
change anyone's access. Everything is checked on the server and recorded in the audit log.

> **Action required first:** the account `GWBK5QsdMNMHdPDjiPgrd7g3u3C2` currently has **normal admin access only**
> (`role: 'admin'`, no `adminLevel`). As part of this implementation, **make this user the super admin** by setting
> `adminLevel: "super"` on `users/GWBK5QsdMNMHdPDjiPgrd7g3u3C2` (section 0). Without it, nobody can promote anyone,
> because every promote and demote action needs a super admin. Do this right after deploying the rules change in
> section 3, and confirm it by signing in as this user and seeing "Super admin" in Settings › Admin Account.

## 0. The first super admin (bootstrap, done once)

| | |
|---|---|
| Firebase Auth UID | `GWBK5QsdMNMHdPDjiPgrd7g3u3C2` |
| Firestore profile | `users/GWBK5QsdMNMHdPDjiPgrd7g3u3C2` |
| Current `role` | `admin` (set by hand in the console; registered first as a Driver) |
| Add | `adminLevel: "super"` |

Ways to add the field. Use one, once, after the rules change in section 3 is deployed (that change stops users
setting `adminLevel` themselves):
- **Firebase console:** Firestore › `users` › `GWBK5QsdMNMHdPDjiPgrd7g3u3C2` › Add field `adminLevel` (string) =
  `super`.
- **Or a one-time script,** `functions/scripts/set-super-admin.js` (Admin SDK, run once with the project's
  credentials, then keep it for reference):
  ```js
  // node functions/scripts/set-super-admin.js
  const { initializeApp } = require("firebase-admin/app");
  const { getFirestore, FieldValue } = require("firebase-admin/firestore");
  initializeApp({ projectId: "smartpark-87e3d" });
  const UID = "GWBK5QsdMNMHdPDjiPgrd7g3u3C2";
  getFirestore().doc(`users/${UID}`)
    .set({ role: "admin", adminLevel: "super", adminSince: FieldValue.serverTimestamp() }, { merge: true })
    .then(() => console.log("super admin set for", UID));
  ```
- Also, in the migration below, give every **existing** admin without `adminLevel` the value `admin`, so
  `GWBK5QsdMNMHdPDjiPgrd7g3u3C2` is the only super admin at the start.

Admin role values used today: `users/{uid}.role == 'admin'` (rules `isAdmin()`, `functions/index.js`,
`src/refunds.js`, `src/payment_health.js`, `lib/screens/auth/role_based_home_page.dart`). Other roles are
`Driver`, `Parking Owner` and `staff`. Keep all of these as they are.

---

## 1. Permissions

| | Super admin | Admin |
|---|---|---|
| Everything admins do today: facility review, suspend and deactivate, notices, driver and facility reports, warnings, refunds and disputes, users directory, reports, Payment Health, Audit Log, Rebuild statistics, Compress photos | ✓ | ✓ |
| See each user's access level (Super admin / Admin / Driver / Owner) and an **Admins** filter in Users | ✓ | ✓ |
| **Promote** a driver to admin | ✓ | ✗ |
| **Make an admin a super admin**, or turn a super admin back into an admin | ✓ | ✗ |
| **Remove admin access** (demote) | ✓ | ✗ |
| Change the commission rate (`docs/quick-fixes.md`, item 4), once that's built | ✓ | ✗ |

### Safety rules (enforced on the server)

1. **Only drivers can be promoted.**
   - **Parking owners can't be promoted.** An owner who is also an admin could approve their own facility or hide
     their own ratings, which is a conflict of interest.
   - **Gate staff accounts can't be promoted** either.
   - The account must have a verified email.
2. **A promoted account is admin-only.** `role` becomes `admin`, and the old role is kept in `formerRole: 'Driver'`
   so a demotion can restore it. Before promoting, the super admin is shown whether the driver has paid tickets with
   hours left or unused temporary QRs. Those stay valid and come back on demotion, but the account can't use them
   while it's an admin.
3. **At least one super admin always remains.** The last super admin can't be demoted, can't demote themselves, and
   can't turn themselves into a normal admin.
4. **A super admin can't demote another super admin directly.** They first make them a normal admin, then remove
   access. These are two deliberate steps, both logged.
5. **Promoting or demoting asks for the super admin's password again,** using the same re-authentication as Delete
   Account.
6. **Demotion takes effect at once.** The rules and functions read the role from `users/{uid}` on every request, so a
   demoted admin is refused on their next action. The app also listens to the profile and returns a demoted admin to
   their former home.
7. **No admin acts on a case about themselves.** For example, they can't decide a driver report, warning, facility
   report or refund request whose driver or owner is their own uid (or their `formerRole` account, which is the same
   uid). Add this check to the existing admin-only functions and to the rules for review decisions.
8. **Every change is audit-logged** and the affected user gets a push notification and an in-app notice.

---

## 2. Data model

`users/{uid}`: new fields

| Field | Type | Notes |
|---|---|---|
| `adminLevel` | String | `super` or `admin`; only when `role == 'admin'` |
| `formerRole` | String | The role before promotion (`Driver`), restored on demotion |
| `adminSince` | Timestamp | When the account became an admin |
| `promotedBy` | String (uid) | Who promoted it |

All four are **server-written only**.

---

## 3. Security rules (`smart_park/firestore.rules`)

- **Important, do this first:** `roleFieldsUnchanged()` currently protects only `role`, `Role` and `userRole`, so a
  user could write `adminLevel` to their own profile. Extend it:
  ```
  function roleFieldsUnchanged() {
    return unchanged('role') && unchanged('Role') && unchanged('userRole') &&
      unchanged('adminLevel') && unchanged('formerRole') && unchanged('adminSince') &&
      unchanged('promotedBy');
  }
  ```
  and make `validNewRole()` refuse any of these four keys on create.
- **New helper:**
  ```
  function isSuperAdmin() {
    return isAdmin() && get(userPath(uid())).data.get('adminLevel', 'admin') == 'super';
  }
  ```
  Promotion and demotion go through Cloud Functions, not client writes, so the rules only need to keep these fields
  read-only for everyone. Use `isSuperAdmin()` for any future super-only document, such as `settings/platform` from
  quick fix 4.
- **Existing `isAdmin()` stays as it is,** so every current admin screen keeps working for both levels.

---

## 4. Cloud Functions (`smart_park/functions`)

New callables in `src/admin_roles.js`, exported from `index.js`:

| Callable | Who | Does |
|---|---|---|
| `promoteToAdmin({ uid, level })` | super admin | Checks the target is a verified **Driver** and not the caller. Sets `role: 'admin'`, `adminLevel` (`admin` or `super`), `formerRole: 'Driver'`, `adminSince`, `promotedBy`. Writes an audit entry and notifies the user |
| `setAdminLevel({ uid, level })` | super admin | Switches an admin between `admin` and `super`. Refuses if it would leave no super admin, or if the target is the caller |
| `removeAdminAccess({ uid })` | super admin | Target must be a normal `admin` (not super) and not the caller. Restores `role` from `formerRole`, deletes `adminLevel`, `adminSince` and `promotedBy`. Writes an audit entry and notifies the user |
| `getAdminCandidates({ uid })` | super admin | Before promoting: the user's role, email verification, and counts of active tickets and unused temporary QRs, for the confirmation dialog |

Shared helpers:
- `requireSuperAdmin(request)`, next to the existing admin checks.
- **Re-authentication:** the app re-authenticates with the password first, then calls the function. The function
  checks `request.auth.token.auth_time` is within the last 5 minutes and refuses otherwise.
- **Count super admins in a transaction,** so two demotions at once can't leave zero.

Changes to existing code:
- `src/audit.js`: actions `admin.promoted`, `admin.level_changed`, `admin.removed`, with before and after values
  (`role`, `adminLevel`). Admin-only entries keep `ownerId: ''`.
- **Self-case checks:** the functions that decide reports, warnings, refunds and disputes (`decideRefund`,
  `resolveRefundDispute`, `recordOwnerRepayment`, and report and warning decisions) refuse when the subject is the
  caller.
- `exportMyData`: include `adminLevel` and `formerRole` in the caller's own profile export.
- **Migration** (one-time, in the same script as section 0): every user with `role == 'admin'` and no `adminLevel`
  gets `adminLevel: 'admin'`, except `GWBK5QsdMNMHdPDjiPgrd7g3u3C2`, which gets `super`.

---

## 5. App (`smart_park/lib`)

- **Users (`screens/admin/admin_user_directory.dart`):**
  - Filters: All / Drivers / Owners / **Admins**, with counts.
  - Each row has a role chip: **Super admin**, **Admin**, **Driver** or **Owner**.
- **User details (both admin levels):** access level, "Admin since [date] · promoted by [name]", and the former
  role.
- **Super admin only, on the same details screen:**
  - A driver gets **Make admin**. A dialog shows the candidate check (verified email, active tickets and unused
    temporary QRs), a choice of Admin or Super admin, and password re-entry.
  - An admin gets **Make super admin** and **Remove admin access**.
  - A super admin gets **Make normal admin**. It's hidden for the caller's own account and for the last super admin.
- **Normal admins** see the same chips and details with no buttons, plus a line: "Only a super admin can change
  admin access."
- **Settings › Admin Account:** shows "Super admin" or "Admin" under the account name.
- **Routing (`screens/auth/role_based_home_page.dart`):** listen to the profile; if `role` stops being `admin`,
  route to the restored role's home.
- **Notices to the affected user:** "You now have admin access", "Your admin access was changed to …", "Your
  admin access was removed". Reuse the push and in-app notice paths. If `docs/quick-fixes.md` item 4 is built
  first, use its `announcements` pop-up.

---

## 6. Tests

- **Rules:**
  - A user can't set `adminLevel`, `formerRole`, `adminSince` or `promotedBy` on their own profile, on create or on
    update.
  - A normal admin can read users' access levels.
  - Nobody writes them from the app.
- **Functions:**
  - Only a super admin can promote, change a level, or remove access.
  - Owners and staff can't be promoted.
  - The caller can't change their own access.
  - The last super admin can't be demoted, including two demotions at the same time.
  - Stale sign-in (old `auth_time`) is refused.
  - Demotion restores `formerRole`.
  - Audit entries are written.
  - An admin can't decide a report, warning or refund about themselves.
- **Flutter:**
  - The chips and the Admins filter appear.
  - Normal admins see no promote or demote buttons.
  - The super admin sees them, except on their own account.
  - Routing after demotion.

Run rules tests on **port 8081** (8080 is taken on this PC), then restore `firebase.json`.

---

## 7. Paper updates once it's built (Chapters 1-5 only)

- **Limitations:** replace "Administrator accounts cannot be registered through the application and are assigned
  directly in the Firebase console" with "Only the first super administrator is set up in the Firebase console;
  super administrators promote other administrators in the application."
- **Scope:** a bullet for super admin and admin access levels.
- **Data dictionary:**
  - Users: `adminLevel`, `formerRole`, `adminSince`, `promotedBy`.
  - User Roles allowed values: a note on the access levels.
- **Admin screens description, Platform Administrator use case** (`paper-revision/scripts/diagrams/usecases.py`):
  "Manage Admin Access" (super admin), and "View Admin List".
- **Cloud Functions table:** the four new callables. **Development:** a new cycle. **Testing:** new rows and
  totals.
- **User's Guide F.5:** how a super admin promotes or removes an admin.
