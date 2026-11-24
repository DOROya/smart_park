# Quality-of-life features: implementation plan

**Status:** B, C and D built 2026-11-23; A (printer) not built, no hardware to test. Still to do: phone tests (plate reading in daylight and indoors, airplane mode, the app shortcut) and paper updates.

| # | Feature | Decision |
|---|---|---|
| A | Bluetooth thermal printer at the gate | **Build** |
| B | Read the plate with the camera | **Build**, as a separate mode next to the QR scanner (not at the same time) |
| C | End-of-day summary for owners | **Build** |
| D | Faster ticket at the gate: app shortcut and offline QR | **Build** |
| — | Pay overtime in the app at exit | **Don't build.** Stays as Recommendation 4. A defense script is at the end of this file |
| — | Filipino / Cebuano | **Not now** |

Rules for every item:
- **The security rules enforce it, not just the screens.**
- **PayMongo stays in test mode.**
- **No reservation or lot-full blocking** (SmartPark isn't a reservation app).
- **One facility per owner account.**
- Run rules tests on **port 8081** (8080 is taken on this PC), then restore `firebase.json`.
- After building, update the paper (Chapters 1-5 only). Each item lists what to change.

Relevant code today:
- Staff scanner: `lib/screens/staff/staff_home_page.dart`, with a `MobileScannerController` created in `initState`
  (`mobile_scanner: ^7.1.3`).
- Gate panels: `gate_result_card.dart`, `gate_pass_panel.dart`, `walk_in_panel.dart`.
- Receipts: `lib/services/parking_receipt.dart` and `lib/widgets/sp_receipt_button.dart` (`pdf`, `printing`).
- Push: `firebase_messaging`; device tokens in `users/{uid}.fcmTokens`, sent by `functions/src/reminders.js`
  (`sendToDriver`) and `src/alerts.js`.
- Scheduled jobs in `functions/index.js`: `reconcilePendingCheckouts` (15 min), `sendParkingReminders` (5 min),
  `refundLongSuspensions` (daily 06:00).

---

## A. Bluetooth thermal printer at the gate

**Why:** the UAT respondent suggested printed tickets (Recommendation 10). Walk-ins currently get nothing in hand,
and some drivers want paper.

### What prints

| Slip | When | Contents |
|---|---|---|
| **Walk-in stub** | Walk-in entry (Car in, Motor in, third type) | Facility name, "WALK-IN", vehicle type, plate if entered, entry date and time, staff name, and a small QR code (`SPW:<activityLogId>`) |
| **Walk-in receipt** | Walk-in exit with a fee | Facility, plate, entry and exit times, length of stay, fee in PHP, staff name |
| **Parking receipt** | On request, from a scan result or ticket trace | The same fields as the driver's in-app receipt (`ParkingReceipt`): facility, vehicle, plate, package, payment method and reference, overtime cash, latest stay. **No ticket QR**, so a printed receipt can't be used to enter, the same rule as the in-app receipt |
| **Reprint last** | Staff menu | Reprints the last slip printed on this phone |

Every slip ends with: "Not an official receipt. For record-keeping only." This matches the Limitations line about BIR
sales books.

### Walk-in stub QR (makes walk-in exits faster)

- The stub's QR holds `SPW:<activityLogId>` of the walk-in entry.
- At **Exit**, if the scanner reads a code starting with `SPW:`, open the walk-in exit for that entry directly
  (fee field ready) instead of the "not a SmartPark ticket" result.
- At **Entry**, an `SPW:` code shows "This is a walk-in stub, not a ticket."
- The stub QR is only a shortcut. The walk-in can still be exited from the Walk-ins panel without it.

### Hardware and package

- Any common **58 mm Bluetooth ESC/POS** receipt printer (the cheap handheld kind sold locally).
- **Package:** pick a maintained Flutter ESC/POS Bluetooth package on pub.dev, for example
  `print_bluetooth_thermal` with `esc_pos_utils_plus` for formatting. **Check the current versions and Android 12+
  support before choosing.** Pin an exact version.
- **Android permissions:** `BLUETOOTH_CONNECT` and `BLUETOOTH_SCAN` (Android 12+), requested through the existing
  `permission_handler`. Add them to `AndroidManifest.xml`.
- **Text-based printing** (ESC/POS text and the printer's built-in QR command) is fast and works on cheap printers.
  Don't print the PDF as an image.

### App

- **Staff Dashboard › Printer** (or the gear menu): **Connect printer** lists paired Bluetooth printers. Remember the
  chosen one on this phone (`SharedPreferences` is fine; it's a per-device setting). Add **Print test slip**.
- **Settings (same screen):**
  - **Print a stub for every walk-in entry**, on or off; off by default until a printer is connected.
  - **Print a receipt for walk-in exits with a fee**, on or off.
- **After each walk-in entry or exit**, print automatically if the setting is on. Otherwise show a **Print** button
  in the result.
- **No printer or printing fails:** the gate never blocks. Show "Couldn't print. Check the printer." with **Retry**,
  and the scan or walk-in is already saved.
- **Owner:** no setup needed. The printer belongs to the gate phone.

### Data

No new collections. Optionally add `printedAt` (Timestamp) to walk-in `activity_logs` entries. If so, staff may set
it once; rules allow only that field, only when it's missing.

### Tests

- Slip text formatting: widths for 58 mm (32 characters per line), long facility names wrap, and amounts in PHP.
- `SPW:` codes: parsed at Exit, refused at Entry, unknown IDs refused.
- The gate flow continues when printing throws.
- The settings toggles are respected.

Real printing needs the device and a printer: test once on the phone with a real printer and keep a photo of a
printed stub for the paper.

### Paper

- Scope bullet ("optional Bluetooth receipt printer at the gate").
- Staff screen description and the Walk-ins paragraph.
- Hardware Requirements (optional 58 mm Bluetooth printer).
- Recommendation 10: printed tickets are now done; keep the BIR accreditation part.
- Data dictionary note on `SPW:` stubs; Development cycle; test rows; User's Guide F.4.

---

## B. Read the plate with the camera

### How reliable it is

On-device text recognition (Google ML Kit, Latin script) reads clean, well-lit plates well. It gets worse with:
- glare and headlights at night;
- dirty, bent or faded plates;
- steep angles;
- small motorcycle plates;
- plate frames, stickers or dealer text near the plate.

It will sometimes miss or misread a character (0/O, 1/I, 8/B). So it must **fill the field for the staff member to
confirm, never save on its own**. It runs on the phone with no internet and no cost.

### Can it coexist with the QR scanner?

**Yes, as a separate mode, not at the same moment.** The QR scanner (`MobileScannerController`) holds the camera, so
two camera users can't run at once on most phones. The pattern:
1. A **camera icon button** beside each plate field: Walk-ins plate, "Camera cannot read the QR? Type the plate",
   and the plate lookup.
2. Tapping it **stops** the QR scanner (`_scannerController.stop()`) and opens a **Read plate** sheet.
3. The sheet takes a **still photo** (tap to capture, or capture when the user holds steady), runs text recognition
   on it, and shows the candidates.
4. Closing the sheet **restarts** the QR scanner (`_scannerController.start()`).

A still photo is more reliable than reading live video, and simpler to build.

### Package

- `google_mlkit_text_recognition` (on-device, Latin script). Check the current version on pub.dev; pin it exactly.
- For the photo: the `camera` package, or the picker for a still image. Check it doesn't conflict with
  `mobile_scanner` while the scanner is stopped.

### Picking the plate out of the text

- Normalize: uppercase, keep A-Z and 0-9, and treat spaces and dashes as separators.
- Score tokens against common Philippine formats, for example 3 letters + 3-4 digits (`ABC 1234`) for cars and
  digits plus letters for motorcycle plates. Keep the patterns in one place, `lib/services/plate_reader.dart`, so they
  can be tuned.
- **Rank candidates higher when they match a plate the facility already knows:** vehicles inside now, today's
  temporary QRs, and recent walk-ins. Reading "ABC 1234" when "ABC 1234" is parked is almost certainly right.
- Show the best guess in large text plus up to two alternatives as chips. Staff tap one, or edit it, before it fills
  the field.
- **If nothing plate-like is found,** show "Couldn't read a plate. Try again closer, or type it." Never fill
  something random.

### Tests

- Plate extraction from sample recognized text: clean plate, plate with frame text, 0/O and 1/I confusion, and
  motorcycle formats.
- Ranking prefers a known parked plate.
- The scanner stops when the sheet opens and restarts when it closes (widget test with a fake controller).
- Nothing fills the field without the staff member's tap.

Test on the real phone in daylight and indoor light with a few real plates. Note the results honestly in the paper,
for example "read correctly in N of M tries in daylight".

### Paper

- Scope bullet; staff screen description.
- Technical Background: ML Kit on-device text recognition.
- Limitations: it reads clear plates but staff must confirm; lighting and dirty plates reduce accuracy.
- Development cycle; test rows; User's Guide F.4.

---

## C. End-of-day summary for owners

**What:** one push notification per day per owner, at a time the owner chooses (default **9:00 PM**), for example:

> **Juliville Parking — today**
> 42 entries, 40 exits, 2 still inside · PHP 3,200 sales · PHP 240 walk-in cash · PHP 60 overtime not collected ·
> Juan Dela Cruz hasn't handed over PHP 300 · Pedro is still clocked in

Tapping it opens the owner app on **Reports** (today), or on **Staff** if cash or a shift needs action.

### Settings

`users/{ownerUid}.notificationPrefs.dailySummary`:

| Field | Type | Notes |
|---|---|---|
| `enabled` | Boolean | Default `true` for owners |
| `hour` | Number | 0-23, Philippine time; default `21` |

The owner writes only their own `notificationPrefs` (check the existing rule allows this map; extend if needed).
The app setting goes under **Profile › Notifications › Daily summary**: a toggle and a time picker (hour only).

### Function

`sendOwnerDailySummaries`: `onSchedule("0 * * * *")`, time zone `Asia/Manila`, region `asia-southeast1`.
1. Find owners whose `dailySummary.enabled` is true and whose `hour` equals the current Manila hour.
2. For each owner's facility, compute **today's Manila day** figures from the same sources the Reports tab uses:
   - entries, exits and vehicles inside (`activity_logs`, `establishment_occupancy`);
   - sales (`payment_splits` gross for the day, extra hours included);
   - walk-in cash (`walkInFee` on walk-in exits);
   - overtime not collected (exits with overtime and no collected status);
   - cash not handed over (gate cash on logs without `cashHandoverId`, grouped by staff);
   - staff still clocked in (`staff_shifts` with `endedAt == null`).
3. **If nothing happened today** (no scans, no sales), skip the push.
4. Send to the owner's `fcmTokens`, dropping dead tokens the way `sendToDriver` does. Data payload
   `{ kind: 'owner_daily_summary', tab: 'reports' or 'staff' }`, handled in `parking_owner_home_screen.dart`
   next to the existing `owner_facility_status` and `owner_staff_flag` kinds.
5. **Don't send twice the same day:** record `lastSentDay` in `users/{ownerUid}.notificationPrefs.dailySummary`
   (server-written). If an hour's run is retried, it sees it already sent.

Put the figures in a pure function, `summarizeOwnerDay(...)` in `src/owner_summary.js`, so it can be unit-tested
without Firestore.

### Tests

- `summarizeOwnerDay`: sales, walk-in cash, uncollected overtime and cash per staff for a sample day.
- The Manila day boundary: a scan at 11:30 PM counts today, one at 12:10 AM counts tomorrow.
- A quiet day sends nothing.
- `lastSentDay` prevents a second send.
- The time setting is respected.
- Rules: an owner can change only their own `dailySummary.enabled` and `hour`, not `lastSentDay`.

### Paper

- Scope bullet; owner screen description (Profile › Notifications).
- Cloud Functions table (`sendOwnerDailySummaries`, hourly).
- Data dictionary Users (`notificationPrefs.dailySummary`).
- Push notification bullet; Development cycle; test rows; User's Guide F.3.

---

## D. Faster ticket at the gate

### D1. App shortcut: "Show my ticket"

- Use the `quick_actions` package (check the current version; pin it exactly). Long-pressing the SmartPark icon
  shows **Show my ticket**.
- **Signed in as a driver,** it opens the best ticket directly at full brightness, choosing in this order:
  1. a ticket **checked in now**;
  2. otherwise the most recent **paid ticket with hours left**;
  3. otherwise the newest **unused temporary QR**;
  4. otherwise the Tickets tab with "No active ticket".
- **Staff:** the shortcut is **Open scanner** instead. Owners and admins get none.
- Register the shortcut after sign-in, based on the role, and clear it on sign-out.
- Optional: an Android home-screen widget is more work, so skip it unless there's time.

### D2. The QR shows with no signal

The ticket QR is drawn on the phone (`qr_flutter`) from the ticket ID, so it needs no network once the ticket is
known. Basements often have no signal.
- Cloud Firestore keeps a local copy on Android by default. **Check nothing turns this off**, and that the ticket
  and temporary-QR screens read from the cache when offline instead of waiting on the network: use the snapshot
  listener's cached data, and show a small "Offline: showing your saved ticket" note.
- **Also save the last active ticket** (ID, plate, vehicle type, facility, hours left, last updated) to local
  storage when it's shown. The shortcut can then open it even on a cold start with no signal.
- **Hours left offline** are shown as "as of [time]". Staff still validate at the gate.
- **Paying a temporary QR still needs data** (unchanged; it's in the Limitations).

### Tests

- Shortcut routing picks the right ticket in each case.
- The staff shortcut opens the scanner.
- The shortcut is cleared on sign-out.
- With the network off (Firestore offline in a test, or a fake repository), the ticket screen shows the cached ticket
  and the offline note.
- Test once on the phone in airplane mode.

### Paper

- Scope bullet; driver screen description (Tickets).
- Limitations: entry and payment still need data; showing the ticket doesn't.
- Development cycle; test rows; User's Guide F.2 (long-press the app icon).

---

## Not building: pay overtime in the app (Recommendation 4)

Keep Recommendation 4 as it is: "Allow drivers to pay overtime fees within the app through PayMongo instead of in
cash at the gate, building on the option to buy more hours before overtime starts."

### Defense script, if the panel asks why overtime is still paid in cash

> "Overtime is the one charge we kept in cash on purpose. Overtime is only known at the exit, when the car is
> already at the gate, so collecting it online would make the driver open GCash and wait while cars line up behind
> them. That's slower than handing over a few pesos.
>
> What we did instead is prevent overtime before it happens. Drivers get a reminder before their paid time ends and
> another when overtime starts, and from either one they can tap Add hours and pay in the app, at the ticket's own
> rate, before they reach the gate. So drivers who want to stay cash-free can.
>
> The cash that is collected isn't lost track of. Staff confirm each overtime collection in the app, the owner sees
> collected versus uncollected overtime in Reports, cash handovers record which staff member handed over what, and
> any change to an exit's overtime status is in the audit log.
>
> Paying overtime online at the exit is our Recommendation 4. Most of it already exists, because the gate can
> already take a payment on the driver's phone, so it's a natural next step once the app runs in live mode."

Short version:

> "Overtime is only known at the exit, so paying it online would hold up the gate. Drivers can avoid it by adding
> hours from the reminder, cash collections are tracked and audited, and online overtime payment is Recommendation
> 4."
