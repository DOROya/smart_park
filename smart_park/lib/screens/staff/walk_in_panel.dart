import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/error_reporter.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/smartpark_ui.dart';

/// Gate panel for drive-up customers without a SmartPark ticket.
///
/// A walk-in is stored as a `transactions` doc with `source: 'walk_in'` and
/// `entryStatus: 'checked_in'`, so the updateOccupancy Cloud Function counts
/// it like any parked ticket. No money is recorded; the plate is optional.
class WalkInPanel extends StatefulWidget {
  const WalkInPanel({
    super.key,
    required this.facilityId,
    required this.ownerId,
    this.staffName = '',
  });

  final String facilityId;
  final String? ownerId;
  final String staffName;

  @override
  State<WalkInPanel> createState() => _WalkInPanelState();
}

class _WalkInPanelState extends State<WalkInPanel> {
  final TextEditingController _plateController = TextEditingController();
  bool _saving = false;
  final Set<String> _exiting = <String>{};

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _insideStream =
      FirebaseFirestore.instance
          .collection('transactions')
          .where('establishmentId', isEqualTo: widget.facilityId)
          .where('source', isEqualTo: 'walk_in')
          .where('entryStatus', isEqualTo: 'checked_in')
          .snapshots();

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, dynamic> _logBase({
    required String staffId,
    required String transactionId,
    required String plate,
    required String vehicleType,
  }) {
    return <String, dynamic>{
      'establishmentID': widget.facilityId,
      'facilityId': widget.facilityId,
      'ownerId': widget.ownerId,
      'staffId': staffId,
      'staffEmail': (FirebaseAuth.instance.currentUser?.email ?? '').trim(),
      if (widget.staffName.trim().isNotEmpty)
        'staffName': widget.staffName.trim(),
      'vehiclePlate': plate.isEmpty ? 'WALK-IN' : plate,
      'vehicleType': vehicleType,
      'source': 'walk_in',
      'status': 'ALLOWED',
      'decision': 'ALLOWED',
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'transactionId': transactionId,
    };
  }

