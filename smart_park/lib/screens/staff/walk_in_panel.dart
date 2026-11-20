import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/error_reporter.dart';
import '../../services/gate_cash.dart' show kMaxWalkInFee;
import '../../services/gate_scan_service.dart' show settleGateWrite;
import '../../services/gate_unsent_exits.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_vehicle_type.dart';

/// Gate panel for drive-up customers without a SmartPark ticket.
///
/// A walk-in is stored as a `transactions` doc with `source: 'walk_in'` and
/// `entryStatus: 'checked_in'`, so the updateOccupancy Cloud Function counts
/// it like any parked ticket. The plate is optional. At exit, staff enter
/// the cash fee the walk-in paid (if any); it goes on the exit log for the
/// owner's books and the end-of-shift cash handover.
class WalkInPanel extends StatefulWidget {
  const WalkInPanel({
    super.key,
    required this.facilityId,
    required this.ownerId,
    this.staffName = '',
    this.entryClosed = false,
    this.unsent,
  });

  /// Where an exit recorded without a connection is followed until it is
  /// on the server.
  final GateUnsentExits? unsent;

  final String facilityId;
  final String? ownerId;
  final String staffName;

  /// The facility was pulled by an admin: no new walk-ins, exits only.
  final bool entryClosed;

  @override
  State<WalkInPanel> createState() => _WalkInPanelState();
}

class _WalkInPanelState extends State<WalkInPanel> {
  final TextEditingController _plateController = TextEditingController();
  bool _saving = false;
  final Set<String> _exiting = <String>{};

