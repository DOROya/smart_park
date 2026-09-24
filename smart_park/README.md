# SmartPark

Flutter app for drivers, parking owners, gate staff and admins, backed by
Firebase (Auth, Firestore, Storage, Cloud Functions) and PayMongo.

## Layout

- `lib/` – Flutter app.
- `functions/` – Cloud Functions (Node 22): PayMongo checkout and platform
  statistics. The PayMongo secret key lives only here, in Secret Manager.
- `firestore.rules`, `storage.rules` – security rules.
- `functions/rules-test/` – emulator tests for both rule files.

## How payments work

1. The driver app calls `createParkingCheckout` with the establishment,
   vehicle, plan and plate. The function prices the package from the
   establishment's own rates and opens a PayMongo checkout session.
2. The app shows the checkout in a web view and polls
   `confirmParkingCheckout`. When PayMongo reports the session paid, the
   function writes the ticket (`transactions`), `payments`,
   `payment_splits` and the day's totals (`stats_daily`, `stats/platform`).
3. `reconcilePendingCheckouts` runs every 15 minutes and finalizes paid
   checkouts the app never confirmed (app closed, connection lost).

No client can write tickets, payments, splits or stats; the rules deny it.

## Running the app

```sh
flutter run -d <device>
```

The app no longer needs PayMongo keys, so `--dart-define-from-file=paymongo.dev.json`
is not required.

## Tests

CI (`.github/workflows/ci.yml`) runs all of these on every push to `master`
and every pull request, plus `dart format` and `flutter analyze`, which must
report no issues.

```sh
flutter test                      # Dart unit/widget tests (incl. gate scanning)
cd functions && npm test          # function unit tests (pricing, PayMongo payload)
cd functions && firebase emulators:exec --only firestore,storage \
  --project demo-smartpark "node --test --test-concurrency=1 rules-test/firestore.test.js rules-test/storage.test.js"
```

## Deploying (in this order)

Cloud Functions need the Blaze (pay-as-you-go) plan.

1. Install function dependencies: `cd functions && npm install`.
2. Store the PayMongo secret key (starts with `sk_`):
   `firebase functions:secrets:set PAYMONGO_SECRET_KEY`
3. Deploy the functions and indexes:
   `firebase deploy --only functions,firestore:indexes`
4. Release the updated app to every device. Older builds create payments
   on the phone, which the new rules reject.
5. Deploy the rules:
   `firebase deploy --only firestore:rules,storage`
   (On the first Storage deploy, allow the prompt that lets Storage rules
   read Firestore.)
6. Sign in as an admin, open Settings and tap **Rebuild statistics** once, so
   the dashboard includes payments made before the stats existed.

Each parking owner should open the app once after the update. That moves
their staff records to the new layout (staff can't scan until it's done)
and their business documents to the private `establishment_private` doc.

Admins are regular users whose `users/{uid}.role` is `admin`, set by hand
in the Firebase console. The app never lets anyone give themselves that role.

## App Check

The app sends App Check tokens (Play Integrity on Android, App Attest with
DeviceCheck fallback on iOS, the debug provider in debug builds). The
functions accept requests without a token until you turn enforcement on:

1. Firebase console > App Check: register the Android app with Play
   Integrity (add the app's SHA-256 fingerprints) and the iOS app with
   App Attest.
2. Run a debug build on each dev device/emulator, copy the debug token it
   prints to the log, and add it under App Check > Apps > Manage debug tokens.
3. Watch App Check > APIs for a few days until almost all requests are
   verified. Then enforce it for Firestore and Storage there, and for the
   functions by adding `ENFORCE_APP_CHECK=true` to `functions/.env` and
   running `firebase deploy --only functions`.

## Crash reporting

Release builds send uncaught errors to Firebase Crashlytics, along with handled
failures reported through `reportError()` (`lib/services/error_reporter.dart`).
Debug builds report nothing. Use `reportError` in any `catch` block where a
failure would otherwise go unnoticed.

## Code layout

Screens live under `lib/screens/<role>/`. Firestore logic that makes
decisions belongs in `lib/services/`, with `FirebaseFirestore` injected, so
it can be tested with `fake_cloud_firestore`. See `gate_scan_service.dart`
and `test/gate_scan_service_test.dart` for the pattern.
