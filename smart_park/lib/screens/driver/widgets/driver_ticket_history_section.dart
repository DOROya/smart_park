import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../theme/app_theme.dart';

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

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
      _parseDateTime(data['createdAt']) ?? _parseDateTime(data['createdAtClient']);
  return jsonEncode(<String, dynamic>{
    'transactionId': doc.id,
    'driverId': (data['driverId'] as String?) ?? '',
    'establishmentId': (data['establishmentId'] as String?) ??
        (data['establishmentID'] as String?) ??
        '',
    'vehicleType': (data['vehicleType'] as String?) ?? '',
    'vehiclePlate': (data['vehiclePlate'] as String?) ?? '',
    'plan': (data['plan'] as String?) ?? '',
    'duration': (data['duration'] as num?)?.toInt() ?? 0,
    'generatedAt': (issuedAt ?? DateTime.now()).toIso8601String(),
  });
}

class DriverTicketHistorySection extends StatelessWidget {
  const DriverTicketHistorySection({super.key});

  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _surfaceSoft = Color(0xFFF8F9FC);
  static const Color _textStrong = Color(0xFF1E2330);
  static const Color _textSubtle = Color(0xFF737A88);
  static const Color _stroke = Color(0xFFE4E7EF);

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
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .where('driverId', isEqualTo: uid)
          .snapshots(),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
          ) {
            final List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets =
                snapshot.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];

            tickets.sort((
              QueryDocumentSnapshot<Map<String, dynamic>> a,
              QueryDocumentSnapshot<Map<String, dynamic>> b,
            ) {
              final DateTime aDate =
                _parseDateTime(a.data()['createdAt']) ??
                _parseDateTime(a.data()['createdAtClient']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
              final DateTime bDate =
                _parseDateTime(b.data()['createdAt']) ??
                _parseDateTime(b.data()['createdAtClient']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: [
                const Text(
                  'Ticket History',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: _textStrong,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'View your parking ticket records and QR entries.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _textSubtle,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _stroke),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4CF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.confirmation_number_rounded,
                          color: Color(0xFF353C4C),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${tickets.length} total ticket${tickets.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: _textStrong,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (snapshot.hasError)
                  const _TicketHistoryEmptyState(
                    message: 'Unable to load ticket history right now.',
                  )
                else if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (tickets.isEmpty)
                  const _TicketHistoryEmptyState(
                    message:
                        'No parking tickets yet. Generate one from an establishment detail page.',
                  )
                else
                  ...tickets.map((
                    QueryDocumentSnapshot<Map<String, dynamic>> doc,
                  ) {
                    final Map<String, dynamic> data = doc.data();
                    final String qrData = _resolveTicketQrPayload(doc);
                    final DateTime? createdAt =
                        _parseDateTime(data['createdAt']) ??
                        _parseDateTime(data['createdAtClient']);
                    final String status = (data['status'] as String?) ?? 'paid';
                    final String createdLabel = createdAt == null
                      ? 'Date unavailable'
                      : _formatTimestamp(createdAt);
                    final String establishmentName =
                      (data['establishmentName'] as String?) ??
                      'Parking Ticket';
                    final String amountLabel =
                      'PHP ${(data['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                      color: _surface,
                        borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _stroke),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  establishmentName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: _textStrong,
                                  ),
                                ),
                              ),
                              _StatusChip(status: status),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _surfaceSoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: _TicketMeta(
                              label: 'Amount',
                              value: amountLabel,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Issued: $createdLabel',
                            style: const TextStyle(
                              color: _textSubtle,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: _stroke),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: QrImageView(
                                data: qrData,
                                size: 170,
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Ticket ID: ${doc.id}',
                            style: const TextStyle(
                              color: _textSubtle,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            );
          },
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final String twoDigitDay = dateTime.day.toString().padLeft(2, '0');
    final String twoDigitHour = dateTime.hour.toString().padLeft(2, '0');
    final String twoDigitMinute = dateTime.minute.toString().padLeft(2, '0');
    return '${_monthName(dateTime.month)} $twoDigitDay, ${dateTime.year} • $twoDigitHour:$twoDigitMinute';
  }

  String _monthName(int month) {
    const List<String> monthNames = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    if (month < 1 || month > 12) {
      return 'Unknown';
    }
    return monthNames[month - 1];
  }
}

class _TicketMeta extends StatelessWidget {
  const _TicketMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: DriverTicketHistorySection._textSubtle,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: DriverTicketHistorySection._textStrong,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final String normalized = status.toLowerCase();
    final Color background = switch (normalized) {
      'paid' => const Color(0xFFE8F6EF),
      'pending' => const Color(0xFFFFF3D9),
      'failed' => const Color(0xFFFFE6E6),
      _ => const Color(0xFFF0F2F5),
    };

    final Color foreground = switch (normalized) {
      'paid' => const Color(0xFF1F7A4A),
      'pending' => const Color(0xFF946200),
      'failed' => const Color(0xFFC53B3B),
      _ => const Color(0xFF5A6070),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        normalized.toUpperCase(),
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TicketHistoryEmptyState extends StatelessWidget {
  const _TicketHistoryEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DriverTicketHistorySection._surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DriverTicketHistorySection._stroke),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: DriverTicketHistorySection._textSubtle,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
