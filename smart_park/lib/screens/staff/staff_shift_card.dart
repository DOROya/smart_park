import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/error_reporter.dart';
import '../../services/staff_shifts.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/smartpark_ui.dart';

/// Clock in / clock out on the staff dashboard, so the owner's duty log
/// shows who was on duty when. The scanner works either way.
class StaffShiftCard extends StatefulWidget {
  const StaffShiftCard({
    super.key,
    required this.staffId,
    required this.staffName,
    required this.facilityId,
    this.ownerId,
  });

  final String staffId;
  final String staffName;
  final String facilityId;
  final String? ownerId;

  @override
  State<StaffShiftCard> createState() => _StaffShiftCardState();
}

class _StaffShiftCardState extends State<StaffShiftCard> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _open = openShiftsOf(
    widget.staffId,
  ).snapshots();
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String fallback) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error, stack) {
      reportError(error, stack, reason: 'Staff shift');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(error, fallback: fallback))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _open,
      builder: (context, snapshot) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> open =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where((d) => d.data()['establishmentId'] == widget.facilityId)
                .toList();
        final QueryDocumentSnapshot<Map<String, dynamic>>? shift = open.isEmpty
            ? null
            : open.first;
        final DateTime? since = spParseDateTime(shift?.data()['startedAt']);
        final bool onDuty = shift != null;
        return SpSectionCard(
          icon: onDuty ? Icons.badge_rounded : Icons.badge_outlined,
          title: onDuty ? 'On Duty' : 'Off Duty',
          subtitle: onDuty
              ? since == null
                    ? 'Clocking in...'
                    : 'Since ${spFormatClockTime(since)} · ${shiftLength(since, null)}'
              : 'Clock in when your shift starts, so the owner knows who '
                    'was at the gate.',
          trailing: SizedBox(
            height: 40,
            child: onDuty
                ? OutlinedButton(
                    onPressed:
                        _busy ||
                            snapshot.connectionState == ConnectionState.waiting
                        ? null
                        : () => _run(
                            () => clockOut(shift.id),
                            'Could not clock out. Try again.',
                          ),
                    child: Text(_busy ? '...' : 'Clock out'),
                  )
                : FilledButton(
                    onPressed: _busy || !snapshot.hasData
                        ? null
                        : () => _run(
                            () => clockIn(
                              staffId: widget.staffId,
                              staffName: widget.staffName,
                              facilityId: widget.facilityId,
                              ownerId: widget.ownerId,
                            ),
                            'Could not clock in. Try again.',
                          ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.onAccent,
                    ),
                    child: Text(_busy ? '...' : 'Clock in'),
                  ),
          ),
          child: const SizedBox.shrink(),
        );
      },
    );
  }
}
