import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'error_reporter.dart';
import 'parking_pricing.dart';

/// Result of a single gate scan shown to the staff member.
class GateScanResult {
  GateScanResult({
    required this.decision,
    required this.vehiclePlate,
    required this.scanType,
    required this.timestamp,
    this.reason,
    this.transactionId,
    this.elapsed,
    this.billableHours,
    this.overtimeHours,
    this.overtimeAmount,
    this.activityLogId,
    this.overtimeCollected = false,
  });

  final String decision;
  final String vehiclePlate;
  final String scanType;
  final DateTime timestamp;
  final String? reason;
  final String? transactionId;
  final Duration? elapsed;
  final int? billableHours;
  final double? overtimeHours;
  final double? overtimeAmount;

  /// The gate log this scan wrote (the exit log for an exit scan).
  final String? activityLogId;

  /// Staff confirmed the overtime cash was handed over.
  final bool overtimeCollected;

  bool get isAllowed => decision == 'ALLOWED';
  bool get isDenied => decision == 'DENIED';
  bool get hasOvertime => (overtimeHours ?? 0) > 0 && (overtimeAmount ?? 0) > 0;

  /// This result after the overtime cash was marked collected.
  GateScanResult markedCollected() => GateScanResult(
    decision: decision,
    vehiclePlate: vehiclePlate,
    scanType: scanType,
    timestamp: timestamp,
    reason: 'Overtime cash collected. Release.',
    transactionId: transactionId,
    elapsed: elapsed,
    billableHours: billableHours,
    overtimeHours: overtimeHours,
    overtimeAmount: overtimeAmount,
    activityLogId: activityLogId,
    overtimeCollected: true,
  );
}

/// `overtimeStatus` values on exit logs and tickets.
const String kOvertimeNone = 'none';
const String kOvertimeCashDue = 'cash_due';
const String kOvertimeCollected = 'collected';
const String kOvertimeRateUnresolved = 'rate_unresolved';

/// The owner let the driver off the overtime charge.
const String kOvertimeWaived = 'waived';

/// Statuses an owner may switch an overtime exit between.
const List<String> kOwnerOvertimeStatuses = <String>[
  kOvertimeCashDue,
  kOvertimeCollected,
  kOvertimeWaived,
];

