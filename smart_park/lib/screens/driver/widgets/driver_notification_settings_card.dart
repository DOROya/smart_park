import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../services/parking_push.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/smartpark_ui.dart';

/// Profile card where a driver chooses their parking reminders: a heads-up
/// before paid time runs out (15, 30 or 60 minutes ahead) and an alert when
/// overtime starts.
class DriverNotificationSettingsCard extends StatelessWidget {
  const DriverNotificationSettingsCard({super.key, required this.driverId});

  final String driverId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(driverId)
          .snapshots(),
      builder: (BuildContext context, snapshot) {
        final ParkingNotificationPrefs prefs =
            ParkingNotificationPrefs.fromUser(snapshot.data?.data());
        void save(ParkingNotificationPrefs next) =>
            ParkingPush.savePrefs(driverId, next);

        return SpSectionCard(
          icon: Icons.notifications_active_outlined,
          title: 'Parking Reminders',
          subtitle:
              'Notifications while you are parked. Paid time only counts '
              'down while you are inside.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.accent,
                title: const Text(
                  'Before my paid time runs out',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                value: prefs.parkingReminders,
                onChanged: (bool v) => save(
                  ParkingNotificationPrefs(
                    parkingReminders: v,
                    leadMinutes: prefs.leadMinutes,
                    overtimeAlerts: prefs.overtimeAlerts,
                  ),
                ),
              ),
              if (prefs.parkingReminders) ...<Widget>[
                Text(
                  'Remind me',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 6),
                SpSegmentedControl<int>(
                  options: <(int, String)>[
                    for (final int m in kReminderLeadChoices)
                      (m, m == 60 ? '1 hour before' : '$m min before'),
                  ],
                  selected: prefs.leadMinutes,
                  onChanged: (int m) => save(
                    ParkingNotificationPrefs(
                      parkingReminders: true,
                      leadMinutes: m,
                      overtimeAlerts: prefs.overtimeAlerts,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.accent,
                title: const Text(
                  'When overtime starts',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'After the facility\'s grace period.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                value: prefs.overtimeAlerts,
                onChanged: (bool v) => save(
                  ParkingNotificationPrefs(
                    parkingReminders: prefs.parkingReminders,
                    leadMinutes: prefs.leadMinutes,
                    overtimeAlerts: v,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