  Future<void> _recordEntry(String vehicleType) async {
    final String? staffId = FirebaseAuth.instance.currentUser?.uid;
    if (_saving || staffId == null) return;
    setState(() => _saving = true);
    final String plate = _plateController.text.trim().toUpperCase();
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final DocumentReference<Map<String, dynamic>> ticketRef = db
        .collection('transactions')
        .doc();
    final DocumentReference<Map<String, dynamic>> logRef = db
        .collection('activity_logs')
        .doc();
    try {
      final WriteBatch batch = db.batch();
      batch.set(ticketRef, <String, dynamic>{
        'establishmentId': widget.facilityId,
        'ownerId': widget.ownerId,
        'source': 'walk_in',
        'status': 'walk_in',
        'entryStatus': 'checked_in',
        'entryAt': FieldValue.serverTimestamp(),
        'entryStaffId': staffId,
        'entryLogId': logRef.id,
        'vehicleType': vehicleType,
        'vehiclePlate': plate,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(logRef, <String, dynamic>{
        ..._logBase(
          staffId: staffId,
          transactionId: ticketRef.id,
          plate: plate,
          vehicleType: vehicleType,
        ),
        'scanType': 'entry',
        'gateMode': 'entry',
        'decisionReason': 'Walk-in entry.',
        'isActive': true,
      });
      await batch.commit();
      _plateController.clear();
      _showSnackBar(
        'Walk-in ${vehicleType == 'motorcycle' ? 'motorcycle' : 'car'} '
        'checked in${plate.isEmpty ? '' : ' ($plate)'}.',
      );
    } catch (error, stack) {
      reportError(error, stack, reason: 'Recording walk-in failed');
      _showSnackBar(
        friendlyError(error, fallback: 'Unable to record the walk-in.'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _recordExit(
    QueryDocumentSnapshot<Map<String, dynamic>> ticket,
  ) async {
    final String? staffId = FirebaseAuth.instance.currentUser?.uid;
    if (staffId == null || _exiting.contains(ticket.id)) return;
    setState(() => _exiting.add(ticket.id));
    final Map<String, dynamic> data = ticket.data();
    final String plate = ((data['vehiclePlate'] as String?) ?? '').trim();
    final String vehicleType = (data['vehicleType'] as String?) ?? 'car';
    final DateTime? entryAt = spParseDateTime(data['entryAt']);
    final int staySeconds = entryAt == null
        ? 0
        : DateTime.now().difference(entryAt).inSeconds.clamp(0, 1 << 31);
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final DocumentReference<Map<String, dynamic>> exitRef = db
        .collection('activity_logs')
        .doc();
    try {
      final WriteBatch batch = db.batch();
      batch.update(ticket.reference, <String, dynamic>{
        'entryStatus': 'checked_out',
        'exitAt': FieldValue.serverTimestamp(),
        'exitStaffId': staffId,
        'exitLogId': exitRef.id,
        'staySeconds': staySeconds,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(exitRef, <String, dynamic>{
        ..._logBase(
          staffId: staffId,
          transactionId: ticket.id,
          plate: plate,
          vehicleType: vehicleType,
        ),
        'scanType': 'exit',
        'gateMode': 'exit',
        'decisionReason': 'Walk-in exit.',
        'isActive': false,
        'elapsedSeconds': staySeconds,
      });
      final String entryLogId = ((data['entryLogId'] as String?) ?? '').trim();
      if (entryLogId.isNotEmpty) {
        batch.set(
          db.collection('activity_logs').doc(entryLogId),
          <String, dynamic>{
            'isActive': false,
            'exitAt': FieldValue.serverTimestamp(),
            'exitLogId': exitRef.id,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      _showSnackBar('Walk-in ${plate.isEmpty ? '' : '$plate '}checked out.');
    } catch (error, stack) {
      reportError(error, stack, reason: 'Walk-in checkout failed');
      _showSnackBar(
        friendlyError(error, fallback: 'Unable to check out the walk-in.'),
      );
    } finally {
      if (mounted) setState(() => _exiting.remove(ticket.id));
    }
  }

  String _stayLabel(DateTime? entryAt) {
    if (entryAt == null) return 'Just now';
    final Duration stay = DateTime.now().difference(entryAt);
    if (stay.inMinutes < 1) return 'Just now';
    if (stay.inHours < 1) return '${stay.inMinutes} min';
    return '${stay.inHours}h ${stay.inMinutes % 60}m';
  }

  Widget _entryButton(String vehicleType, IconData icon, String label) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: _saving ? null : () => _recordEntry(vehicleType),
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: AppTheme.onAccent,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
        ),
      ),
    );
  }

  Widget _insideRow(QueryDocumentSnapshot<Map<String, dynamic>> ticket) {
    final Map<String, dynamic> data = ticket.data();
    final String plate = ((data['vehiclePlate'] as String?) ?? '').trim();
    final bool motorcycle = data['vehicleType'] == 'motorcycle';
    final DateTime? entryAt = spParseDateTime(data['entryAt']);
    final bool busy = _exiting.contains(ticket.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            motorcycle
                ? Icons.two_wheeler_rounded
                : Icons.directions_car_rounded,
            size: 20,
            color: AppTheme.textDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plate.isEmpty
                      ? (motorcycle
                            ? 'Motorcycle (no plate)'
                            : 'Car (no plate)')
                      : plate,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  entryAt == null
                      ? 'Inside'
                      : 'In at ${TimeOfDay.fromDateTime(entryAt).format(context)}'
                            ' · ${_stayLabel(entryAt)}',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => _recordExit(ticket),
            style: OutlinedButton.styleFrom(
              foregroundColor: spExitColor,
              side: BorderSide(color: spCardBorder),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Exit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SpSectionCard(
      icon: Icons.directions_walk_rounded,
      title: 'Walk-ins',
      subtitle:
          'Customers without a SmartPark ticket. Counts toward slots only; '
          'no payment is recorded.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _plateController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Plate number (optional)',
              isDense: true,
              filled: true,
              fillColor: AppTheme.surfaceAlt,
              prefixIcon: const Icon(Icons.pin_outlined, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radius),
                borderSide: BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radius),
                borderSide: BorderSide(color: AppTheme.border),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _entryButton('car', Icons.directions_car_rounded, 'Car in'),
              const SizedBox(width: 10),
              _entryButton('motorcycle', Icons.two_wheeler_rounded, 'Motor in'),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _insideStream,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
                ) {
                  final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                  inside =
                      List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                        snapshot.data?.docs ??
                            <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                      )..sort((a, b) {
                        final DateTime now = DateTime.now();
                        return (spParseDateTime(a.data()['entryAt']) ?? now)
                            .compareTo(
                              spParseDateTime(b.data()['entryAt']) ?? now,
                            );
                      });
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inside now (${inside.length})',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                      if (inside.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'No walk-ins inside.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        )
                      else
                        for (final QueryDocumentSnapshot<Map<String, dynamic>>
                            ticket
                            in inside)
                          _insideRow(ticket),
                    ],
                  );
                },
          ),
        ],
      ),
    );
  }
}
