import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/smartpark_ui.dart';

/// Rebuilds a scanner-compatible QR payload for tickets saved before the QR
/// string was persisted. The gate scanner requires JSON containing at least
/// the transaction id, so a bare document id must never be rendered.
String _resolveTicketQrPayload(
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) {
  final Map<String, dynamic> data = doc.data();
  final String stored = ((data['qrCode'] as String?) ?? '').trim();
  if (stored.isNotEmpty) {
    return stored;
  }
  final DateTime? issuedAt =
      spParseDateTime(data['createdAt']) ??
      spParseDateTime(data['createdAtClient']);
  return jsonEncode(<String, dynamic>{
    'transactionId': doc.id,
    'driverId': (data['driverId'] as String?) ?? '',
    'establishmentId':
        (data['establishmentId'] as String?) ??
        (data['establishmentID'] as String?) ??
        '',
    'vehicleType': (data['vehicleType'] as String?) ?? '',
    'vehiclePlate': (data['vehiclePlate'] as String?) ?? '',
    'plan': (data['plan'] as String?) ?? '',
    'duration': (data['duration'] as num?)?.toInt() ?? 0,
    'generatedAt': (issuedAt ?? DateTime.now()).toIso8601String(),
  });
}

/// Where a ticket is in its life: payment, then gate entry, then gate exit.
enum _TicketState { awaitingPayment, failed, ready, parked, completed }

_TicketState _ticketState(Map<String, dynamic> data) {
  final String status = ((data['status'] as String?) ?? 'paid').toLowerCase();
  final String entry = ((data['entryStatus'] as String?) ?? '').toLowerCase();
  if (status == 'failed' || status == 'expired' || status == 'cancelled') {
    return _TicketState.failed;
  }
  if (status != 'paid') {
    return _TicketState.awaitingPayment;
  }
  if (entry == 'checked_out' || entry == 'exited') {
    return _TicketState.completed;
  }
  if (entry == 'checked_in' || entry == 'inside') {
    return _TicketState.parked;
  }
  return _TicketState.ready;
}

(String, Color, IconData) _stateStyle(_TicketState state) {
  return switch (state) {
    _TicketState.ready => (
      'Ready to use',
      spEntryColor,
      Icons.qr_code_2_rounded,
    ),
    _TicketState.parked => (
      'Parked',
      spInsideColor,
      Icons.local_parking_rounded,
    ),
    _TicketState.completed => (
      'Completed',
      const Color(0xFF737A88),
      Icons.check_circle_outline_rounded,
    ),
    _TicketState.awaitingPayment => (
      'Awaiting payment',
      spInsideColor,
      Icons.hourglass_top_rounded,
    ),
    _TicketState.failed => (
      'Payment failed',
      spDeniedColor,
      Icons.error_outline_rounded,
    ),
  };
}

DateTime? _issuedAt(Map<String, dynamic> data) =>
    spParseDateTime(data['createdAt']) ??
    spParseDateTime(data['createdAtClient']);

class DriverTicketHistorySection extends StatefulWidget {
  const DriverTicketHistorySection({super.key});

  @override
  State<DriverTicketHistorySection> createState() =>
      _DriverTicketHistorySectionState();
}

class _DriverTicketHistorySectionState extends State<DriverTicketHistorySection>
    with SpStreamCache<DriverTicketHistorySection> {
  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(
        child: Text(
          'No logged-in driver found.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: cachedStream(
        'tickets_$uid',
        () => FirebaseFirestore.instance
            .collection('transactions')
            .where('driverId', isEqualTo: uid)
            .snapshots(),
      ),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
          ) {
            final List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets =
                List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                  snapshot.data?.docs ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                );
            final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);
            tickets.sort(
              (
                QueryDocumentSnapshot<Map<String, dynamic>> a,
                QueryDocumentSnapshot<Map<String, dynamic>> b,
              ) => (_issuedAt(b.data()) ?? epoch).compareTo(
                _issuedAt(a.data()) ?? epoch,
              ),
            );

            final List<QueryDocumentSnapshot<Map<String, dynamic>>> active =
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final List<QueryDocumentSnapshot<Map<String, dynamic>>> past =
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                in tickets) {
              final _TicketState state = _ticketState(doc.data());
              if (state == _TicketState.ready || state == _TicketState.parked) {
                active.add(doc);
              } else {
                past.add(doc);
              }
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const SpPageHeader(
                  title: 'Tickets',
                  subtitle: 'Show the QR code to gate staff on entry and exit.',
                ),
                const SizedBox(height: 16),
                if (snapshot.hasError)
                  const SpEmptyState(
                    icon: Icons.error_outline_rounded,
                    message: 'Unable to load your tickets right now.',
                  )
                else if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (tickets.isEmpty)
                  const SpEmptyState(
                    icon: Icons.confirmation_number_outlined,
                    message:
                        'No parking tickets yet. Pick a parking spot on the '
                        'Home tab to buy one.',
                  )
                else ...[
                  const SpSectionLabel('Active'),
                  const SizedBox(height: 8),
                  if (active.isEmpty)
                    const SpEmptyState(
                      icon: Icons.qr_code_2_rounded,
                      message:
                          'No active tickets. Your next ticket shows up here.',
                    )
                  else
                    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                        in active)
                      _ActiveTicketCard(doc: doc),
                  if (past.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const SpSectionLabel('Past Tickets'),
                    const SizedBox(height: 8),
                    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                        in past)
                      _PastTicketRow(doc: doc),
                  ],
                ],
              ],
            );
          },
    );
  }
}