  /// The facility's details, for any custom vehicle type (e.g. trucks).
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _detailsStream =
      FirebaseFirestore.instance
          .collection('establishment_details')
          .doc(widget.facilityId)
          .snapshots();

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
    if (_saving || staffId == null || widget.entryClosed) return;
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
        'Walk-in ${spVehicleTypeLabel(vehicleType).toLowerCase()} '
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
    // The cash fee the walk-in paid, for the owner's books and handover.
    final double? fee = await _askWalkInFee(ticket.data());
    if (fee == null || !mounted) return;
    setState(() => _exiting.add(ticket.id));
    final Map<String, dynamic> data = ticket.data();
    final String plate = ((data['vehiclePlate'] as String?) ?? '').trim();
    final String vehicleType = (data['vehicleType'] as String?) ?? 'car';
    final DateTime? entryAt = spParseDateTime(data['entryAt']);
    // This device's time: without a connection the exit is sent later, and
    // must still say when the vehicle left.
    final DateTime leftAt = DateTime.now();
    final Timestamp exitAt = Timestamp.fromDate(leftAt);
    final int staySeconds = entryAt == null
        ? 0
        : leftAt.difference(entryAt).inSeconds.clamp(0, 1 << 31);
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final DocumentReference<Map<String, dynamic>> exitRef = db
        .collection('activity_logs')
        .doc();
    try {
      final WriteBatch batch = db.batch();
      batch.update(ticket.reference, <String, dynamic>{
        'entryStatus': 'checked_out',
        'exitAt': exitAt,
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
        'timestamp': exitAt,
        'createdAt': exitAt,
        'decisionReason': 'Walk-in exit.',
        'isActive': false,
        'elapsedSeconds': staySeconds,
        if (fee > 0) 'walkInFee': fee,
      });
      final String entryLogId = ((data['entryLogId'] as String?) ?? '').trim();
      if (entryLogId.isNotEmpty) {
        batch.set(
          db.collection('activity_logs').doc(entryLogId),
          <String, dynamic>{
            'isActive': false,
            'exitAt': exitAt,
            'exitLogId': exitRef.id,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      // Without a connection the exit is kept on this device and sent later.
      final bool sent = await settleGateWrite(
        batch.commit(),
        onQueued: (Future<void> write) => widget.unsent?.track(
          UnsentExit(
            transactionId: ticket.id,
            exitLogId: exitRef.id,
            plate: plate,
            leftAt: leftAt,
            walkIn: true,
          ),
          write,
        ),
      );
      if (sent) widget.unsent?.resolve(ticket.id);
      _showSnackBar(
        'Walk-in ${plate.isEmpty ? '' : '$plate '}checked out'
        '${fee > 0 ? ', ${spPeso(fee)} collected' : ''}.'
        '${sent ? '' : ' No connection: saved on this device and sent when it is back.'}',
      );
    } catch (error, stack) {
      reportError(error, stack, reason: 'Walk-in checkout failed');
      _showSnackBar(
        friendlyError(error, fallback: 'Unable to check out the walk-in.'),
      );
    } finally {
      if (mounted) setState(() => _exiting.remove(ticket.id));
    }
  }

  /// Asks what the walk-in paid in cash (0 for none). Null if staff
  /// cancel, and then nothing is recorded.
  Future<double?> _askWalkInFee(Map<String, dynamic> data) {
    final String plate = ((data['vehiclePlate'] as String?) ?? '').trim();
    return showDialog<double>(
      context: context,
      builder: (BuildContext context) => _WalkInFeeDialog(
        title: plate.isEmpty ? 'Walk-in exit' : 'Walk-in exit · $plate',
        stay: _stayLabel(spParseDateTime(data['entryAt'])),
      ),
    );
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
        onPressed: _saving || widget.entryClosed
            ? null
            : () => _recordEntry(vehicleType),
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
    final String type = spVehicleTypeKey(data['vehicleType']);
    final DateTime? entryAt = spParseDateTime(data['entryAt']);
    final bool busy = _exiting.contains(ticket.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(spVehicleTypeIcon(type), size: 20, color: AppTheme.textDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plate.isEmpty
                      ? '${spVehicleTypeLabel(type)} (no plate)'
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
          'Customers without a SmartPark ticket. They count toward slots, '
          'and the cash fee you take at their exit is recorded.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.entryClosed) ...[
            Text(
              'New walk-ins are closed while this facility is pulled. '
              'Walk-ins already inside can still exit below.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: spDeniedColor,
              ),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _plateController,
            enabled: !widget.entryClosed,
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
          // A custom vehicle type the owner added, e.g. trucks.
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _detailsStream,
            builder: (BuildContext context, snap) {
              final List<String> others = spOtherVehicleSlots(
                snap.data?.data()?['slotCounts'],
              ).keys.toList();
              if (others.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    for (final String key in others) ...[
                      if (key != others.first) const SizedBox(width: 10),
                      _entryButton(
                        key,
                        spVehicleTypeIcon(key),
                        '${spVehicleTypeLabel(key)} in',
                      ),
                    ],
                  ],
                ),
              );
            },
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

/// The cash fee for a walk-in leaving: pops the amount (0 for "No fee").
class _WalkInFeeDialog extends StatefulWidget {
  const _WalkInFeeDialog({required this.title, required this.stay});

  final String title;
  final String stay;

  @override
  State<_WalkInFeeDialog> createState() => _WalkInFeeDialogState();
}

class _WalkInFeeDialogState extends State<_WalkInFeeDialog> {
  final TextEditingController _fee = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  void _save() {
    final double? fee = double.tryParse(_fee.text.trim());
    if (fee == null || fee <= 0 || fee > kMaxWalkInFee) {
      setState(() => _error = 'Enter the amount collected, or tap No fee.');
      return;
    }
    Navigator.of(context).pop((fee * 100).round() / 100);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            // "Parked just now." / "Parked 1h 05m."
            'Parked ${widget.stay == 'Just now' ? 'just now' : widget.stay}. '
            'Enter the parking fee you collected in '
            'cash; it is added to the cash you hand to the owner.',
            style: TextStyle(color: AppTheme.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fee,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(
                RegExp(r'^\d{0,6}(\.\d{0,2})?'),
              ),
            ],
            decoration: InputDecoration(
              labelText: 'Fee collected',
              prefixText: '₱ ',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(0.0),
          child: const Text('No fee'),
        ),
        FilledButton(onPressed: _save, child: const Text('Record exit')),
      ],
    );
  }
}
