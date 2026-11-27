import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/parking_checkout_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../widgets/smartpark_ui.dart';
import '../../../widgets/sp_dialog.dart';

/// Shown when a driver hits the open-ticket limit (unused temporary QRs
/// plus parked vehicles): instead of a dead end, their unused QRs, each
/// with Cancel, so they can make room right there. Returns true when at
/// least one was cancelled, so the caller can try again.
Future<bool> showOpenTicketsSheet(BuildContext context) async {
  final bool? freed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.surface,
    builder: (_) => const _OpenTicketsSheet(),
  );
  return freed ?? false;
}

class _OpenTicketsSheet extends StatefulWidget {
  const _OpenTicketsSheet();

  @override
  State<_OpenTicketsSheet> createState() => _OpenTicketsSheetState();
}

class _OpenTicketsSheetState extends State<_OpenTicketsSheet> {
  final ParkingCheckoutService _service = ParkingCheckoutService();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _passes =
      FirebaseFirestore.instance
          .collection('parking_checkouts')
          .where('driverId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .where('kind', isEqualTo: 'gate_pass')
          .where('status', isEqualTo: 'awaiting_gate')
          .snapshots();
  final Set<String> _busy = <String>{};
  bool _freed = false;

  Future<void> _cancel(String id) async {
    setState(() => _busy.add(id));
    try {
      await _service.cancelPass(id);
      _freed = true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(error, fallback: 'Could not cancel the QR.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _passes,
          builder: (BuildContext context, snapshot) {
            final List<QueryDocumentSnapshot<Map<String, dynamic>>> open =
                (snapshot.data?.docs ??
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                    .where((d) {
                      final DateTime? until = spParseDateTime(
                        d.data()['expiresAt'],
                      );
                      return until == null || until.isAfter(now);
                    })
                    .toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Center(
                  child: SpDialogIcon(
                    Icons.confirmation_number_outlined,
                    tone: SpDialogTone.warning,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Too many open tickets',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You can have up to 3 at a time, counting unused temporary '
                  'QRs and vehicles parked on your tickets. Cancel a QR you '
                  'no longer need to make a new one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.4, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                if (!snapshot.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (open.isEmpty)
                  SpEmptyState(
                    icon: Icons.local_parking_rounded,
                    message: _freed
                        ? 'Done. You can make a new temporary QR now.'
                        : 'No unused QRs to cancel: your vehicles are '
                              'parked. If one already left, ask that '
                              'facility to record its exit.',
                  )
                else
                  for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                      in open)
                    _row(d.id, d.data()),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_freed),
                  child: Text(_freed ? 'Make a new QR' : 'Close'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(String id, Map<String, dynamic> pass) {
    final String facility =
        ((pass['establishmentName'] as String?) ?? '').trim().isEmpty
        ? 'Parking'
        : (pass['establishmentName'] as String).trim();
    final String plate = ((pass['vehiclePlate'] as String?) ?? '').trim();
    final DateTime? until = spParseDateTime(pass['expiresAt']);
    final bool busy = _busy.contains(id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        border: Border.all(color: spCardBorder),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.qr_code_2_rounded, color: AppTheme.accentText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  facility,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  <String>[
                    plate,
                    if (until != null) 'Valid until ${spFormatDate(until)}',
                  ].joinDots(),
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => _cancel(id),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: Text(busy ? 'Cancelling...' : 'Cancel'),
          ),
        ],
      ),
    );
  }
}
