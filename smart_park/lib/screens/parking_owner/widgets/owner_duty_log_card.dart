import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/error_reporter.dart';
import '../../../services/staff_shifts.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../widgets/smartpark_ui.dart';

/// Who is on duty now, and the duty log for a day: each staff member's
/// clock-in and clock-out. The owner can end a shift someone forgot.
class OwnerDutyLogCard extends StatefulWidget {
  const OwnerDutyLogCard({super.key, required this.facilityId});

  final String facilityId;

  @override
  State<OwnerDutyLogCard> createState() => _OwnerDutyLogCardState();
}

class _OwnerDutyLogCardState extends State<OwnerDutyLogCard> {
  DateTime _day = DateTime.now();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _dayShifts = _query();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _onDuty = onDutyAt(
    widget.facilityId,
  ).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> _query() =>
      shiftsOnDay(widget.facilityId, _day).snapshots();

  bool get _isToday {
    final DateTime now = DateTime.now();
    return _day.year == now.year &&
        _day.month == now.month &&
        _day.day == now.day;
  }

  Future<void> _pickDay() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _day = picked;
      _dayShifts = _query();
    });
  }

  Future<void> _endShift(String shiftId, String name) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('End $name\'s shift?'),
        content: const Text(
          'Use this when someone forgot to clock out. The shift ends now and '
          'is marked as ended by you.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End shift'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await clockOut(shiftId, endedBy: FirebaseAuth.instance.currentUser?.uid);
    } catch (error, stack) {
      reportError(error, stack, reason: 'Owner ends shift');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(error, fallback: 'Could not end the shift.'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SpSectionCard(
      icon: Icons.schedule_rounded,
      title: 'Duty Log',
      subtitle: 'When each staff member clocked in and out.',
      trailing: TextButton.icon(
        onPressed: _pickDay,
        icon: const Icon(Icons.calendar_today_rounded, size: 16),
        label: Text(_isToday ? 'Today' : spFormatDate(_day)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _onDuty,
            builder: (context, snapshot) {
              final List<QueryDocumentSnapshot<Map<String, dynamic>>> open =
                  snapshot.data?.docs ??
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              return Text(
                open.isEmpty
                    ? 'Nobody is clocked in right now.'
                    : 'On duty now: ${open.map((d) => _nameOf(d.data())).join(', ')}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: open.isEmpty
                      ? AppTheme.textSecondary
                      : AppTheme.success,
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _dayShifts,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'Unable to load the duty log.',
                  style: TextStyle(color: AppTheme.textMuted),
                );
              }
              final List<QueryDocumentSnapshot<Map<String, dynamic>>> shifts =
                  snapshot.data?.docs ??
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (shifts.isEmpty) {
                return Text(
                  'No shifts ${_isToday ? 'today' : 'on this day'}.',
                  style: TextStyle(color: AppTheme.textMuted),
                );
              }
              return Column(
                children: <Widget>[
                  for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                      in shifts)
                    _shiftRow(d),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _nameOf(Map<String, dynamic> shift) {
    final String name = ((shift['staffName'] as String?) ?? '').trim();
    return name.isEmpty ? 'Staff member' : name;
  }

  Widget _shiftRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> s = doc.data();
    final DateTime? start = spParseDateTime(s['startedAt']);
    final DateTime? end = spParseDateTime(s['endedAt']);
    final bool open = s['endedAt'] == null;
    // Ended for them: by the owner, or else by a supervisor.
    final String endedBy = (s['endedBy'] as String?) ?? '';
    final String endedNote = endedBy.isEmpty
        ? ''
        : endedBy == s['ownerId']
        ? ' · ended by owner'
        : ' · ended by supervisor';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(
            open ? Icons.circle : Icons.check_circle_outline_rounded,
            size: 14,
            color: open ? AppTheme.success : AppTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _nameOf(s),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  start == null
                      ? 'Clocking in...'
                      : '${spFormatClockTime(start)} – '
                            '${open
                                ? 'now'
                                : end == null
                                ? '…'
                                : spFormatClockTime(end)}'
                            ' · ${shiftLength(start, end)}'
                            '$endedNote',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          if (open)
            TextButton(
              onPressed: () => _endShift(doc.id, _nameOf(s)),
              style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              child: const Text('End shift'),
            ),
        ],
      ),
    );
  }
}
