import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'gate_cash.dart';
import 'gate_scan_service.dart' show overtimeStatusOf;

/// The owner's gate activity for a date range as a CSV file, for the
/// accountant, a dispute or an incident check: every scan with its time,
/// plate, driver, staff, result, stay, and the cash taken at the gate.

/// Longest range one export covers.
const int kMaxExportDays = 93;

const String kCsvMimeType = 'text/csv';

/// The facility's gate logs from [first] to [last] (whole local days),
/// oldest first.
Future<List<Map<String, dynamic>>> loadActivityRange(
  String facilityId,
  DateTime first,
  DateTime last, {
  FirebaseFirestore? firestore,
}) async {
  final DateTime start = DateTime(first.year, first.month, first.day);
  final DateTime end = DateTime(last.year, last.month, last.day + 1);
  final QuerySnapshot<Map<String, dynamic>> snap =
      await (firestore ?? FirebaseFirestore.instance)
          .collection('activity_logs')
          .where('establishmentID', isEqualTo: facilityId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('timestamp', isLessThan: Timestamp.fromDate(end))
          // Newest first uses the index the Activity tab already has.
          .orderBy('timestamp', descending: true)
          .get();
  return <Map<String, dynamic>>[
    for (final QueryDocumentSnapshot<Map<String, dynamic>> d
        in snap.docs.reversed)
      <String, dynamic>{...d.data(), '_id': d.id},
  ];
}

const List<String> kActivityCsvColumns = <String>[
  'Date',
  'Time',
  'Scan',
  'Result',
  'Reason',
  'Plate',
  'Vehicle type',
  'Customer',
  'Driver',
  'Ticket #',
  'Staff',
  'Stay (h:mm)',
  'Overtime (PHP)',
  'Overtime status',
  'Walk-in fee (PHP)',
  'Cash handed over',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// A CSV field: quoted when it holds a comma, quote or line break, and a
/// leading =, +, - or @ is escaped so a spreadsheet never runs it.
String csvField(Object? value) {
  String text = value?.toString() ?? '';
  if (text.isNotEmpty && '=+-@'.contains(text[0])) text = "'$text";
  if (text.contains(RegExp(r'[",\r\n]'))) {
    text = '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

String _money(double amount) => amount == 0 ? '' : amount.toStringAsFixed(2);

/// One CSV row per gate log. [staffName] names the staff member who
/// scanned (the screen's own lookup, so removed staff still show).
List<String> activityCsvRow(
  Map<String, dynamic> log,
  String Function(Map<String, dynamic> log) staffName,
) {
  final Object? ts = log['timestamp'];
  final DateTime? at = ts is Timestamp ? ts.toDate() : null;
  final int stay = ((log['elapsedSeconds'] as num?) ?? 0).toInt();
  final String status = overtimeStatusOf(log);
  final double overtime = ((log['overtimeAmount'] as num?) ?? 0).toDouble();
  final bool walkIn = log['source'] == 'walk_in';
  return <String>[
    at == null ? '' : '${at.year}-${_two(at.month)}-${_two(at.day)}',
    at == null ? '' : '${_two(at.hour)}:${_two(at.minute)}',
    switch (log['scanType']) {
      'entry' => 'Entry',
      'exit' => 'Exit',
      final Object? other => '${other ?? ''}',
    },
    ((log['decision'] ?? log['status']) as String? ?? '').toUpperCase() ==
            'ALLOWED'
        ? 'Allowed'
        : 'Denied',
    (log['decisionReason'] as String?) ?? '',
    (log['vehiclePlate'] as String?) ?? '',
    (log['vehicleType'] as String?) ?? '',
    walkIn ? 'Walk-in' : 'SmartPark',
    (log['driverName'] as String?) ?? '',
    (log['transactionId'] as String?) ?? '',
    staffName(log),
    stay <= 0 ? '' : '${stay ~/ 3600}:${_two((stay % 3600) ~/ 60)}',
    _money(overtime),
    overtime == 0 ? '' : status,
    _money(walkInFeeOf(log)),
    ((log['cashHandoverId'] as String?) ?? '').isEmpty
        ? (awaitsHandover(log) ? 'Not yet' : '')
        : 'Yes',
  ].map(csvField).toList();
}

/// The whole file: a header row, then [logs]. A UTF-8 byte order mark
/// lets Excel read names with accents correctly.
Uint8List buildActivityCsv(
  List<Map<String, dynamic>> logs,
  String Function(Map<String, dynamic> log) staffName,
) {
  final StringBuffer out = StringBuffer('﻿')
    ..write(kActivityCsvColumns.map(csvField).join(','))
    ..write('\r\n');
  for (final Map<String, dynamic> log in logs) {
    out
      ..write(activityCsvRow(log, staffName).join(','))
      ..write('\r\n');
  }
  return Uint8List.fromList(utf8.encode(out.toString()));
}

/// e.g. "SmartPark-activity-2026-11-01-to-2026-11-20.csv".
String activityCsvFileName(DateTime first, DateTime last) {
  String d(DateTime x) => '${x.year}-${_two(x.month)}-${_two(x.day)}';
  return 'SmartPark-activity-${d(first)}-to-${d(last)}.csv';
}
