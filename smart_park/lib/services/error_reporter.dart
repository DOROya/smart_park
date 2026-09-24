import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Records a handled (non-fatal) error so it shows up in Crashlytics instead
/// of disappearing inside a `catch` block. Safe to call from tests, where
/// Firebase is not initialized.
void reportError(Object error, StackTrace stack, {required String reason}) {
  debugPrint('SmartPark: $reason: $error');
  if (Firebase.apps.isEmpty) return;
  unawaited(
    FirebaseCrashlytics.instance.recordError(error, stack, reason: reason),
  );
}
