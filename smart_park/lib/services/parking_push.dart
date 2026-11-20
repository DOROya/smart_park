import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'error_reporter.dart';

/// How long before paid time ends a driver can be reminded, in minutes
/// (matches LEAD_CHOICES in functions/src/reminders.js).
const List<int> kReminderLeadChoices = <int>[15, 30, 60];

/// A driver's notification choices (`users/{uid}.notificationPrefs`).
/// Everything is on by default, 30 minutes ahead.
class ParkingNotificationPrefs {
  const ParkingNotificationPrefs({
    this.parkingReminders = true,
    this.leadMinutes = 30,
    this.overtimeAlerts = true,
  });

  factory ParkingNotificationPrefs.fromUser(Map<String, dynamic>? user) {
    final Object? raw = user?['notificationPrefs'];
    final Map<dynamic, dynamic> p = raw is Map ? raw : <dynamic, dynamic>{};
    final int lead = ((p['leadMinutes'] as num?) ?? 30).toInt();
    return ParkingNotificationPrefs(
      parkingReminders: p['parkingReminders'] != false,
      leadMinutes: kReminderLeadChoices.contains(lead) ? lead : 30,
      overtimeAlerts: p['overtimeAlerts'] != false,
    );
  }

  final bool parkingReminders;
  final int leadMinutes;
  final bool overtimeAlerts;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'parkingReminders': parkingReminders,
    'leadMinutes': leadMinutes,
    'overtimeAlerts': overtimeAlerts,
  };
}

/// Registers this phone for the server's parking reminders (see
/// functions/src/reminders.js) and shows them while the app is open.
class ParkingPush {
  ParkingPush._();

  static StreamSubscription<String>? _refresh;
  static StreamSubscription<RemoteMessage>? _foreground;
  static StreamSubscription<RemoteMessage>? _opened;

  /// Sent when staff confirm space for a temporary QR; carries `checkoutId`.
  static const String kGateConfirm = 'gate_confirm';

  static DocumentReference<Map<String, dynamic>> _user(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  /// Asks for permission (Android 13+ shows a prompt once) and saves this
  /// phone's token on the driver. [onForeground] shows a message that
  /// arrives while the app is open, since the system tray only shows them
  /// in the background. [onOpen] gets the data of a notice the driver
  /// tapped (also the one that launched the app).
  static Future<void> register(
    String uid, {
    required void Function(String title, String body) onForeground,
    void Function(Map<String, dynamic> data)? onOpen,
  }) async {
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      final NotificationSettings settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final String? token = await messaging.getToken();
      if (token != null) await _save(uid, token);
      await _refresh?.cancel();
      _refresh = messaging.onTokenRefresh.listen((String t) => _save(uid, t));
      await _foreground?.cancel();
      _foreground = FirebaseMessaging.onMessage.listen((RemoteMessage m) {
        // With the app open, the temporary QR opens by itself instead.
        if (m.data['kind'] == kGateConfirm) return;
        final RemoteNotification? n = m.notification;
        if (n != null) onForeground(n.title ?? '', n.body ?? '');
      });
      if (onOpen != null) {
        await _opened?.cancel();
        _opened = FirebaseMessaging.onMessageOpenedApp.listen(
          (RemoteMessage m) => onOpen(m.data),
        );
        final RemoteMessage? launch = await messaging.getInitialMessage();
        if (launch != null) onOpen(launch.data);
      }
    } catch (error, stack) {
      // Reminders are a convenience; the app works without them.
      reportError(error, stack, reason: 'Push registration');
    }
  }

  static Future<void> _save(String uid, String token) =>
      _user(uid).set(<String, dynamic>{
        'fcmTokens': FieldValue.arrayUnion(<String>[token]),
      }, SetOptions(merge: true));

  /// On sign-out: this phone stops getting the driver's reminders, so the
  /// next person to sign in here doesn't see them.
  static Future<void> unregister(String uid) async {
    try {
      await _refresh?.cancel();
      await _foreground?.cancel();
      await _opened?.cancel();
      _refresh = null;
      _foreground = null;
      _opened = null;
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _user(uid).update(<String, dynamic>{
          'fcmTokens': FieldValue.arrayRemove(<String>[token]),
        });
      }
    } catch (error, stack) {
      reportError(error, stack, reason: 'Push unregistration');
    }
  }

  static Future<void> savePrefs(String uid, ParkingNotificationPrefs prefs) =>
      _user(uid).set(<String, dynamic>{
        'notificationPrefs': prefs.toMap(),
      }, SetOptions(merge: true));
}
