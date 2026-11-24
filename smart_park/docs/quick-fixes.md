# Quick fixes: implementation plan

**Status:** items 1, 2 and 4 built 2026-11-23; item 3 (comment moderation) not built, by decision. Still to do: paper updates.
These are gaps a defense panel could ask about that are small to close. They're independent of each other and of
`docs/supervisor-role.md`, so build them in any order. Suggested order: 1 and 3 (smallest), then 2, then 4.

Rules for every item:
- **The security rules enforce it, not just the screens.** Every new field gets a rules check and a rules test.
- **Facility and rating changes are audit-logged.** `src/audit.js` already watches `establishments` and
  `establishment_details`. Add `facility_ratings` and any new collection where noted.
- **PayMongo stays in test mode.**
- **Owner role:** one facility per owner account. Don't add multi-facility support.
- Run rules tests on **port 8081** (8080 is taken on this PC), then restore `firebase.json`.
- After building, update the paper (Chapters 1-5 only). Each item lists what to change.

---

## 1. Facility contact number

**Gap:** a driver can't reach the lot from the app, for example when the gate is unattended or something goes
wrong.

**Data:** `establishments/{id}.contactNumber` (String, optional, Philippine mobile or landline). Store mobiles as
`+639XXXXXXXXX`, using the same normalizer as the saved GCash number (`normalizePhMobile` in
`functions/src/gate_pass.js`; mirror it in Dart). Keep landlines as typed, digits, spaces and dashes only.

**Rules:** only the owner writes it; it's validated as a string of at most 20 characters. It's public like the rest of
`establishments`.

**App:**
- Owner facility form (register and edit): a **Contact number** field (optional) with a hint, "Shown to drivers
  so they can call the facility."
- Driver establishment details, Overview tab, Location & Hours card: show the number as **selectable text**
  with a **Call** button (`tel:` link) and a copy button. `tel:` links don't always work, so the number must stay
  readable and copyable.
- Driver ticket details: the same number, so a driver at the gate can call.

**Tests:** normalization; rules (owner may set it, others may not, too long refused); the widget shows the number and
the Call button only when it's set.

**Paper:** Scope bullet; the establishment details screen description; data dictionary Establishments
(`contactNumber`); the owner registration step in the User's Guide; a Development cycle; test rows.

---

## 2. Temporary closure ("Closed until")

**Gap:** operating hours are only the regular weekly hours. A lot that closes for a holiday, an event or repairs
still shows as open.

**Data:** `establishment_details/{id}`:

| Field | Type | Notes |
|---|---|---|
| `closedUntil` | Timestamp or null | Closed until this moment; null means no closure |
| `closedReason` | String | Optional, up to 120 characters, for example "Closed for the holiday" |

**Rules:** only the owner (and later the supervisor, if `canOperate` exists) writes these two fields.
`closedUntil` must be in the future and at most 30 days ahead. Clearing it is always allowed.

**Behavior:**
- **Discovery and details:** while `closedUntil` is in the future, the facility shows **Closed until [date, time]**
  with the reason. It counts as not open for the **Open now** filter.
- **Gate, entry:** refuse new entries and walk-in entries, with the reason "Facility temporarily closed until …".
  Reuse the path that already refuses entries at a suspended facility.
- **Gate, exit:** exits still go through, so nobody is locked in.
- **Overtime:** time while temporarily closed is not charged, the same rule as regular closed hours. Extend the
  closed-hours overtime code to subtract the closure window.
- **Temporary QRs and paid tickets:** stay valid. A ticket is not a reservation and its hours don't count down while
  the driver isn't parked, so no refund is needed. Drivers holding the facility's tickets get one push notification
  when a closure is set.
- **After `closedUntil`:** the facility reopens automatically, with no job needed, because everything compares
  against the current time.

**App:** Owner Facility home: **Close temporarily**, which asks for an until date and time and a reason, and shows a
banner with **Reopen now** while closed.

**Tests:** gate refuses entry but allows exit while closed; the Open now filter; overtime subtracts the window;
rules (future only, 30-day limit, owner only); reopening automatically when the time passes.

**Paper:** Scope bullet; owner and driver screen descriptions; data dictionary Establishment Details; Limitations,
if any limit stays; a Development cycle; test rows; User's Guide (owner step, driver note).

---

## 3. Rating comment moderation

**Gap:** facility ratings (added November 20) allow a free-text comment, but nobody can remove an abusive or
off-topic one. Fake ratings are already prevented: only a driver whose ticket was used can rate, once per ticket.

**Data:** `facility_ratings/{ticketId}`:

| Field | Type | Notes |
|---|---|---|
| `commentHidden` | Boolean | Set by an administrator; the comment is no longer shown anywhere |
| `hiddenReason` | String | Optional, admin-only |
| `reportedByOwner` | Boolean | The owner flagged the comment for review |
| `reportedAt` | Timestamp | When it was flagged |

