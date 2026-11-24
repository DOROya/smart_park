import 'package:flutter/material.dart';

import '../../../services/facility_closure.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../widgets/smartpark_ui.dart';

/// Close the facility for a while (a holiday, repairs) and reopen it. While
/// closed, the gate admits no one, exits still go through, overtime
/// doesn't run, and drivers see "Closed until". It reopens by itself.
class OwnerClosureCard extends StatefulWidget {
  const OwnerClosureCard({
    super.key,
    required this.facilityId,
    required this.details,
  });

  final String facilityId;
  final Map<String, dynamic>? details;

  @override
  State<OwnerClosureCard> createState() => _OwnerClosureCardState();
}

class _OwnerClosureCardState extends State<OwnerClosureCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(error, fallback: 'Could not save. Try again.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final ({DateTime until, String reason})? picked =
        await showDialog<({DateTime until, String reason})>(
          context: context,
          builder: (_) => const _CloseDialog(),
        );
    if (picked == null) return;
    await _run(
      () => setTemporaryClosure(
        widget.facilityId,
        until: picked.until,
        reason: picked.reason,
      ),
      'Closed until ${spFormatDate(picked.until)}, '
      '${spFormatClockTime(picked.until)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final TemporaryClosure? closure = TemporaryClosure.of(widget.details);
    if (closure == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : _close,
          icon: const Icon(Icons.event_busy_outlined, size: 18),
          label: const Text('Close temporarily'),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dangerSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.dangerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.event_busy_rounded, color: spDeniedColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Closed until ${temporaryClosureUntilLabel(closure)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${closure.reason.isEmpty ? '' : '${closure.reason}. '}'
            'The gate admits no one until then; vehicles inside can still '
            'leave and pay no overtime for the closed time. It reopens by '
            'itself.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                    () => clearTemporaryClosure(widget.facilityId),
                    'Reopened.',
                  ),
            icon: const Icon(Icons.lock_open_rounded, size: 18),
            label: const Text('Reopen now'),
          ),
        ],
      ),
    );
  }
}

class _CloseDialog extends StatefulWidget {
  const _CloseDialog();

  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  final TextEditingController _reason = TextEditingController();
  DateTime _until = DateTime.now().add(const Duration(days: 1));
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final DateTime now = DateTime.now();
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: _until,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: kMaxClosureDays)),
    );
    if (day == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_until),
    );
    if (time == null) return;
    setState(() {
      _until = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Close temporarily'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'No entries or walk-ins until then. Tickets and temporary QRs '
              'stay valid, and drivers holding them are notified.',
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(
                'Until ${spFormatDate(_until)}, ${spFormatClockTime(_until)}',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLength: kMaxClosureReasonLength,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Closed for the holiday',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: spDeniedColor)),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final String? denial = closureDenial(_until, _reason.text);
            if (denial != null) {
              setState(() => _error = denial);
              return;
            }
            Navigator.of(context).pop((until: _until, reason: _reason.text));
          },
          child: const Text('Close facility'),
        ),
      ],
    );
  }
}
