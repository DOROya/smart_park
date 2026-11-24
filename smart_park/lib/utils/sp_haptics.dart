import 'dart:async';

import 'package:flutter/services.dart' show HapticFeedback;

/// A short buzz for good news: a payment went through, hours were added.
void spHapticSuccess() => unawaited(HapticFeedback.mediumImpact());

/// A stronger double buzz for something the driver must act on now, such as
/// staff confirming space at the gate while the phone is in a pocket.
void spHapticAttention() {
  unawaited(HapticFeedback.heavyImpact());
  unawaited(
    Future<void>.delayed(
      const Duration(milliseconds: 160),
      HapticFeedback.heavyImpact,
    ),
  );
}

/// One firm buzz for a no: turned away, payment stopped.
void spHapticWarning() => unawaited(HapticFeedback.heavyImpact());
