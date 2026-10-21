import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/driver_reports.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/smartpark_ui.dart';

Stream<QuerySnapshot<Map<String, dynamic>>> _reportsStream() =>
    FirebaseFirestore.instance
        .collection('driver_reports')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

(String, Color, IconData) _statusStyle(String status) => switch (status) {
  kReportWarned => ('Warned', spEntryColor, Icons.verified_rounded),
  kReportDismissed => (
    'Dismissed',
    AppTheme.textMuted,
    Icons.do_not_disturb_on_outlined,
  ),
  _ => ('Open', spInsideColor, Icons.flag_rounded),
};

String _when(Map<String, dynamic> data) {
  final DateTime? at = spParseDateTime(data['createdAt']);
  return at == null
      ? 'Just now'
      : '${spFormatDate(at)}, ${spFormatClockTime(at)}';
}

/// Dashboard card: open driver reports waiting for review, newest first.
class AdminDriverReportsCard extends StatelessWidget {
  const AdminDriverReportsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reportsStream(),
      builder: (BuildContext context, snapshot) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> open =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where((d) => reportStatus(d.data()) == kReportOpen)
                .toList();
        return SpSectionCard(
          icon: Icons.flag_rounded,
          title: 'Driver Reports',
          subtitle: 'Complaints from parking owners about drivers.',
          trailing: open.isEmpty
              ? null
              : SpChip(label: '${open.length} open', color: spInsideColor),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              else if (open.isEmpty)
                const SpEmptyState(
                  boxed: false,
                  icon: Icons.check_circle_outline_rounded,
                  message: 'No reports waiting for review.',
                )
              else
                for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                    in open.take(3))
                  _ReportRow(doc: doc),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminDriverReportsPage(),
                    ),
                  ),
                  child: const Text('View all reports'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Every driver report, filterable by status.
class AdminDriverReportsPage extends StatefulWidget {
  const AdminDriverReportsPage({super.key});

  @override
  State<AdminDriverReportsPage> createState() => _AdminDriverReportsPageState();
}

class _AdminDriverReportsPageState extends State<AdminDriverReportsPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      _reportsStream();
  String _filter = kReportOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Driver Reports'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (BuildContext context, snapshot) {
          final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
              (snapshot.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  .where(
                    (d) =>
                        _filter == 'all' || reportStatus(d.data()) == _filter,
                  )
                  .toList();
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SpSegmentedControl<String>(
                    options: const <(String, String)>[
                      (kReportOpen, 'Open'),
                      (kReportWarned, 'Warned'),
                      (kReportDismissed, 'Dismissed'),
                      ('all', 'All'),
                    ],
                    selected: _filter,
                    onChanged: (String v) => setState(() => _filter = v),
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.hasError)
                    const SpEmptyState(
                      icon: Icons.error_outline_rounded,
                      message: 'Unable to load reports.',
                    )
                  else if (!snapshot.hasData)
                    const Center(child: CircularProgressIndicator())
                  else if (docs.isEmpty)
                    const SpEmptyState(
                      icon: Icons.flag_outlined,
                      message: 'No reports here.',
                    )
                  else
                    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                        in docs)
                      _ReportRow(doc: doc),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> data = doc.data();
    final (String label, Color color, IconData icon) = _statusStyle(
      reportStatus(data),
    );
    final String driver = ((data['driverName'] as String?) ?? '').trim();
    final String facility = ((data['establishmentName'] as String?) ?? '')
        .trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: spCardBorder),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: () => showAdminReportReview(context, doc),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver.isEmpty ? 'Driver' : driver,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                      Text(
                        (data['reason'] as String?) ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        '${facility.isEmpty ? 'Facility' : facility} · ${_when(data)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SpChip(label: label, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Review sheet: the report, the driver's other reports, and the actions
/// (warn the driver, or dismiss) while it's open.
Future<void> showAdminReportReview(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.surface,
    builder: (_) => _ReportReviewSheet(doc: doc),
  );
}

