import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/driver_reports.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'smartpark_ui.dart';

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

/// Asks the owner why they're reporting the driver of [ticket], then files
/// the report. Returns whether one was sent.
Future<bool> showReportDriverDialog(
  BuildContext context, {
  required String ownerId,
  required String ticketId,
  required Map<String, dynamic> ticket,
}) async {
  final bool? sent = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => _ReportDriverDialog(
      ownerId: ownerId,
      ticketId: ticketId,
      ticket: ticket,
    ),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report sent to the SmartPark admin.')),
    );
  }
  return sent ?? false;
}

class _ReportDriverDialog extends StatefulWidget {
  const _ReportDriverDialog({
    required this.ownerId,
    required this.ticketId,
    required this.ticket,
  });

  final String ownerId;
  final String ticketId;
  final Map<String, dynamic> ticket;

  @override
  State<_ReportDriverDialog> createState() => _ReportDriverDialogState();
}

class _ReportDriverDialogState extends State<_ReportDriverDialog> {
  final TextEditingController _details = TextEditingController();
  String? _reason;
  bool _missing = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String? reason = _reason;
    if (reason == null || (reason == 'Other' && _details.text.trim().isEmpty)) {
      setState(() => _missing = true);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await submitDriverReport(
        ownerId: widget.ownerId,
        establishmentId: ((widget.ticket['establishmentId'] as String?) ?? '')
            .trim(),
        establishmentName:
            ((widget.ticket['establishmentName'] as String?) ?? '').trim(),
        transactionId: widget.ticketId,
        driverId: ((widget.ticket['driverId'] as String?) ?? '').trim(),
        driverName: ((widget.ticket['driverName'] as String?) ?? '').trim(),
        reason: reason,
        details: _details.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = friendlyError(error, fallback: 'Could not send the report.');
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
      title: const Text('Report driver'),
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
                'The SmartPark admin reviews every report and may warn the '
                'driver. The driver is not told who reported them.',
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final String reason in kDriverReportReasons)
                    ChoiceChip(
                      label: Text(reason),
                      selected: _reason == reason,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _reason == reason
                            ? AppTheme.onAccent
                            : AppTheme.textDark,
                      ),
                      selectedColor: AppTheme.accent,
                      backgroundColor: AppTheme.surface,
                      side: BorderSide(
                        color: _reason == reason
                            ? AppTheme.accent
                            : _missing
                            ? AppTheme.dangerBorder
                            : AppTheme.border,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      onSelected: _sending
                          ? null
                          : (bool on) => setState(() {
                              _reason = on ? reason : null;
                              _missing = false;
                            }),
                    ),
                ],
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
                  labelText: _reason == 'Other'
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
                      (_reason == 'Other'
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
          label: Text(_sending ? 'Sending...' : 'Send report'),
        ),
      ],
    );
  }
}
