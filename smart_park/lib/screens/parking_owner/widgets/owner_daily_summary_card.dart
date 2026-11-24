import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../services/operating_hours.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/smartpark_ui.dart';

/// Hour the end-of-day summary is sent by default (9:00 PM); matches
/// DEFAULT_HOUR in functions/src/owner_summary.js.
const int kDefaultDailySummaryHour = 21;

/// The owner's choice: on or off, and the hour (Philippine time).
({bool enabled, int hour}) dailySummaryPrefsOf(Map<String, dynamic>? user) {
  final Object? prefs = user?['notificationPrefs'];
  final Object? daily = prefs is Map ? prefs['dailySummary'] : null;
  final Map<Object?, Object?> d = daily is Map
      ? daily
      : const <Object?, Object?>{};
  final Object? hour = d['hour'];
  return (
    enabled: d['enabled'] != false,
    hour: hour is int && hour >= 0 && hour <= 23
        ? hour
        : kDefaultDailySummaryHour,
  );
}

/// Profile › Notifications › Daily summary: one push a day with the day's
/// gate activity, sales and cash, at the hour the owner picks.
class OwnerDailySummaryCard extends StatelessWidget {
  const OwnerDailySummaryCard({super.key, required this.ownerId});

  final String ownerId;

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('users').doc(ownerId);

  Future<void> _save(bool enabled, int hour) => _ref.set(<String, dynamic>{
    'notificationPrefs': <String, dynamic>{
      'dailySummary': <String, dynamic>{'enabled': enabled, 'hour': hour},
    },
  }, SetOptions(merge: true));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ref.snapshots(),
      builder: (BuildContext context, snapshot) {
        final ({bool enabled, int hour}) prefs = dailySummaryPrefsOf(
          snapshot.data?.data(),
        );
        return SpSectionCard(
          icon: Icons.summarize_outlined,
          title: 'Daily Summary',
          subtitle:
              'One notification a day: entries and exits, sales, gate cash '
              'not handed over, and staff still on duty. Not sent on a day '
              'with no activity.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.accent,
                title: const Text(
                  'Send me a daily summary',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                value: prefs.enabled,
                onChanged: (bool v) => _save(v, prefs.hour),
              ),
              if (prefs.enabled)
                OutlinedButton.icon(
                  onPressed: () async {
                    final TimeOfDay? picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: prefs.hour, minute: 0),
                      helpText: 'Hour to send it (minutes are ignored)',
                    );
                    if (picked != null) await _save(true, picked.hour);
                  },
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(
                    'At ${OperatingHours.format12h(prefs.hour * 60)}',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
