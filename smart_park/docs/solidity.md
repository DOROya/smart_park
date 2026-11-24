# Making the backend solid: implementation plan

**Status:** items 1 and 4 started 2026-11-23: payment alerts to admins (4.4) built; backups and console alerts are steps for the user (README > Operations). Items 2, 3, 5 and 6 on hold.
**Project:** Firebase `smartpark-87e3d`, Cloud Functions in `asia-southeast1` (photo compression in `us-east1`).
For Google Cloud console links, always add `?project=smartpark-87e3d`; the user's console otherwise opens an
unrelated "My First Project".

Already in place (don't redo):
- CI (`.github/workflows/ci.yml`) runs `flutter analyze`, `flutter test`, `npm test` and `npm run test:rules` on
  every push.
- Crashlytics is on.
- Rate limits exist on emails (`src/auth_emails.js`), data downloads (`src/data_export.js`) and temporary QRs
  (`src/gate_pass.js`).
- Payments are written in transactions, and the 15-minute reconcile job finishes payments the app missed.
- The Payment Health card shows payment problems to admins.

**Several steps here are console or `gcloud` actions on the live project.** Show the user the exact command or
click path, and let them run it or approve it. Don't run anything that changes the live project without asking.

Suggested order: **1 and 4 first** (small, protect against the worst cases), then 2, 6, 5, 3.

---

## 1. Daily Firestore backups (and a restore drill)

**Gap:** no backups are set up, but the paper's Preventive Maintenance already says "Regular Firestore backups".

**Do (user runs or approves):**
1. Check the database location:
   `gcloud firestore databases describe --database="(default)" --project=smartpark-87e3d`
2. Create a daily backup schedule, kept 7 days:
   `gcloud firestore backups schedules create --database="(default)" --recurrence=daily --retention=7d --project=smartpark-87e3d`
3. **Restore drill, once,** into a separate test database. This never touches `(default)`:
   - `gcloud firestore backups list --project=smartpark-87e3d` (pick the newest backup)
   - `gcloud firestore databases restore --source-backup=<backup name> --destination-database=restore-test --project=smartpark-87e3d`
   - Spot-check a few documents in `restore-test` in the console, then delete `restore-test` so it doesn't cost
     anything.
4. **Cloud Storage** (facility photos, business documents): check that the bucket's **soft delete** is on, with 7
   days or more kept. Google Cloud › Storage › bucket › Protection.

Costs are small at this data size: backup storage is billed per GB.

Write down the date of the restore drill and the backup schedule in `smart_park/README.md` (Operations section).

**Paper:**
- Preventive Maintenance: change to "Daily Firestore backups are kept for 7 days, and a restore was tested on
  [date]."
- Implementation Results: a line if desired.

---

## 2. Server-controlled minimum app version ("Update required")

**Gap:** `lib/services/app_version_guard.dart` compares the installed version only against a build-time
`--dart-define LATEST_DEV_VERSION`. Nothing stops an old APK, installed by hand from Codemagic, from running against
a newer backend and failing in confusing ways. That happened in principle when payment moved to the gate.

### Data

`settings/app` (server or admin written; readable by everyone, including signed-out users):

| Field | Type | Notes |
|---|---|---|
| `minVersion` | String | For example `1.4.0+42`; older apps can't start |
| `latestVersion` | String | Shown as "A newer version is available" (optional, not blocking) |
| `downloadUrl` | String | Where to get the APK, for example the Codemagic artifact or a shared link |
| `message` | String | Optional, one sentence on why to update |

**Rules:** `allow read: if true;` and `allow write: if false;` from the app. Set it in the console. Once
`docs/admin-roles.md` is built, add a super-admin-only **App version** setting that calls a callable instead.

### App

- `AppVersionGuard.check()` reads `settings/app` first, falling back to the dart-define for development. It compares
  with the existing `_compareVersion` (version and build number).
- **Older than `minVersion`:** a full-screen **Update required** page before sign-in. It shows the installed and
  required versions, the message, and the download link as **selectable text plus a button**. Nothing else is
  reachable.
- **Older than `latestVersion` only:** a dismissible banner, once per app start.
- **Offline or read fails:** don't block; continue as today.

### Process (add to `README.md`)

When a release changes a callable's inputs, a rule an older app relies on, or a data shape, **raise `minVersion`**
to that build right after deploying it. Codemagic's build number is the `+N` part.

### Tests

- `_compareVersion` edge cases: `1.10.0` vs `1.9.0`, and build numbers.
- Older than the minimum: blocked. Between the minimum and the latest: banner. Read fails: not blocked.
- Rules: anyone reads, nobody writes.

**Paper:** Implementation Plan (Release Preparation: raise `minVersion` on breaking releases); data dictionary
(`settings/app`); Maintenance (Adaptive).

---

## 3. A separate development project (keep live data safe)

**Gap:** development runs, tests, the UAT and real accounts all use `smartpark-87e3d`. A script or test pointed at
it can change real data.

**Do:**
1. Create a second Firebase project, for example `smartpark-dev` (the user creates it in the console). It needs
   the Blaze plan for Cloud Functions; set a small budget on it (section 4).
2. Add aliases to `.firebaserc`:
   ```json
   { "projects": { "default": "smartpark-87e3d", "prod": "smartpark-87e3d", "dev": "smartpark-dev" } }
   ```
   Deploy with `firebase deploy --project dev` or `--project prod`. Never deploy to prod by default from scripts.
3. **App:** two build flavors, `dev` and `prod`. Run `flutterfire configure` once per project to get two
   `firebase_options` files, and pick one by flavor or `--dart-define`. The dev build shows a small **DEV** badge so
   screenshots are never taken from it by mistake.
4. **Day-to-day:** prefer the local emulators: `firebase emulators:start`. The Firestore emulator must use **port
   8081** on this PC (8080 is taken); change `firebase.json` only temporarily and restore it after. Add a seed script,
   `functions/scripts/seed-emulator.js`, that creates one test owner, facility, staff and driver.
5. **PayMongo:** the dev project uses its own test keys in its own Secret Manager.

**Not in scope:** moving the live demo data. `smartpark-87e3d` stays the project for demos and real use.

**Paper:** Implementation Plan (separate development and production environments); Development section (tools).

---

## 4. Alerts when something breaks or costs too much

**Gap:** a failing Cloud Function, a crash spike or an unexpected bill goes unnoticed until someone looks.

**Do (console, user clicks through):**
1. **Budget alert:** Google Cloud › Billing › Budgets & alerts. Create a monthly budget for `smartpark-87e3d` (for
   example PHP 500) with email alerts at 50%, 90% and 100%. Do the same for `smartpark-dev` if created.
2. **Cloud Function errors:** Google Cloud › Monitoring › Alerting. Create a policy on the log-based metric for
   Cloud Functions with severity ERROR or higher, more than 5 in 15 minutes, notifying the team's email.
3. **Crashlytics:** Firebase console › Crashlytics. Turn on new-issue and velocity (crash spike) email alerts.
4. **In app, server side (code):** in the existing 15-minute `reconcilePendingCheckouts` job, if `src/payment_health.js`
   finds **stuck payments** or an **overdue reconcile run**, send a push to admins (reuse `src/alerts.js`) at most
   once every 6 hours. Record `lastAlertAt` on `stats/reconcile`.

### Tests (for 4.4)

- An alert is sent when stuck payments exist.
- It isn't repeated within 6 hours.
- No alert when healthy.

**Paper:** Maintenance (Preventive: budget, error and crash alerts; payment alerts to admins).

---

## 5. One end-to-end test of the main flow

**Gap:** unit, widget and rules tests check pieces. Nothing runs the whole path across functions and rules: driver
creates a temporary QR, staff take payment, the driver confirms, entry, exit, the owner's reports and payment split.

### Approach: a server-side end-to-end test on the emulators

UI-driven tests need the camera and are slow, so drive the flow through the Cloud Functions and Firestore the way the
app does.

- **Location:** `functions/e2e/main-flow.test.js`, run with
  `firebase emulators:exec --only auth,firestore,functions --project demo-smartpark "node --test e2e/*.test.js"`.
  Add it as `npm run test:e2e` and a CI step.
- **PayMongo stub:** add a fake PayMongo client used **only when `process.env.FUNCTIONS_EMULATOR === 'true'` and
  `PAYMONGO_FAKE === '1'`**. It answers payment intents and checkouts as paid. **Never** let it load outside the
  emulator: the function must throw at startup if `PAYMONGO_FAKE` is set without the emulator.
- **Steps (each asserts state):**
  1. The seed creates an owner, an approved facility with rates, staff and a driver.
  2. Driver `createParkingPass` with a saved GCash number gives a temporary QR with the price.
  3. Staff `findGatePass`, `startGatePayment`; driver `payGatePass`; staff `checkGatePayment` until paid.
  4. Check one ticket, one payment and one payment split exist, with the 5% commission and matching amounts.
  5. Staff mark entry (the client write the rules allow), then exit after a fake stay with overtime; mark the
     overtime collected.
  6. Owner reads the reports' sources: sales total, commission, overtime cash. Owner records a cash handover;
     the logs are stamped once.
  7. A second attempt to pay the same temporary QR is refused, so no second ticket.
- **Also:** one test where staff **Turn away**: nothing is charged and no ticket is created.

**Paper:** Testing (one end-to-end test of the main flow on the emulators, with its result); the summary table and
totals.

---

## 6. Automatic dependency updates and a security audit

**Gap:** package security fixes arrive without anyone being told.

**Do:**
1. `.github/dependabot.yml`:
   ```yaml
   version: 2
   updates:
     - package-ecosystem: "pub"
       directory: "/smart_park"
       schedule: { interval: "weekly" }
       groups: { minor-and-patch: { update-types: ["minor", "patch"] } }
     - package-ecosystem: "npm"
       directory: "/smart_park/functions"
       schedule: { interval: "weekly" }
       groups: { minor-and-patch: { update-types: ["minor", "patch"] } }
     - package-ecosystem: "github-actions"
       directory: "/"
       schedule: { interval: "monthly" }
   ```
2. In `ci.yml`, in the functions job, add `npm audit --omit=dev --audit-level=high`. Start it with
   `continue-on-error: true` for a week to see the current findings. Fix or document them, then make it blocking.
3. Optionally, an informational `flutter pub outdated` step.

**Rule for merging Dependabot pull requests:** CI must pass. Merge major version bumps of Firebase, `mobile_scanner`
or PayMongo-related code only after a manual check on the phone.

**Paper:** Maintenance (Adaptive: dependency updates are proposed weekly and tested by CI).