**Rules:**
- The owner of the rated facility may set only `reportedByOwner: true` and `reportedAt`, once.
- Only an administrator may set `commentHidden` and `hiddenReason`.
- The driver may still edit their rating; editing the comment clears `reportedByOwner` but **not**
  `commentHidden`.
- The stars still count toward the average after a comment is hidden: it's the comment that's moderated, not the
  rating. `updateFacilityRating` (`src/ratings.js`) needs no change.

**App:**
- Owner Driver Ratings card: **Report comment** on each comment, with a confirmation that names what happens next.
- Admin dashboard: a **Reported comments** card next to Facility Reports, with **Hide comment** or **Keep**.
- Hidden comments disappear from the owner's card and anywhere drivers see comments. The driver who wrote it sees
  "Your comment was hidden by SmartPark."
- Add `facility_ratings` to the audit log's watched collections, so a hide is recorded with the admin's name.

**Tests:** rules (the owner can report only their own facility's ratings, only once; only an admin hides); a hidden
comment leaves the card but the average is unchanged; the audit entry.

**Paper:** Scope bullet (moderation); data dictionary Facility Ratings fields; admin and owner screen descriptions;
Terms (a line that SmartPark may hide comments that are abusive or not about the facility); test rows.

---

## 4. Configurable commission, with a terms update and an owner announcement

**Gap:** the 5% commission is fixed in code (`functions/src/pricing.js` `PLATFORM_FEE_RATE = 0.05` and
`lib/services/platform_fees.dart` `kPlatformFeeRate = 0.05`). Changing it means redeploying, and owners would not be
told. Recommendation 7 in the paper already lists it.

The change must be transparent: owners learn about a new rate **before** it applies, the old rate keeps applying to
anything already sold, and the record of who changed it and when is kept.

### 4a. Rate stored on the server, copied onto every sale

**Data:** `settings/platform` (new document, server-written only):

| Field | Type | Notes |
|---|---|---|
| `commissionRate` | Number | Current rate, for example `0.05` |
| `pendingRate` | Number or null | Next rate, if a change is scheduled |
| `pendingEffectiveAt` | Timestamp or null | When `pendingRate` takes over |
| `minNoticeDays` | Number | `30`; a change can't take effect sooner |
| `updatedBy`, `updatedAt` | | Admin who scheduled the change |

**Rules:** everyone signed in may read `settings/platform` (owners and drivers see the rate). Nobody writes it from
the app; only the new callable `scheduleCommissionChange` writes it.

**Pricing:**
- Replace the constant with a helper `commissionRateAt(now)`, which returns `pendingRate` once
  `now >= pendingEffectiveAt`, otherwise `commissionRate`.
- The price is fixed **when the temporary QR is created** (`createParkingPass`) and for extra hours
  (`addTicketHours`). Save the rate used on the checkout record as `commissionRate`, and copy it onto the ticket and
  the payment split, like `purchaseOvertimeRate`.
- `confirmParkingCheckout`, the gate payment and the reconcile job use the **rate saved on the checkout**, never the
  current one. A driver or owner is never charged a rate that changed after the price was shown.
- Refund recovery and every report already work from the saved split amounts, so they stay correct across a change.
- The app copy (`platform_fees.dart`) reads the rate from `settings/platform` for display only. Keep the existing
  test that compares the app's and the server's pricing rules, and extend it for a non-5% rate.

**Callable `scheduleCommissionChange({ rate, effectiveAt, message })`, admin only:**
- `rate` between 0.01 and 0.15. `effectiveAt` at least `minNoticeDays` (30) days ahead. Lowering the rate may take
  effect sooner, at least 1 day ahead, since it only helps owners.
- Writes `pendingRate` and `pendingEffectiveAt`, creates the owner announcement (4c), and writes an audit entry
  `platform.commission_scheduled` with the old and new rate.
- **Cancel:** `cancelCommissionChange()` clears the pending change, posts a short follow-up announcement and
  writes an audit entry.
- A daily job (add to the existing 06:00 job) moves `pendingRate` into `commissionRate` once `pendingEffectiveAt`
  has passed and writes `platform.commission_changed` to the audit log. Pricing doesn't depend on the job running,
  because `commissionRateAt` already checks the time.

**Admin app:** Settings › **Commission rate**: shows the current rate, any scheduled change and its date, and
**Schedule a change** (new rate, effective date, a message to owners) with a preview of the announcement before
sending. Remove the line "fixed at 5% and not configurable from this screen".

### 4b. Terms and Conditions (`lib/content/terms_content.dart`)

Rewrite the owner and driver commission points so the terms don't need a new version every time the rate changes:
- **Rate:** "SmartPark keeps a platform commission from each payment made in the app. The current rate is shown in
  the app under Reports and is **[current rate]**."
- **Notice:** "SmartPark may change the commission rate. Owners are told in the app at least 30 days before a
  higher rate takes effect. A lower rate may take effect sooner."
- **Old sales keep their rate:** "A change applies only to purchases made on or after its effective date.
  Tickets, extra hours and refunds of earlier purchases keep the rate in force when they were bought."
- **Owners who disagree:** "An owner who does not accept a new rate may stop selling through SmartPark before it
  takes effect by asking SmartPark to deactivate the facility or by deleting their account. Tickets already sold
  stay valid, and refunds follow the refund terms."
- **Drivers:** the parking price is set by the owner and the commission comes out of the owner's share, so a rate
  change never changes what a driver is charged for a package already shown.

Bump `kTermsVersion` once for this wording change; everyone accepts again on next open, as today. Later rate changes
need **no** new terms version, only the announcement.

Also update the Privacy Notice only if new personal data is collected. It isn't: announcements store only who saw
them and when.

### 4c. Announcements to owners (pop-up once, kept in the Profile)

A general announcement feature, so it also works for future platform notices, with commission changes as the
first use.

**Data:**
- `announcements/{id}`, written by the server only:
  `audience` (`owners`, `drivers`, `staff` or `all`), `title`, `body`, `kind` (`commission_change` or
  `general`), `effectiveAt` (optional), `createdBy`, `createdAt`, `oldRate` and `newRate` (for commission changes).
- `users/{uid}/announcement_reads/{announcementId}`: `seenAt`, and `acknowledgedAt` for commission changes.
  Written only by that user, with only these fields.

**Rules:** an announcement is readable by signed-in users whose role matches `audience`. Nobody writes
announcements from the app. Each user writes only their own `announcement_reads`.

**App: an `AnnouncementWatcher`.** Model it on `DriverWarningWatcher`
(`lib/screens/driver/widgets/driver_warning_watcher.dart`), which already shows a warning once when the app
opens, never in the middle of use.
- On app open or resume, find announcements for the user's role that have no `announcement_reads` entry, and show
  them **one at a time** in a dialog.
- A **commission change** dialog shows the old rate, the new rate, the effective date, and an example
  ("On a PHP 100 sale, SmartPark keeps PHP 5.00 now and PHP 7.00 from Jan 1, 2027"). It has a link to the updated
  terms and an **I understand** button that saves `acknowledgedAt`. Closing without acknowledging shows it again on
  the next open, until the effective date.
- Never show a dialog at the gate: on staff screens, only once the Scanner isn't active.
- **Profile › Announcements** lists every announcement for the role, newest first, so it can be read again.
- **Push:** also send the announcement as a push notification to owners (reuse `src/alerts.js` token handling).
  Tapping it opens the dialog.

**Owner Reports:** under the Commission tile, show "Rate: 5%". While a change is scheduled, add "7% from Jan 1,
2027" with a link to the announcement.

**Admin:** for each commission announcement, show how many owners have acknowledged it ("12 of 15 owners"). This is
the transparency record if an owner later disputes the change.

### 4d. Tests

- **Pricing:**
  - A checkout made before the effective date keeps the old rate even when it's paid after it.
  - Extra hours use the rate at the time they're bought.
  - The split uses the saved rate.
  - The app's and the server's pricing rules agree at 5% and at another rate.
- **Callable:**
  - Admin only.
  - Rate limits.
  - Notice period: 30 days for an increase, 1 day for a decrease.
  - Creates the announcement and the audit entry.
  - Cancel works.
- **Rules:**
  - Nobody writes `settings/platform` or `announcements` from the app.
  - A user writes only their own `announcement_reads`.
  - An owner can't read driver-only announcements.
- **Widget tests:**
  - The dialog shows once.
  - "I understand" records the acknowledgement.
  - It reappears if dismissed before the effective date.
  - It never shows on the active Scanner.
  - Profile › Announcements lists it.
- **Terms test:** the commission wording reads the current rate and states the 30-day notice.

### 4e. Paper (Chapters 1-5)

- **Scope:** "commission rate set by the administrator with 30 days' notice to owners, announced in the app".
  **Limitations:** remove "fixed at 5% and cannot be changed". **Recommendation 7:** remove the commission part.
- **Data dictionary:** new tables for `settings/platform`, `announcements` and `announcement_reads`; the
  `commissionRate` field on Parking Checkouts, Transactions and Payment Splits. Tables after the insert point
  renumber, so use the same renumbering approach as `scripts/nov22_features_2026_11_22.py`.
- **Purpose and Description, Technical Background, payment descriptions:** say "the platform commission
  (currently 5%)" where the paper says "5%" as a fixed rule. Keep 5% where it describes the evaluated system.
- **Privacy and Terms paragraph:** the notice period and that old sales keep their rate.
- **Cloud Functions table:** the new callables.
- **Development:** a new cycle. **Testing:** new test rows and totals.
- **Diagrams:** an Admin use case "Schedule Commission Change" and an Owner use case "Acknowledge Announcement";
  the Commission Dashboard class diagram gets `commissionRate`.
- **User's Guide:** an admin step (schedule a change) and an owner note (announcements pop up once; read them
  again in the Profile).
