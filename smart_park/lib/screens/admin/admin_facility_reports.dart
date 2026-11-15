import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/driver_reports.dart';
import '../../services/facility_reports.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/smartpark_ui.dart';

String _when(Object? timestamp) {
  final DateTime? at = spParseDateTime(timestamp);
  return at == null
      ? 'Just now'
      : '${spFormatDate(at)}, ${spFormatClockTime(at)}';
}

Future<void> _run(
  BuildContext context,
  Future<void> Function() action,
  String done,
) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(friendlyError(error, fallback: 'Could not save.')),
      ),
    );
  }
}

/// Asks for an optional note; null when cancelled.
Future<String?> _askNote(
  BuildContext context, {
  required String title,
  required String label,
  required String confirm,
}) async {
  final TextEditingController controller = TextEditingController();
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLength: 300,
        maxLines: 3,
        decoration: InputDecoration(labelText: label),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  final String note = controller.text.trim();
  controller.dispose();
  return ok == true ? note : null;
}

Widget _box({required Widget child}) => Container(
  width: double.infinity,
  margin: const EdgeInsets.only(bottom: 8),
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: AppTheme.surface,
    borderRadius: BorderRadius.circular(AppTheme.radius),
    border: Border.all(color: spCardBorder),
  ),
  child: child,
);

Widget _line(String text, {bool strong = false, bool muted = false}) => Text(
  text,
  style: TextStyle(
    fontSize: strong ? 13.5 : 12.5,
    height: 1.4,
    fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
    color: muted ? AppTheme.textMuted : AppTheme.textDark,
  ),
);

/// Dashboard card: drivers' reports about facilities waiting for review.
/// Resolving one records that the admin acted on it (for example by
/// suspending the facility from its own page); dismissing closes it.
class AdminFacilityReportsCard extends StatefulWidget {
  const AdminFacilityReportsCard({super.key});

  @override
  State<AdminFacilityReportsCard> createState() =>
      _AdminFacilityReportsCardState();
}

class _AdminFacilityReportsCardState extends State<AdminFacilityReportsCard> {
  final Stream<QuerySnapshot<Map<String, dynamic>>> _reports = FirebaseFirestore
      .instance
      .collection('facility_reports')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots();
  bool _showClosed = false;