String _vehicleLabel(Map<String, dynamic> data) {
  final String type = ((data['vehicleType'] as String?) ?? '').toLowerCase();
  return switch (type) {
    'car' => 'Car',
    'motorcycle' => 'Motorcycle',
    '' => 'Vehicle',
    _ => '${type[0].toUpperCase()}${type.substring(1)}',
  };
}

IconData _vehicleIcon(Map<String, dynamic> data) =>
    ((data['vehicleType'] as String?) ?? '').toLowerCase() == 'motorcycle'
    ? Icons.two_wheeler_rounded
    : Icons.directions_car_rounded;

String _planLabel(Map<String, dynamic> data) {
  final String plan = ((data['plan'] as String?) ?? '').trim();
  if (plan.isEmpty) return '';
  if (plan.toLowerCase() == 'base') return 'Base · $spBaseStayLabel';
  return '${plan[0].toUpperCase()}${plan.substring(1)}';
}

String _dateTimeLabel(DateTime? date) => date == null
    ? 'Date unavailable'
    : '${spFormatDate(date)}, ${spFormatClockTime(date)}';

class _ActiveTicketCard extends StatelessWidget {
  const _ActiveTicketCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> data = doc.data();
    final _TicketState state = _ticketState(data);
    final (String stateLabel, Color stateColor, IconData _) = _stateStyle(
      state,
    );
    final String name = ((data['establishmentName'] as String?) ?? '').trim();
    final double amount = ((data['amount'] as num?) ?? 0).toDouble();
    final DateTime? enteredAt = spParseDateTime(data['entryAt']);
    final String plan = _planLabel(data);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: spCardBorder),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFFFFEAA8), Color(0xFFF7C846)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Parking Ticket' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1F2532),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state == _TicketState.parked && enteredAt != null
                            ? 'Entered ${spFormatClockTime(enteredAt)}'
                            : 'Show this at the entrance',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3D4658),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    stateLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: stateColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: spCardBorder),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: QrImageView(
                    data: _resolveTicketQrPayload(doc),
                    size: 190,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      _vehicleIcon(data),
                      size: 18,
                      color: AppTheme.textDark,
                    ),
                    const SizedBox(width: 6),
                    SpPlateBadge(
                      plate: (data['vehiclePlate'] as String?) ?? '',
                    ),
                    const Spacer(),
                    Text(
                      'PHP ${amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.isEmpty
                            ? _vehicleLabel(data)
                            : '${_vehicleLabel(data)} · $plan',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    Text(
                      _dateTimeLabel(_issuedAt(data)),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Ticket #${doc.id}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9DA1AB),
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

class _PastTicketRow extends StatelessWidget {
  const _PastTicketRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> data = doc.data();
    final _TicketState state = _ticketState(data);
    final (String stateLabel, Color stateColor, IconData stateIcon) =
        _stateStyle(state);
    final String name = ((data['establishmentName'] as String?) ?? '').trim();
    final double amount = ((data['amount'] as num?) ?? 0).toDouble();
    final int overtimeHours = ((data['overtimeHours'] as num?) ?? 0).toInt();
    final double overtimeAmount = ((data['overtimeAmount'] as num?) ?? 0)
        .toDouble();
    final int? staySeconds = (data['staySeconds'] as num?)?.toInt();
    final String plate = ((data['vehiclePlate'] as String?) ?? '').trim();

    final List<String> details = <String>[
      if (plate.isNotEmpty) plate.toUpperCase(),
      if (state == _TicketState.completed && staySeconds != null)
        'Stayed ${spFormatDuration(Duration(seconds: staySeconds))}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: spCardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(stateIcon, color: stateColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name.isEmpty ? 'Parking Ticket' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PHP ${amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    SpChip(label: stateLabel, color: stateColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _dateTimeLabel(_issuedAt(data)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details.join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
                if (overtimeHours > 0 && overtimeAmount > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3D9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Overtime ${overtimeHours}h · PHP ${overtimeAmount.toStringAsFixed(2)} cash',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: spInsideColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
