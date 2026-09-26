import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../theme/app_theme.dart';
import 'smartpark_ui.dart';

/// Bottom sheet for one gate log: who scanned it, when, why, and every other
/// scan of the same ticket, so a disputed entry or exit can be traced to the
/// staff member who handled each step.
///
/// The timeline is loaded here because the entry may be from an earlier day
/// than the list the log was tapped in.
///
/// Pass [onMarkOvertimeCollected] (staff only) to offer confirming the
/// overtime cash on an exit still flagged "collect cash".
Future<void> showSpActivityDetails(
  BuildContext context, {
  required Map<String, dynamic> log,
  Map<String, String>? staffNames,
  Future<void> Function(Map<String, dynamic> log)? onMarkOvertimeCollected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.surface,
    builder: (BuildContext sheetContext) => _ActivityDetailsSheet(
      log: log,
      staffNames: staffNames,
      onMarkOvertimeCollected: onMarkOvertimeCollected,
    ),
  );
}

/// Whether [a] and [b] are the same gate log (the maps carry no doc id).
bool _sameLog(Map<String, dynamic> a, Map<String, dynamic> b) =>
    spParseDateTime(a['timestamp']) == spParseDateTime(b['timestamp']) &&
    a['scanType'] == b['scanType'] &&
    a['staffId'] == b['staffId'] &&
    a['decision'] == b['decision'];

class _ActivityDetailsSheet extends StatefulWidget {
  const _ActivityDetailsSheet({
    required this.log,
    required this.staffNames,
    this.onMarkOvertimeCollected,
  });

  final Map<String, dynamic> log;
  final Map<String, String>? staffNames;
  final Future<void> Function(Map<String, dynamic> log)?
  onMarkOvertimeCollected;

  @override
  State<_ActivityDetailsSheet> createState() => _ActivityDetailsSheetState();
}

class _ActivityDetailsSheetState extends State<_ActivityDetailsSheet> {
  late final Future<List<Map<String, dynamic>>> _timeline = _loadTimeline();
  bool _marking = false;

  /// Set once this sheet marked the cash collected (the log map is a
  /// snapshot and does not update).
  bool _markedCollected = false;

  Map<String, dynamic> get log => widget.log;
  Map<String, String>? get staffNames => widget.staffNames;

