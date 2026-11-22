/// Firebase App Check: proves to Firebase that a request comes from the real
/// SmartPark app on a real phone, not a script holding the app's API key.
///
/// Once activated, Cloud Functions, Firestore and Storage calls carry an App
/// Check token. Whether a missing or bad token is refused is decided on the
/// server (ENFORCE_APP_CHECK in functions/.env for Cloud Functions; the
/// Firebase console for Firestore and Storage), so turning this on in the
/// app never locks anyone out by itself.
library;

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// A fixed debug token for development builds, so it only has to be
/// registered once in the Firebase console (App Check > Apps > Manage debug
/// tokens). Pass it with `--dart-define=APP_CHECK_DEBUG_TOKEN=<uuid>`.
/// Without it, the debug provider prints a new token to the log.
const String _debugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

/// Starts App Check: Play Integrity (Android) and App Attest (iOS) in
/// release builds, the debug provider in debug builds. Never throws: if App
/// Check can't start, the app still opens and requests go without a token.
Future<void> activateAppCheck() async {
  final bool supported =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (!supported) return;
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? AndroidDebugProvider(
              debugToken: _debugToken.isEmpty ? null : _debugToken,
            )
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? AppleDebugProvider(
              debugToken: _debugToken.isEmpty ? null : _debugToken,
            )
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
    // Tokens refresh in the background before they expire.
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  } catch (error, stack) {
    debugPrint('App Check did not start: $error\n$stack');
  }
}