class _ReportReviewSheet extends StatefulWidget {
  const _ReportReviewSheet({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  State<_ReportReviewSheet> createState() => _ReportReviewSheetState();
}

class _ReportReviewSheetState extends State<_ReportReviewSheet> {
  late final Map<String, dynamic> _data = widget.doc.data();
  late final TextEditingController _message = TextEditingController(
    text:
        'SmartPark received a report about your parking at '
        '${((_data['establishmentName'] as String?) ?? '').trim().isEmpty ? 'a facility' : _data['establishmentName']}'
        // "Other" says nothing to the driver; the admin writes the specifics.
        '${_data['reason'] == 'Other' ? '' : ': ${_data['reason']}'}. '
        'Please follow each facility\'s rules and pay '
        'any overtime at the gate. Repeated reports may lead to action on '
        'your account.',
  );
  final TextEditingController _note = TextEditingController();
  late final Future<QuerySnapshot<Map<String, dynamic>>> _history =
      FirebaseFirestore.instance
          .collection('driver_reports')
          .where('driverId', isEqualTo: _data['driverId'])
          .get();
  String? _saving;

  @override
  void dispose() {
    _message.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _act(String action) async {
    final String adminId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (action == kReportWarned && _message.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write the warning the driver will see.')),
      );
      return;
    }
    setState(() => _saving = action);
    try {
      if (action == kReportWarned) {
        await warnDriverForReport(
          adminId: adminId,
          reportId: widget.doc.id,
          report: _data,
          message: _message.text,
          adminNote: _note.text,
        );
      } else {
        await dismissDriverReport(
          adminId: adminId,
          reportId: widget.doc.id,
          adminNote: _note.text,
        );
      }
      if (!mounted) return;
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            action == kReportWarned
                ? 'Warning sent to the driver.'
                : 'Report dismissed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error, fallback: 'Could not save.')),
        ),
      );
    }
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 1),
          Text(value, style: TextStyle(fontSize: 13, color: AppTheme.textDark)),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 12),
    filled: true,
    fillColor: AppTheme.surfaceAlt,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radius),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final String status = reportStatus(_data);
    final bool open = status == kReportOpen;
    final (String label, Color color, IconData _) = _statusStyle(status);
    final String details = ((_data['details'] as String?) ?? '').trim();
    final String adminNote = ((_data['adminNote'] as String?) ?? '').trim();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ((_data['driverName'] as String?) ?? '').trim().isEmpty
                        ? 'Driver'
                        : _data['driverName'] as String,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),
                SpChip(label: label, color: color),
              ],
            ),
            const SizedBox(height: 14),
            _field('Reason', (_data['reason'] as String?) ?? ''),
            if (details.isNotEmpty) _field('Owner\'s details', details),
            _field(
              'Facility',
              ((_data['establishmentName'] as String?) ?? '').trim().isEmpty
                  ? 'Unknown facility'
                  : _data['establishmentName'] as String,
            ),
            _field('Reported', _when(_data)),
            _field('Ticket', (_data['transactionId'] as String?) ?? ''),
            FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: _history,
              builder: (BuildContext context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final List<Map<String, dynamic>> all = snapshot.data!.docs
                    .map((d) => d.data())
                    .toList();
                final int warned = all
                    .where((d) => reportStatus(d) == kReportWarned)
                    .length;
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: all.length > 1
                        ? AppTheme.warningSoft
                        : AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          all.length <= 1
                              ? 'First report about this driver.'
                              : '${all.length} reports about this driver '
                                    '· warned $warned time${warned == 1 ? '' : 's'} before.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (!open) ...[
              if (adminNote.isNotEmpty) _field('Admin note', adminNote),
            ] else ...[
              TextField(
                controller: _message,
                enabled: _saving == null,
                maxLines: 4,
                decoration: _decoration(
                  'Warning the driver will see',
                  'Explain what was reported and what to do differently.',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                enabled: _saving == null,
                maxLines: 2,
                decoration: _decoration(
                  'Note to the owner (optional)',
                  'Shown to the owner who reported, not to the driver.',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving == null
                          ? () => unawaited(_act(kReportDismissed))
                          : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: Text(
                        _saving == kReportDismissed ? 'Saving...' : 'Dismiss',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving == null
                          ? () => unawaited(_act(kReportWarned))
                          : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: AppTheme.warning,
                        foregroundColor: AppTheme.onAccent,
                      ),
                      icon: const Icon(Icons.warning_amber_rounded, size: 18),
                      label: Text(
                        _saving == kReportWarned ? 'Sending...' : 'Warn driver',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
