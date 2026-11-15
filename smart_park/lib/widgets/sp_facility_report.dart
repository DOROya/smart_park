import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/facility_reports.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'sp_reason_dropdowns.dart';

/// "Report facility" on a driver's ticket: opens the report form for the
/// facility that ticket is for.
class SpReportFacilityButton extends StatelessWidget {
  const SpReportFacilityButton({
    super.key,
    required this.ticketId,
    required this.ticket,
  });

  final String ticketId;
  final Map<String, dynamic> ticket;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () =>
          showFacilityReportSheet(context, ticketId: ticketId, ticket: ticket),
      icon: const Icon(Icons.flag_outlined, size: 16),
      label: const Text('Report facility'),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.textSecondary,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// The driver's form for reporting the facility of [ticket] to SmartPark.
Future<void> showFacilityReportSheet(
  BuildContext context, {
  required String ticketId,
  required Map<String, dynamic> ticket,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.surface,
    builder: (_) => _FacilityReportSheet(ticketId: ticketId, ticket: ticket),
  );
}

class _FacilityReportSheet extends StatefulWidget {
  const _FacilityReportSheet({required this.ticketId, required this.ticket});

  final String ticketId;
  final Map<String, dynamic> ticket;

  @override
  State<_FacilityReportSheet> createState() => _FacilityReportSheetState();
}

class _FacilityReportSheetState extends State<_FacilityReportSheet> {
  final TextEditingController _details = TextEditingController();
  List<String?> _reasons = <String?>[null];
  bool _missing = false;
  bool _sending = false;

  String get _facility =>
      ((widget.ticket['establishmentName'] as String?) ?? '').trim();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final List<String> reasons = spPickedReasons(_reasons);
    final String details = _details.text.trim();
    // "Other" on its own tells the admin nothing.
    if (reasons.isEmpty || (reasons.contains('Other') && details.isEmpty)) {
      setState(() => _missing = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reasons.isEmpty
                ? 'Pick at least one reason.'
                : 'Describe what happened for "Other".',
          ),
        ),
      );
      return;
    }
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _sending = true);
    try {
      await submitFacilityReport(
        driverId: uid,
        driverName: ((widget.ticket['driverName'] as String?) ?? '').trim(),
        establishmentId: ((widget.ticket['establishmentId'] as String?) ?? '')
            .trim(),
        establishmentName: _facility,
        transactionId: widget.ticketId,
        reasons: reasons,
        details: details,
      );
      if (!mounted) return;
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Report sent. A SmartPark admin will review it.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(error, fallback: 'Could not send the report.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
          children: <Widget>[
            Text(
              'Report ${_facility.isEmpty ? 'this facility' : _facility}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your report goes to SmartPark, not to the facility. The '
              'facility is not told who reported it.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            SpReasonDropdowns(
              options: kFacilityReportReasons,
              values: _reasons,
              missing: _missing,
              enabled: !_sending,
              onChanged: (List<String?> v) => setState(() {
                _reasons = v;
                _missing = false;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _details,
              enabled: !_sending,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: 'What happened? (optional)',
                hintText: 'When it happened, what was said or charged...',
                hintStyle: const TextStyle(fontSize: 12),
                filled: true,
                fillColor: AppTheme.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              icon: const Icon(Icons.flag_rounded, size: 18),
              label: Text(_sending ? 'Sending...' : 'Send report'),
            ),
          ],
        ),
      ),
    );
  }
}
