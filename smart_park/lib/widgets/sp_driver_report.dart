import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/driver_reports.dart';
import '../services/staff_incidents.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'smartpark_ui.dart';
import 'sp_reason_dropdowns.dart';

/// Owner's "Report driver" control for one ticket. Once the owner has
/// reported it, shows where the report stands instead.
class SpDriverReportButton extends StatelessWidget {
  const SpDriverReportButton({
    super.key,
    required this.ticketId,
    required this.ticket,
  });

  final String ticketId;

  /// The `transactions` doc: driver, facility and its name.
  final Map<String, dynamic> ticket;

  @override
  Widget build(BuildContext context) {
    final String ownerId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final String driverId = ((ticket['driverId'] as String?) ?? '').trim();
    if (ownerId.isEmpty || driverId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('driver_reports')
          .where('reporterId', isEqualTo: ownerId)
          .where('transactionId', isEqualTo: ticketId)
          .snapshots(),
      builder: (BuildContext context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> reports =
            snapshot.data!.docs;
        if (reports.isNotEmpty) {
          return _ReportStatusStrip(report: reports.first.data());
        }
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => showReportDriverDialog(
              context,
              ownerId: ownerId,
              ticketId: ticketId,
              ticket: ticket,
            ),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text(
              'Report driver to SmartPark',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: AppTheme.danger,
              side: BorderSide(color: AppTheme.dangerBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radius),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One-line report status for compact cards (e.g. Recent Transactions):
/// where the owner's report on this ticket stands.
class SpDriverReportChip extends StatelessWidget {
  const SpDriverReportChip({super.key, required this.report});

  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color, IconData icon) = switch (reportStatus(
      report,
    )) {
      kReportWarned => (
        'Reported · driver warned',
        spEntryColor,
        Icons.verified_rounded,
      ),
      kReportDismissed => (
        'Reported · closed, no action',
        AppTheme.textMuted,
        Icons.do_not_disturb_on_outlined,
      ),
      _ => ('Reported · under review', spInsideColor, Icons.flag_rounded),
    };
    final String note = ((report['adminNote'] as String?) ?? '').trim();
    return Tooltip(
      message: note.isEmpty
          ? (report['reason'] as String?) ?? ''
          : 'Admin note: $note',
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportStatusStrip extends StatelessWidget {
  const _ReportStatusStrip({required this.report});

  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final (
      String title,
      String body,
      Color color,
      IconData icon,
    ) = switch (reportStatus(report)) {
      kReportWarned => (
        'Driver warned',
        'SmartPark reviewed your report and warned the driver.',
        spEntryColor,
        Icons.verified_rounded,
      ),
      kReportDismissed => (
        'Report closed',
        'SmartPark reviewed your report and took no action.',
        AppTheme.textMuted,
        Icons.do_not_disturb_on_outlined,
      ),
      _ => (
        'Reported · under review',
        'SmartPark will review: ${(report['reason'] as String?) ?? ''}.',
        spInsideColor,
        Icons.flag_rounded,
      ),
    };
    final String note = ((report['adminNote'] as String?) ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: spCardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  note.isEmpty ? body : '$body Admin note: $note',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks the owner why they're reporting the driver of [ticket] (one or more
/// reasons, [initialReasons] picked to start), then files the report.
/// Returns whether one was sent.
Future<bool> showReportDriverDialog(
  BuildContext context, {
  required String ownerId,
  required String ticketId,
  required Map<String, dynamic> ticket,
  List<String> initialReasons = const <String>[],
  String initialDetails = '',
}) async {
  final bool? sent = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => _ReportDriverDialog(
      ticket: ticket,
      initialReasons: initialReasons,
      initialDetails: initialDetails,
      submit: (List<String> reasons, String details) => submitDriverReport(
        ownerId: ownerId,
        establishmentId: ((ticket['establishmentId'] as String?) ?? '').trim(),
        establishmentName: ((ticket['establishmentName'] as String?) ?? '')
            .trim(),
        transactionId: ticketId,
        driverId: ((ticket['driverId'] as String?) ?? '').trim(),
        driverName: ((ticket['driverName'] as String?) ?? '').trim(),
        reasons: reasons,
        details: details,
      ),
    ),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report sent to the SmartPark admin.')),
    );
  }
  return sent ?? false;
}

/// Staff flag a ticket's driver for their owner to look at, optionally with
/// [initialReasons] picked. Returns whether a flag was sent.
Future<bool> showFlagIncidentDialog(
  BuildContext context, {
  required String ticketId,
  required Map<String, dynamic> ticket,
  required String staffName,
  List<String> initialReasons = const <String>[],
}) async {
  final String staffId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final bool? sent = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => _ReportDriverDialog(
      ticket: ticket,
      initialReasons: initialReasons,
      title: 'Flag incident',
      intro:
          'Your parking owner sees this flag and decides whether to report '
          'the driver to SmartPark.',
      sendLabel: 'Flag for owner',
      submit: (List<String> reasons, String details) => flagIncident(
        staffId: staffId,
        staffName: staffName,
        transactionId: ticketId,
        ticket: ticket,
        reasons: reasons,
        details: details,
      ),
    ),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Incident flagged for your owner.')),
    );
  }
  return sent ?? false;
}

/// Staff's "Flag incident" control for one ticket; once flagged, shows
/// what the owner did with it instead.
class SpIncidentFlagButton extends StatelessWidget {
  const SpIncidentFlagButton({
    super.key,
    required this.ticketId,
    required this.ticket,
    required this.staffName,
  });

  final String ticketId;
  final Map<String, dynamic> ticket;
  final String staffName;

  @override
  Widget build(BuildContext context) {
    final String staffId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final String driverId = ((ticket['driverId'] as String?) ?? '').trim();
    if (staffId.isEmpty || driverId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('staff_incidents')
          .where('staffId', isEqualTo: staffId)
          .where('transactionId', isEqualTo: ticketId)
          .snapshots(),
      builder: (BuildContext context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> flags =
            snapshot.data!.docs;
        if (flags.isNotEmpty) {
          final (
            String label,
            Color color,
            IconData icon,
          ) = switch (incidentStatus(flags.first.data())) {
            kIncidentReported => (
              'Flagged · owner reported it to SmartPark',
              spEntryColor,
              Icons.verified_rounded,
            ),
            kIncidentDismissed => (
              'Flagged · owner closed it',
              AppTheme.textMuted,
              Icons.do_not_disturb_on_outlined,
            ),
            _ => (
              'Flagged · waiting for your owner',
              spInsideColor,
              Icons.outlined_flag_rounded,
            ),
          };
          return Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          );
        }
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => showFlagIncidentDialog(
              context,
              ticketId: ticketId,
              ticket: ticket,
              staffName: staffName,
            ),
            icon: const Icon(Icons.outlined_flag_rounded, size: 18),
            label: const Text(
              'Flag incident for owner',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: spInsideColor,
              side: BorderSide(color: AppTheme.accent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radius),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The reasons-and-details form shared by owners reporting a driver to
/// SmartPark and staff flagging one for their owner. One reason is picked
/// per dropdown; "Add Another Reason" adds more.
class _ReportDriverDialog extends StatefulWidget {
  const _ReportDriverDialog({
    required this.ticket,
    required this.submit,
    this.title = 'Report driver',
    this.intro =
        'The SmartPark admin reviews every report and may warn the driver. '
        'The driver is not told who reported them.',
    this.sendLabel = 'Send report',
    this.initialReasons = const <String>[],
    this.initialDetails = '',
  });

  final Map<String, dynamic> ticket;
  final Future<void> Function(List<String> reasons, String details) submit;
  final String title;
  final String intro;
  final String sendLabel;
  final List<String> initialReasons;
  final String initialDetails;

  @override
  State<_ReportDriverDialog> createState() => _ReportDriverDialogState();
}

class _ReportDriverDialogState extends State<_ReportDriverDialog> {
  late final TextEditingController _details = TextEditingController(
    text: widget.initialDetails,
  );
  // Reasons no longer on the list (renamed since) aren't pre-picked.
  late List<String?> _reasons = <String?>[
    for (final String reason in widget.initialReasons)
      if (kDriverReportReasons.contains(reason)) reason,
  ];
  bool _missing = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final List<String> reasons = spPickedReasons(_reasons);
    if (reasons.isEmpty ||
        (reasons.contains('Other') && _details.text.trim().isEmpty)) {
      setState(() => _missing = true);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.submit(reasons, _details.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = friendlyError(error, fallback: 'Could not send it.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String driverName = ((widget.ticket['driverName'] as String?) ?? '')
        .trim();
    final String plate = ((widget.ticket['vehiclePlate'] as String?) ?? '')
        .trim();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_rounded, color: AppTheme.textDark),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        driverName.isEmpty ? 'Driver' : driverName,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                    if (plate.isNotEmpty) SpPlateBadge(plate: plate),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.intro,
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 14),
              Text.rich(
                TextSpan(
                  text: 'What happened? ',
                  children: [
                    TextSpan(
                      text: '*',
                      style: TextStyle(color: AppTheme.danger),
                    ),
                  ],
                ),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              SpReasonDropdowns(
                options: kDriverReportReasons,
                values: _reasons,
                missing: _missing,
                enabled: !_sending,
                onChanged: (List<String?> reasons) => setState(() {
                  _reasons = reasons;
                  _missing = false;
                }),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _details,
                enabled: !_sending,
                maxLines: 3,
                onChanged: (_) {
                  if (_missing) setState(() => _missing = false);
                },
                decoration: InputDecoration(
                  labelText: _reasons.contains('Other')
                      ? 'Details (required for "Other")'
                      : 'Details (optional)',
                  hintText: 'When it happened, what was said, any damage...',
                  hintStyle: const TextStyle(fontSize: 12),
                  filled: true,
                  fillColor: AppTheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                ),
              ),
              if (_missing || _error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error ??
                      (_reasons.contains('Other')
                          ? 'Describe what happened in the details box.'
                          : 'Pick what happened first.'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.danger,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.flag_rounded, size: 18),
          label: Text(_sending ? 'Sending...' : widget.sendLabel),
        ),
      ],
    );
  }
}

/// Owner's queue of incidents their gate staff flagged and the owner hasn't
/// acted on yet. Each can be reported to SmartPark (the report form opens
/// pre-filled from the flag) or dismissed. Hidden when nothing is open.
class SpStaffFlagsCard extends StatefulWidget {
  const SpStaffFlagsCard({super.key, required this.facilityId});

  final String facilityId;

  @override
  State<SpStaffFlagsCard> createState() => _SpStaffFlagsCardState();
}

class _SpStaffFlagsCardState extends State<SpStaffFlagsCard> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _flags = _query();
  final Set<String> _busy = <String>{};

  Stream<QuerySnapshot<Map<String, dynamic>>> _query() => FirebaseFirestore
      .instance
      .collection('staff_incidents')
      .where('establishmentId', isEqualTo: widget.facilityId)
      .snapshots();

  @override
  void didUpdateWidget(SpStaffFlagsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.facilityId != widget.facilityId) _flags = _query();
  }

  Future<void> _resolve(String id, Future<bool> Function() action) async {
    setState(() => _busy.add(id));
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(error, fallback: 'Could not save.')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<bool> _report(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final Map<String, dynamic> flag = doc.data();
    final String staff = ((flag['staffName'] as String?) ?? '').trim();
    final String details = ((flag['details'] as String?) ?? '').trim();
    final bool sent = await showReportDriverDialog(
      context,
      ownerId: FirebaseAuth.instance.currentUser?.uid ?? '',
      ticketId: (flag['transactionId'] as String?) ?? '',
      ticket: incidentAsTicket(flag),
      initialReasons: reportReasons(flag),
      initialDetails: [
        if (details.isNotEmpty) details,
        'Flagged by ${staff.isEmpty ? 'gate staff' : staff}.',
      ].join(' '),
    );
    if (sent) await resolveIncident(doc.id, kIncidentReported);
    return sent;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _flags,
      builder: (BuildContext context, snapshot) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> open =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where((d) => incidentStatus(d.data()) == kIncidentOpen)
                .toList()
              ..sort(
                (a, b) =>
                    (spParseDateTime(b.data()['createdAt']) ?? DateTime.now())
                        .compareTo(
                          spParseDateTime(a.data()['createdAt']) ??
                              DateTime.now(),
                        ),
              );
        if (open.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SpSectionCard(
            icon: Icons.outlined_flag_rounded,
            title: 'Staff Flags',
            subtitle: 'Incidents your gate staff flagged for you to review.',
            trailing: SpChip(
              label: '${open.length} open',
              color: spInsideColor,
            ),
            child: Column(
              children: [
                for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                    in open)
                  _flagRow(doc),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _flagRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> flag = doc.data();
    final String driver = ((flag['driverName'] as String?) ?? '').trim();
    final String plate = ((flag['vehiclePlate'] as String?) ?? '').trim();
    final String staff = ((flag['staffName'] as String?) ?? '').trim();
    final String details = ((flag['details'] as String?) ?? '').trim();
    final DateTime? at = spParseDateTime(flag['createdAt']);
    final bool busy = _busy.contains(doc.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warningSoft,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  driver.isEmpty ? 'Driver' : driver,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              if (plate.isNotEmpty) SpPlateBadge(plate: plate),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            (flag['reason'] as String?) ?? '',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
          ),
          if (details.isNotEmpty)
            Text(
              details,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          const SizedBox(height: 4),
          Text(
            'Flagged by ${staff.isEmpty ? 'gate staff' : staff}'
            '${at == null ? '' : ' · ${spFormatDate(at)}, ${spFormatClockTime(at)}'}',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => _resolve(doc.id, () async {
                        await resolveIncident(doc.id, kIncidentDismissed);
                        return true;
                      }),
                child: const Text('Dismiss'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => _resolve(doc.id, () => _report(doc)),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
                icon: const Icon(Icons.flag_rounded, size: 16),
                label: const Text('Report to SmartPark'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