/// Owner override of an exit's overtime status (e.g. cash handed over without
/// staff confirming it, a wrong confirmation, or a waived charge). Updates the
/// ticket and its exit log. Only exits that billed overtime cash can change.
Future<void> setOvertimeStatusAsOwner({
  required String ownerId,
  required String transactionId,
  required String status,
  FirebaseFirestore? firestore,
}) async {
  if (!kOwnerOvertimeStatuses.contains(status)) {
    throw ArgumentError.value(status, 'status');
  }
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  final DocumentReference<Map<String, dynamic>> ticketRef = db
      .collection('transactions')
      .doc(transactionId);
  final Map<String, dynamic> ticket =
      (await ticketRef.get()).data() ?? <String, dynamic>{};
  final String current = ((ticket['overtimeStatus'] as String?) ?? '')
      .toLowerCase();
  if (!kOwnerOvertimeStatuses.contains(current)) {
    throw StateError('This exit has no overtime cash to update.');
  }
  if (current == status) return;
  final Map<String, dynamic> fields = <String, dynamic>{
    'overtimeStatus': status,
    'overtimeStatusBy': ownerId,
    'overtimeStatusAt': FieldValue.serverTimestamp(),
    // Only a collected exit names who took the cash.
    'overtimeCollectedBy': status == kOvertimeCollected
        ? ownerId
        : FieldValue.delete(),
    'overtimeCollectedAt': status == kOvertimeCollected
        ? FieldValue.serverTimestamp()
        : FieldValue.delete(),
  };
  final String logId = ((ticket['exitLogId'] as String?) ?? '').trim();
  final WriteBatch batch = db.batch();
  batch.set(ticketRef, <String, dynamic>{
    ...fields,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  if (logId.isNotEmpty) {
    batch.set(
      db.collection('activity_logs').doc(logId),
      fields,
      SetOptions(merge: true),
    );
  }
  await batch.commit();
}

/// The signed-in staff member operating the gate.
class GateStaff {
  const GateStaff({
    required this.staffId,
    required this.email,
    required this.facilityId,
    required this.ownerId,
    this.name = '',
  });

  final String staffId;
  final String email;
  final String? facilityId;
  final String? ownerId;

  /// Name from the staff record, stamped on each log so the owner can still
  /// see who scanned after the staff member is removed.
  final String name;
}

/// Which facility a staff account is assigned to.
class StaffAssignment {
  const StaffAssignment({
    required this.facilityId,
    required this.ownerId,
    this.staffName = '',
    this.deactivated = false,
  });

  final String? facilityId;
  final String? ownerId;
  final String staffName;

  /// The owner deactivated this staff account; it may not work the gate.
  final bool deactivated;
}

/// Whether a `staff_accounts` record is active. Records from before
/// deactivation existed have no `active` field and count as active.
bool isStaffRecordActive(Map<String, dynamic> data) => data['active'] != false;

/// Verifies parking tickets at the gate and records entry/exit scans.
///
/// Holds a short re-scan cooldown, so keep one instance per gate screen.
class GateScanService {
  GateScanService({FirebaseFirestore? firestore, DateTime Function()? clock})
    : _db = firestore ?? FirebaseFirestore.instance,
      _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  /// Guards against re-processing the same ticket while the camera keeps
  /// reporting it.
  String? _lastProcessedTicketKey;
  DateTime? _lastProcessedAt;

  static const Duration rescanCooldown = Duration(seconds: 8);

  /// Looks up the facility for [uid]: by staff record, then by staff email,
  /// then from the user's own profile.
  Future<StaffAssignment> resolveAssignment({
    required String uid,
    required String email,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> byUid = await _db
        .collection('staff_accounts')
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();
    if (byUid.docs.isNotEmpty) {
      return _assignmentFrom(byUid.docs.first.data());
    }

    final String normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isNotEmpty) {
      final QuerySnapshot<Map<String, dynamic>> byEmail = await _db
          .collection('staff_accounts')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) {
        return _assignmentFrom(byEmail.docs.first.data());
      }
    }

    final DocumentSnapshot<Map<String, dynamic>> userDoc = await _db
        .collection('users')
        .doc(uid)
        .get();
    return _assignmentFrom(userDoc.data() ?? <String, dynamic>{});
  }

  StaffAssignment _assignmentFrom(Map<String, dynamic> data) {
    if (!isStaffRecordActive(data)) {
      return StaffAssignment(
        facilityId: null,
        ownerId: data['ownerId'] as String?,
        staffName: ((data['name'] as String?) ?? '').trim(),
        deactivated: true,
      );
    }
    return StaffAssignment(
      facilityId:
          (data['establishmentID'] as String?) ??
          (data['facilityId'] as String?),
      ownerId: data['ownerId'] as String?,
      staffName: ((data['name'] as String?) ?? '').trim(),
    );
  }

  /// Handles a scanned QR code. Returns null when the scan is ignored because
  /// the same ticket was just processed.
  Future<GateScanResult?> handleScanPayload({
    required GateStaff staff,
    required String gateMode,
    required String rawPayload,
  }) async {
    final String? facilityId = staff.facilityId;
    if (facilityId == null || facilityId.isEmpty) {
      return GateScanResult(
        decision: 'DENIED',
        vehiclePlate: '--',
        scanType: gateMode,
        timestamp: _now(),
        reason: 'Staff is not assigned to a facility yet.',
      );
    }
    final Map<String, dynamic>? payload = _decodePayload(rawPayload);
    if (payload == null) {
      await _logDeniedScan(
        staff: staff,
        scanType: gateMode,
        vehiclePlate: 'unreadable',
        decisionReason: 'QR is not a SmartPark ticket.',
      );
      return GateScanResult(
        decision: 'DENIED',
        vehiclePlate: '--',
        scanType: gateMode,
        timestamp: _now(),
        reason: 'Not a SmartPark ticket QR.',
      );
    }
    final String txId = ((payload['transactionId'] as String?) ?? '').trim();
    final String pPlate = ((payload['vehiclePlate'] as String?) ?? '--').trim();
    if (txId.isEmpty) {
      await _logDeniedScan(
        staff: staff,
        scanType: gateMode,
        vehiclePlate: pPlate,
        decisionReason: 'Ticket payload missing transaction id.',
      );
      return GateScanResult(
        decision: 'DENIED',
        vehiclePlate: pPlate,
        scanType: gateMode,
        timestamp: _now(),
        reason: 'Ticket is unreadable. Use plate lookup.',
      );
    }
    return _verifyTicket(
      staff: staff,
      facilityId: facilityId,
      gateMode: gateMode,
      transactionId: txId,
      payloadPlate: pPlate,
    );
  }

  Map<String, dynamic>? _decodePayload(String rawPayload) {
    try {
      final dynamic decoded = jsonDecode(rawPayload);
      if (decoded is Map) {
        return decoded.map<String, dynamic>(
          (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v),
        );
      }
    } on FormatException {
      // Not JSON; not one of our tickets.
    }
    return null;
  }

  /// Finds this facility's ticket for [rawPlate] (for unreadable QR codes)
  /// and verifies it like a scan. Returns null when the scan is ignored
  /// because the same ticket was just processed.
  Future<GateScanResult?> lookupByPlate({
    required GateStaff staff,
    required String gateMode,
    required String rawPlate,
  }) async {
    final String plate = rawPlate.trim();
    if (plate.isEmpty) {
      return GateScanResult(
        decision: 'ERROR',
        vehiclePlate: '--',
        scanType: gateMode,
        timestamp: _now(),
        reason: 'Type the plate before lookup.',
      );
    }
    final String? facilityId = staff.facilityId;
    if (facilityId == null || facilityId.isEmpty) {
      return GateScanResult(
        decision: 'DENIED',
        vehiclePlate: plate,
        scanType: gateMode,
        timestamp: _now(),
        reason: 'Staff not assigned to a facility.',
      );
    }
    try {
      final QuerySnapshot<Map<String, dynamic>> matches = await _db
          .collection('transactions')
          .where('establishmentId', isEqualTo: facilityId)
          // New tickets store the plate upper-cased; older ones as typed.
          .where(
            'vehiclePlate',
            whereIn: <String>{plate, plate.toUpperCase()}.toList(),
          )
          .limit(10)
          .get();
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> mine = matches
          .docs
          .where((QueryDocumentSnapshot<Map<String, dynamic>> d) {
            final Map<String, dynamic> m = d.data();
            // Walk-ins are checked out from the Walk-ins panel instead.
            return _ticketFacility(m) == facilityId && m['source'] != 'walk_in';
          })
          .toList();
      if (mine.isEmpty) {
        await _logDeniedScan(
          staff: staff,
          scanType: gateMode,
          vehiclePlate: plate,
          decisionReason: 'Plate lookup: no ticket here.',
        );
        return GateScanResult(
          decision: 'DENIED',
          vehiclePlate: plate,
          scanType: gateMode,
          timestamp: _now(),
          reason: 'No ticket for this plate here.',
        );
      }
      // Prefer a paid ticket. (Not firstWhere/orElse: the snapshot list's
      // runtime element type is a private subclass, which orElse rejects.)
      QueryDocumentSnapshot<Map<String, dynamic>> chosen = mine.first;
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in mine) {
        if (_status(d.data()) == 'paid') {
          chosen = d;
          break;
        }
      }
      if (_status(chosen.data()) != 'paid') {
        await _logDeniedScan(
          staff: staff,
          scanType: gateMode,
          vehiclePlate: plate,
          decisionReason: 'Plate lookup: ticket unpaid.',
          transactionId: chosen.id,
        );
        return GateScanResult(
          decision: 'DENIED',
          vehiclePlate: plate,
          scanType: gateMode,
          timestamp: _now(),
          transactionId: chosen.id,
          reason: 'Ticket for plate is unpaid.',
        );
      }
      return await _verifyTicket(
        staff: staff,
        facilityId: facilityId,
        gateMode: gateMode,
        transactionId: chosen.id,
        payloadPlate: plate,
      );
    } catch (error, stack) {
      reportError(error, stack, reason: 'Plate lookup failed');
      return GateScanResult(
        decision: 'ERROR',
        vehiclePlate: plate,
        scanType: gateMode,
        timestamp: _now(),
        reason: 'Lookup failed. Retry.',
      );
    }
  }

  Future<GateScanResult?> _verifyTicket({
    required GateStaff staff,
    required String facilityId,
    required String gateMode,
    required String transactionId,
    required String payloadPlate,
  }) async {
    final String ticketKey = '$gateMode|$transactionId';
    final DateTime now = _now();
    if (_lastProcessedTicketKey == ticketKey &&
        _lastProcessedAt != null &&
        now.difference(_lastProcessedAt!) < rescanCooldown) {
      return null;
    }
    try {
      DocumentSnapshot<Map<String, dynamic>>? snap;
      try {
        snap = await _db.collection('transactions').doc(transactionId).get();
      } on FirebaseException catch (error) {
        // Staff may only read their own facility's tickets, so a ticket from
        // another facility (or a made-up id) is denied rather than returned.
        if (error.code != 'permission-denied') rethrow;
        snap = null;
      }
      if (snap == null || !snap.exists) {
        return _deny(
          staff: staff,
          scanType: gateMode,
          plate: payloadPlate,
          transactionId: transactionId,
          timestamp: now,
          logReason: 'Ticket does not exist.',
          reason: 'Ticket not found for this facility.',
        );
      }
      final Map<String, dynamic> ticket = snap.data() ?? <String, dynamic>{};
      final String status = _status(ticket);
      final String ticketPlate =
          ((ticket['vehiclePlate'] as String?) ?? payloadPlate).trim();
      final String plate = ticketPlate.isEmpty ? '--' : ticketPlate;
      if (_ticketFacility(ticket) != facilityId) {
        return _deny(
          staff: staff,
          scanType: gateMode,
          plate: plate,
          transactionId: transactionId,
          timestamp: now,
          logReason: 'Ticket belongs to another facility.',
          reason: 'Ticket issued for another facility.',
        );
      }
      if (status != 'paid') {
        return _deny(
          staff: staff,
          scanType: gateMode,
          plate: plate,
          transactionId: transactionId,
          timestamp: now,
          logReason: 'Ticket not paid ($status).',
          reason: 'Payment not confirmed.',
        );
      }
      final GateScanResult result = gateMode == 'entry'
          ? await _processEntryScan(
              staff: staff,
              facilityId: facilityId,
              transactionId: transactionId,
              plate: plate,
              ticket: ticket,
              scannedAt: now,
            )
          : await _processExitScan(
              staff: staff,
              facilityId: facilityId,
              transactionId: transactionId,
              plate: plate,
              ticket: ticket,
              scannedAt: now,
            );
      if (result.isAllowed) {
        _lastProcessedTicketKey = ticketKey;
        _lastProcessedAt = now;
      }
      return result;
    } catch (error, stack) {
      reportError(error, stack, reason: 'Gate scan verification failed');
      return GateScanResult(
        decision: 'ERROR',
        vehiclePlate: '--',
        scanType: gateMode,
        timestamp: now,
        transactionId: transactionId,
        reason: 'Verification failed. Retry.',
      );
    }
  }

  Future<GateScanResult> _processEntryScan({
    required GateStaff staff,
    required String facilityId,
    required String transactionId,
    required String plate,
    required Map<String, dynamic> ticket,
    required DateTime scannedAt,
  }) async {
    final String entryStatus = _entryStatus(ticket);
    if (entryStatus == 'checked_in' || entryStatus == 'inside') {
      return _deny(
        staff: staff,
        scanType: 'entry',
        plate: plate,
        transactionId: transactionId,
        timestamp: scannedAt,
        logReason: 'Ticket already checked in.',
        reason: 'Already inside. Do not admit twice.',
      );
    }
    if (entryStatus == 'checked_out' || entryStatus == 'exited') {
      return _deny(
        staff: staff,
        scanType: 'entry',
        plate: plate,
        transactionId: transactionId,
        timestamp: scannedAt,
        logReason: 'Ticket already used.',
        reason: 'Ticket already completed a stay.',
      );
    }
    final DocumentReference<Map<String, dynamic>> ticketRef = _db
        .collection('transactions')
        .doc(transactionId);
    final DocumentReference<Map<String, dynamic>> logRef = _db
        .collection('activity_logs')
        .doc();
    final WriteBatch batch = _db.batch();
    batch.set(ticketRef, <String, dynamic>{
      'entryStatus': 'checked_in',
      'entryAt': FieldValue.serverTimestamp(),
      'entryStaffId': staff.staffId,
      'entryLogId': logRef.id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(logRef, <String, dynamic>{
      ..._logBase(staff, facilityId, plate, 'entry'),
      'status': 'ALLOWED',
      'decision': 'ALLOWED',
      'decisionReason': 'Paid ticket verified for this facility.',
      'isActive': true,
      'transactionId': transactionId,
    });
    await batch.commit();
    await _logStaffAction(
      staff: staff,
      action: 'scan_entry',
      transactionId: transactionId,
      activityLogId: logRef.id,
      vehiclePlate: plate,
    );
    return GateScanResult(
      decision: 'ALLOWED',
      vehiclePlate: plate,
      scanType: 'entry',
      timestamp: scannedAt,
      transactionId: transactionId,
      reason: 'Paid ticket verified. Admit vehicle.',
    );
  }

  Future<GateScanResult> _processExitScan({
    required GateStaff staff,
    required String facilityId,
    required String transactionId,
    required String plate,
    required Map<String, dynamic> ticket,
    required DateTime scannedAt,
  }) async {
    final String entryStatus = _entryStatus(ticket);
    if (entryStatus == 'checked_out' || entryStatus == 'exited') {
      return _deny(
        staff: staff,
        scanType: 'exit',
        plate: plate,
        transactionId: transactionId,
        timestamp: scannedAt,
        logReason: 'Ticket already checked out.',
        reason: 'Already exited.',
      );
    }
    final DateTime? entryAt =
        _parseTimestamp(ticket['entryAt']) ??
        _parseTimestamp(ticket['createdAt']);
    if ((entryStatus != 'checked_in' && entryStatus != 'inside') &&
        entryAt == null) {
      return _deny(
        staff: staff,
        scanType: 'exit',
        plate: plate,
        transactionId: transactionId,
        timestamp: scannedAt,
        logReason: 'No recorded entry scan.',
        reason: 'No entry on record. Verify first.',
      );
    }

    final DateTime entryTime = entryAt ?? scannedAt;
    Duration elapsed = scannedAt.difference(entryTime);
    if (elapsed.isNegative) {
      elapsed = Duration.zero;
    }
    final Map<String, dynamic>? rates = await _loadRates(facilityId);

    final String vType = ((ticket['vehicleType'] as String?) ?? 'car')
        .trim()
        .toLowerCase();
    final double? rate = resolveOvertimeRate(rates, vType);
    // Overtime starts after the time the driver paid for, not always
    // after the base stay.
    final int includedHours = includedStayHours(
      plan: ((ticket['plan'] as String?) ?? 'base').trim().toLowerCase(),
      duration: ticketDuration(ticket),
    );
    final int extraHours = overtimeHours(elapsed, includedHours);
    final double amount = rate == null ? 0 : extraHours * rate;
    final bool cashDue = extraHours > 0 && amount > 0;
    final String oStatus = extraHours <= 0
        ? kOvertimeNone
        : (cashDue ? kOvertimeCashDue : kOvertimeRateUnresolved);
    final DocumentReference<Map<String, dynamic>> ticketRef = _db
        .collection('transactions')
        .doc(transactionId);
    final DocumentReference<Map<String, dynamic>> exitRef = _db
        .collection('activity_logs')
        .doc();
    final QueryDocumentSnapshot<Map<String, dynamic>>? openEntry =
        await _findOpenEntry(facilityId, transactionId);
    final WriteBatch batch = _db.batch();
    batch.set(ticketRef, <String, dynamic>{
      'entryStatus': 'checked_out',
      'exitAt': FieldValue.serverTimestamp(),
      'exitStaffId': staff.staffId,
      'exitLogId': exitRef.id,
      'staySeconds': elapsed.inSeconds,
      'overtimeHours': extraHours,
      'overtimeRate': rate,
      'overtimeAmount': amount,
      'overtimeStatus': oStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(exitRef, <String, dynamic>{
      ..._logBase(staff, facilityId, plate, 'exit'),
      'status': 'ALLOWED',
      'decision': 'ALLOWED',
      'decisionReason': extraHours <= 0
          ? 'Within paid time.'
          : (cashDue ? 'Overtime: collect cash.' : 'Overtime: rate missing.'),
      'isActive': false,
      'transactionId': transactionId,
      'elapsedSeconds': elapsed.inSeconds,
      'billableHours': includedHours + extraHours,
      'overtimeHours': extraHours,
      'overtimeRate': rate,
      'overtimeAmount': amount,
      'overtimeStatus': oStatus,
    });
    if (openEntry != null) {
      batch.set(openEntry.reference, <String, dynamic>{
        'isActive': false,
        'exitAt': FieldValue.serverTimestamp(),
        'exitLogId': exitRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
    await _logStaffAction(
      staff: staff,
      action: 'scan_exit',
      transactionId: transactionId,
      activityLogId: exitRef.id,
      vehiclePlate: plate,
    );
    return GateScanResult(
      decision: 'ALLOWED',
      vehiclePlate: plate,
      scanType: 'exit',
      timestamp: scannedAt,
      transactionId: transactionId,
      elapsed: elapsed,
      billableHours: includedHours + extraHours,
      overtimeHours: extraHours.toDouble(),
      overtimeAmount: amount,
      activityLogId: exitRef.id,
      reason: extraHours <= 0
          ? 'Within paid time. Release.'
          : (cashDue ? 'Overtime: collect cash first.' : 'Overtime: confirm.'),
    );
  }

  /// Records that [staff] took the overtime cash for [transactionId], on the
  /// ticket and its exit log, so the owner can tell collected cash from cash
  /// still owed. [exitLogId] defaults to the one stored on the ticket.
  Future<void> markOvertimeCollected({
    required GateStaff staff,
    required String transactionId,
    String? exitLogId,
  }) async {
    final DocumentReference<Map<String, dynamic>> ticketRef = _db
        .collection('transactions')
        .doc(transactionId);
    final Map<String, dynamic> ticket =
        (await ticketRef.get()).data() ?? <String, dynamic>{};
    final String status = ((ticket['overtimeStatus'] as String?) ?? '')
        .toLowerCase();
    if (status == kOvertimeCollected) return;
    if (status != kOvertimeCashDue) {
      throw StateError('No overtime cash is due on this ticket.');
    }
    final String logId = (exitLogId ?? (ticket['exitLogId'] as String?) ?? '')
        .trim();
    final Map<String, dynamic> collected = <String, dynamic>{
      'overtimeStatus': kOvertimeCollected,
      'overtimeCollectedBy': staff.staffId,
      'overtimeCollectedAt': FieldValue.serverTimestamp(),
    };
    final WriteBatch batch = _db.batch();
    batch.set(ticketRef, <String, dynamic>{
      ...collected,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (logId.isNotEmpty) {
      batch.set(
        _db.collection('activity_logs').doc(logId),
        collected,
        SetOptions(merge: true),
      );
    }
    await batch.commit();
    await _logStaffAction(
      staff: staff,
      action: 'overtime_collected',
      transactionId: transactionId,
      activityLogId: logId,
      vehiclePlate: ticket['vehiclePlate'] as String?,
    );
  }

  Future<Map<String, dynamic>?> _loadRates(String facilityId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> details = await _db
          .collection('establishment_details')
          .doc(facilityId)
          .get();
      final dynamic raw = details.data()?['rates'];
      if (raw is Map) {
        return raw.map<String, dynamic>(
          (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v),
        );
      }
    } catch (error, stack) {
      reportError(
        error,
        stack,
        reason: 'Loading facility rates for exit scan failed',
      );
    }
    return null;
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findOpenEntry(
    String facilityId,
    String transactionId,
  ) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> q = await _db
          .collection('activity_logs')
          .where('establishmentID', isEqualTo: facilityId)
          .where('transactionId', isEqualTo: transactionId)
          .where('scanType', isEqualTo: 'entry')
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      return q.docs.isEmpty ? null : q.docs.first;
    } catch (error, stack) {
      reportError(error, stack, reason: 'Looking up open entry log failed');
      return null;
    }
  }

  /// Logs a denied scan and returns the matching result for the staff member.
  Future<GateScanResult> _deny({
    required GateStaff staff,
    required String scanType,
    required String plate,
    required String transactionId,
    required DateTime timestamp,
    required String logReason,
    required String reason,
  }) async {
    await _logDeniedScan(
      staff: staff,
      scanType: scanType,
      vehiclePlate: plate,
      decisionReason: logReason,
      transactionId: transactionId,
    );
    return GateScanResult(
      decision: 'DENIED',
      vehiclePlate: plate,
      scanType: scanType,
      timestamp: timestamp,
      transactionId: transactionId,
      reason: reason,
    );
  }

  Map<String, dynamic> _logBase(
    GateStaff staff,
    String facilityId,
    String plate,
    String scanType,
  ) {
    return <String, dynamic>{
      'establishmentID': facilityId,
      'facilityId': facilityId,
      'ownerId': staff.ownerId,
      'staffId': staff.staffId,
      'staffEmail': staff.email.trim(),
      if (staff.name.trim().isNotEmpty) 'staffName': staff.name.trim(),
      'vehiclePlate': plate,
      'scanType': scanType,
      'gateMode': scanType,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Future<String?> _logDeniedScan({
    required GateStaff staff,
    required String scanType,
    required String vehiclePlate,
    required String decisionReason,
    String? transactionId,
  }) async {
    final String? facilityId = staff.facilityId;
    if (facilityId == null) {
      return null;
    }
    final DocumentReference<Map<String, dynamic>> logRef = await _db
        .collection('activity_logs')
        .add(<String, dynamic>{
          ..._logBase(staff, facilityId, vehiclePlate, scanType),
          'status': 'DENIED',
          'decision': 'DENIED',
          'decisionReason': decisionReason,
          'isActive': false,
          if (transactionId != null && transactionId.isNotEmpty)
            'transactionId': transactionId,
        });
    await _logStaffAction(
      staff: staff,
      action: 'scan_$scanType',
      transactionId: transactionId ?? logRef.id,
      activityLogId: logRef.id,
      vehiclePlate: vehiclePlate,
    );
    return logRef.id;
  }

  Future<void> _logStaffAction({
    required GateStaff staff,
    required String action,
    required String transactionId,
    String? activityLogId,
    String? vehiclePlate,
  }) async {
    await _db.collection('StaffActivityLogs').add(<String, dynamic>{
      'staffID': staff.staffId,
      'ownerId': staff.ownerId,
      'establishmentID': staff.facilityId,
      'facilityId': staff.facilityId,
      'action': action,
      'date': FieldValue.serverTimestamp(),
      'transactionId': transactionId,
      if (activityLogId != null && activityLogId.isNotEmpty)
        'activityLogId': activityLogId,
      if (vehiclePlate != null && vehiclePlate.isNotEmpty)
        'vehiclePlate': vehiclePlate,
    });
  }

  static String _status(Map<String, dynamic> ticket) =>
      ((ticket['status'] as String?) ?? '').toLowerCase();

  static String _entryStatus(Map<String, dynamic> ticket) =>
      ((ticket['entryStatus'] as String?) ?? '').toLowerCase();

  static String _ticketFacility(Map<String, dynamic> ticket) =>
      ((ticket['establishmentId'] as String?) ??
              (ticket['establishmentID'] as String?) ??
              '')
          .trim();

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }
}