  Future<List<Map<String, dynamic>>> _loadTimeline() async {
    final String transactionId = ((log['transactionId'] as String?) ?? '')
        .trim();
    final String facilityId = ((log['establishmentID'] as String?) ?? '')
        .trim();
    if (transactionId.isEmpty || facilityId.isEmpty) {
      return <Map<String, dynamic>>[log];
    }
    // Security rules only allow reading logs filtered to one facility.
    final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
        .instance
        .collection('activity_logs')
        .where('establishmentID', isEqualTo: facilityId)
        .where('transactionId', isEqualTo: transactionId)
        .get();
    final DateTime now = DateTime.now();
    return snap.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.data())
        .toList()
      ..sort(
        (Map<String, dynamic> a, Map<String, dynamic> b) =>
            (spParseDateTime(a['timestamp']) ?? now).compareTo(
              spParseDateTime(b['timestamp']) ?? now,
            ),
      );
  }

  String _when(Map<String, dynamic> data) {
    final DateTime? time = spParseDateTime(data['timestamp']);
    return time == null
        ? 'Just now'
        : '${spFormatDate(time)}, ${spFormatClockTime(time)}';
  }

  String _staffLabel(Map<String, dynamic> data) {
    final String name = spLogStaffName(data, staffNames) ?? 'Unknown staff';
    final String staffId = ((data['staffId'] as String?) ?? '').trim();
    final bool removed =
        staffNames != null &&
        staffId.isNotEmpty &&
        !staffNames!.containsKey(staffId);
    return removed ? '$name (removed)' : name;
  }

  @override
  Widget build(BuildContext context) {
    final String transactionId = ((log['transactionId'] as String?) ?? '')
        .trim();
    final bool allowed = spIsAllowedLog(log);
    final bool isExit = spLogScanType(log) == 'exit';
    final String reason = ((log['decisionReason'] as String?) ?? '').trim();
    final bool walkIn = log['source'] == 'walk_in';

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: <Widget>[
            Row(
              children: <Widget>[
                SpPlateBadge(plate: (log['vehiclePlate'] as String?) ?? ''),
                const SizedBox(width: 8),
                if (walkIn) ...<Widget>[
                  SpChip(label: 'Walk-in', color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                SpChip(
                  label: allowed ? 'Allowed' : 'Denied',
                  color: allowed ? spEntryColor : spDeniedColor,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _row(
              Icons.badge_outlined,
              walkIn ? 'Logged by' : 'Scanned by',
              _staffLabel(log),
              emphasize: true,
            ),
            _row(
              isExit ? Icons.logout_rounded : Icons.login_rounded,
              isExit ? 'Exit scan' : 'Entry scan',
              _when(log),
            ),
            if (reason.isNotEmpty)
              _row(Icons.info_outline_rounded, 'Result', reason),
            if (((log['overtimeHours'] as num?) ?? 0) > 0) _overtimeRow(),
            if (transactionId.isNotEmpty) _ticketRow(context, transactionId),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _timeline,
              builder: (context, snapshot) {
                final List<Map<String, dynamic>> timeline =
                    snapshot.data ?? <Map<String, dynamic>>[];
                if (snapshot.hasError) {
                  return Text(
                    'Could not load the ticket timeline.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                if (timeline.length <= 1) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: 8),
                    const SpSectionLabel('Ticket timeline'),
                    const SizedBox(height: 8),
                    for (final Map<String, dynamic> step in timeline)
                      _timelineStep(step, isCurrent: _sameLog(step, log)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    IconData icon,
    String label,
    String value, {
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: emphasize ? 15 : 13,
                    fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overtimeRow() {
    final int hours = ((log['overtimeHours'] as num?) ?? 0).toInt();
    final double amount = ((log['overtimeAmount'] as num?) ?? 0).toDouble();
    final String status = ((log['overtimeStatus'] as String?) ?? '')
        .toLowerCase();
    final bool collected = _markedCollected || status == 'collected';
    final bool due = !collected && status == 'cash_due';
    final String collectorId = ((log['overtimeCollectedBy'] as String?) ?? '')
        .trim();
    final DateTime? collectedAt = spParseDateTime(log['overtimeCollectedAt']);
    String? collector = staffNames?[collectorId];
    if ((collector ?? '').isEmpty && collectorId == log['staffId']) {
      collector = _staffLabel(log);
    }
    final String value = amount <= 0
        ? '${hours}h · no rate set, nothing billed'
        : collected
        ? 'PHP ${amount.toStringAsFixed(2)} for ${hours}h · collected'
              '${(collector ?? '').isEmpty ? '' : ' by $collector'}'
              '${collectedAt == null ? '' : ', ${spFormatClockTime(collectedAt)}'}'
        : 'PHP ${amount.toStringAsFixed(2)} for ${hours}h · not yet confirmed '
              'collected';
    final Future<void> Function(Map<String, dynamic> log)? onMark =
        widget.onMarkOvertimeCollected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _row(Icons.payments_outlined, 'Overtime cash', value),
        if (due && onMark != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: _marking
                  ? null
                  : () async {
                      setState(() => _marking = true);
                      try {
                        await onMark(log);
                        if (mounted) setState(() => _markedCollected = true);
                      } finally {
                        if (mounted) setState(() => _marking = false);
                      }
                    },
              icon: const Icon(Icons.check_rounded),
              label: Text(
                _marking
                    ? 'Saving...'
                    : 'Cash collected (PHP ${amount.toStringAsFixed(2)})',
              ),
            ),
          ),
      ],
    );
  }

  Widget _ticketRow(BuildContext context, String transactionId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.confirmation_number_outlined,
            size: 16,
            color: AppTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              transactionId,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy ticket ID',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: transactionId));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ticket ID copied.')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _timelineStep(Map<String, dynamic> step, {required bool isCurrent}) {
    final bool allowed = spIsAllowedLog(step);
    final bool isExit = spLogScanType(step) == 'exit';
    final Color color = !allowed
        ? spDeniedColor
        : isExit
        ? spExitColor
        : spEntryColor;
    final String title =
        '${isExit ? 'Exit' : 'Entry'}${allowed ? '' : ' denied'}';
    final DateTime? time = spParseDateTime(step['timestamp']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isCurrent ? AppTheme.surfaceAlt : AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: isCurrent ? color : spCardBorder),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            !allowed
                ? Icons.block_rounded
                : isExit
                ? Icons.logout_rounded
                : Icons.login_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$title · ${time == null ? 'just now' : '${spFormatDate(time)}, ${spFormatClockTime(time)}'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  _staffLabel(step),
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
