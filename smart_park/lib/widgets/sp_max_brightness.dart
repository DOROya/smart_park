import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Ticket QR colours: pure black on white whatever the app theme, which is
/// what gate scanners read most reliably.
const QrEyeStyle kTicketQrEyeStyle = QrEyeStyle(
  eyeShape: QrEyeShape.square,
  color: Color(0xFF000000),
);
const QrDataModuleStyle kTicketQrModuleStyle = QrDataModuleStyle(
  dataModuleShape: QrDataModuleShape.square,
  color: Color(0xFF000000),
);

const MethodChannel _screen = MethodChannel('smartpark/screen');

/// How many [SpMaxBrightness] widgets are on screen; brightness goes back to
/// normal when the last one leaves.
int _holders = 0;

void _set(bool on) {
  if (kIsWeb || !Platform.isAndroid) return;
  unawaited(
    _screen.invokeMethod<void>('setMaxBrightness', on).catchError((_) {}),
  );
}

/// Turns the screen to full brightness while [child] (a QR ticket) is
/// shown, so gate scanners read it first time, even outdoors.
class SpMaxBrightness extends StatefulWidget {
  const SpMaxBrightness({super.key, required this.child});

  final Widget child;

  @override
  State<SpMaxBrightness> createState() => _SpMaxBrightnessState();
}

class _SpMaxBrightnessState extends State<SpMaxBrightness> {
  @override
  void initState() {
    super.initState();
    if (_holders++ == 0) _set(true);
  }

  @override
  void dispose() {
    if (--_holders == 0) _set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