  Future<void> _close(String id, {required bool resolved}) async {
    final String? note = await _askNote(
      context,
      title: resolved ? 'Mark as resolved?' : 'Dismiss this report?',
      label: 'Note for the record (optional)',
      confirm: resolved ? 'Resolved' : 'Dismiss',
    );
    if (note == null || !mounted) return;
    await _run(
      context,
      () => closeFacilityReport(
        adminId: FirebaseAuth.instance.currentUser?.uid ?? '',
        reportId: id,
        resolved: resolved,
        adminNote: note,
      ),
      resolved ? 'Report marked resolved.' : 'Report dismissed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reports,
      builder: (BuildContext context, snapshot) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> all =
            snapshot.data?.docs ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> open = all
            .where((d) => facilityReportStatus(d.data()) == kFacilityReportOpen)
            .toList();
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> shown =
            _showClosed ? all : open;
        // How often each facility has been reported, to spot repeats.
        final Map<String, int> perFacility = <String, int>{};
        for (final QueryDocumentSnapshot<Map<String, dynamic>> d in all) {
          final String id = (d.data()['establishmentId'] as String?) ?? '';
          perFacility[id] = (perFacility[id] ?? 0) + 1;
        }
        return SpSectionCard(
          icon: Icons.storefront_outlined,
          title: 'Facility Reports',
          subtitle: 'Complaints from drivers about parking facilities.',
          trailing: open.isEmpty
              ? null
              : SpChip(label: '${open.length} open', color: spInsideColor),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (snapshot.hasError)
                const SpEmptyState(
                  boxed: false,
                  icon: Icons.error_outline_rounded,
                  message: 'Unable to load reports.',
                )
              else if (!snapshot.hasData)
                const SizedBox(
                  height: 24,
                  child: Center(child: LinearProgressIndicator()),
                )
              else if (shown.isEmpty)
                const SpEmptyState(
                  boxed: false,
                  icon: Icons.check_circle_outline_rounded,
                  message: 'No reports waiting for review.',
                )
              else
                for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                    in shown)
                  _report(doc, perFacility),
              if (all.length > open.length)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _showClosed = !_showClosed),
                    child: Text(
                      _showClosed ? 'Show open only' : 'Show closed reports',
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _report(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, int> perFacility,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String status = facilityReportStatus(data);
    final bool open = status == kFacilityReportOpen;
    final String facility = ((data['establishmentName'] as String?) ?? '')
        .trim();
    final String driver = ((data['driverName'] as String?) ?? '').trim();
    final String details = ((data['details'] as String?) ?? '').trim();
    final String note = ((data['adminNote'] as String?) ?? '').trim();
    final int count = perFacility[data['establishmentId']] ?? 1;
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _line(
                  facility.isEmpty ? 'Facility' : facility,
                  strong: true,
                ),
              ),
              SpChip(
                label: open
                    ? 'Open'
                    : status == kFacilityReportResolved
                    ? 'Resolved'
                    : 'Dismissed',
                color: open
                    ? spInsideColor
                    : status == kFacilityReportResolved
                    ? spEntryColor
                    : AppTheme.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 4),
          _line(reportReasons(data).join(', ')),
          if (details.isNotEmpty) _line(details),
          _line(
            '${driver.isEmpty ? 'Driver' : driver} · '
            '${_when(data['createdAt'])}'
            '${count > 1 ? ' · $count reports about this facility' : ''}',
            muted: true,
          ),
          if (note.isNotEmpty) _line('Note: $note', muted: true),
          if (open) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => _close(doc.id, resolved: false),
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: () => _close(doc.id, resolved: true),
                  child: const Text('Mark resolved'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Dashboard card: warnings a driver has contested. Withdrawing deletes the
/// warning; keeping it records why, which the driver sees. Hidden while
/// there is nothing to decide.
class AdminWarningContestsCard extends StatefulWidget {
  const AdminWarningContestsCard({super.key});

  @override
  State<AdminWarningContestsCard> createState() =>
      _AdminWarningContestsCardState();
}

class _AdminWarningContestsCardState extends State<AdminWarningContestsCard> {
  final Stream<QuerySnapshot<Map<String, dynamic>>> _contested =
      FirebaseFirestore.instance
          .collection('driver_warnings')
          .where('contestedAt', isGreaterThan: Timestamp(0, 0))
          .snapshots();

  Future<void> _withdraw(String id) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Withdraw this warning?'),
        content: const Text(
          'The warning is removed from the driver\'s account for good.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(context, () => withdrawDriverWarning(id), 'Warning withdrawn.');
  }

  Future<void> _keep(String id) async {
    final String? note = await _askNote(
      context,
      title: 'Keep this warning?',
      label: 'Reason shown to the driver (optional)',
      confirm: 'Keep warning',
    );
    if (note == null || !mounted) return;
    await _run(
      context,
      () => rejectWarningContest(
        adminId: FirebaseAuth.instance.currentUser?.uid ?? '',
        warningId: id,
        note: note,
      ),
      'Warning kept. The driver can see your reason.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _contested,
      builder: (BuildContext context, snapshot) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> open =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where((d) => warningContestStatus(d.data()) == 'open')
                .toList();
        if (open.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: SpSectionCard(
            icon: Icons.gavel_rounded,
            title: 'Contested Warnings',
            subtitle: 'Drivers who say a warning they received is wrong.',
            trailing: SpChip(
              label: '${open.length} to review',
              color: spInsideColor,
            ),
            child: Column(
              children: <Widget>[
                for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                    in open)
                  _contest(doc),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _contest(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data();
    final String facility = ((data['establishmentName'] as String?) ?? '')
        .trim();
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _line(
            reportReasons(data).isEmpty
                ? 'Warning'
                : reportReasons(data).join(', '),
            strong: true,
          ),
          _line(
            'Warning: ${((data['message'] as String?) ?? '').trim()}',
            muted: true,
          ),
          const SizedBox(height: 4),
          _line(
            'Driver says: ${((data['contestMessage'] as String?) ?? '').trim()}',
          ),
          _line(
            '${facility.isEmpty ? 'Facility' : facility} · contested '
            '${_when(data['contestedAt'])}',
            muted: true,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => _keep(doc.id),
                child: const Text('Keep warning'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: () => _withdraw(doc.id),
                child: const Text('Withdraw warning'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
