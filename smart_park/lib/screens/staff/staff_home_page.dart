import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/parking_pricing.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/smartpark_ui.dart';
import '../../services/error_reporter.dart';
import '../auth/sign_in_screen.dart';
import 'walk_in_panel.dart';

part 'staff_home_page_fragments.dart';

class StaffHomePage extends StatefulWidget {
  const StaffHomePage({super.key});

  @override
  State<StaffHomePage> createState() => _StaffHomePageState();
}

/// Result of a single gate scan shown to the staff member.
class _GateScanResult {
  _GateScanResult({
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

  bool get isAllowed => decision == 'ALLOWED';
  bool get isDenied => decision == 'DENIED';
  bool get hasOvertime => (overtimeHours ?? 0) > 0 && (overtimeAmount ?? 0) > 0;
}

class _StaffHomePageState extends State<StaffHomePage>
    with SingleTickerProviderStateMixin, SpStreamCache<StaffHomePage> {
  final PermissionService _permissionService = const PermissionService();

  late Future<DocumentSnapshot<Map<String, dynamic>>> _userFuture;
  late TabController _historyTabController;

  int _selectedNavIndex = 0;
  String _historyFilter = 'all';
  DateTime _selectedHistoryDate = DateTime.now();

  String? _assignedFacilityId;
  String? _ownerId;

  late final MobileScannerController _scannerController;
  bool _isProcessingScan = false;
  _GateScanResult? _lastScanResult;

  /// Staff-side gate direction. Entry/exit is chosen here in the app and is
  /// never taken from the scanned QR content.
  String _gateMode = 'entry';

  /// Guards against re-processing the same ticket while the camera keeps
  /// reporting it.
  String? _lastProcessedTicketKey;
  DateTime? _lastProcessedAt;

  static const Duration _rescanCooldown = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();

    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    _userFuture = FirebaseFirestore.instance.collection('users').doc(uid).get();

    _historyTabController = TabController(length: 4, vsync: this);
    _historyTabController.addListener(() {
      if (_historyTabController.indexIsChanging) {
        return;
      }

      setState(() {
        _historyFilter = switch (_historyTabController.index) {
          0 => 'all',
          1 => 'entry',
          2 => 'exit',
          _ => 'active',
        };
      });
    });

    unawaited(_resolveAssignedFacility());
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _historyTabController.dispose();
    super.dispose();
  }

  Future<void> _resolveAssignedFacility() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final String signedInEmail =
        (FirebaseAuth.instance.currentUser?.email ?? '').trim().toLowerCase();

    final QuerySnapshot<Map<String, dynamic>> staffSnapshot =
        await FirebaseFirestore.instance
            .collection('staff_accounts')
            .where('userId', isEqualTo: uid)
            .limit(1)
            .get();

    if (staffSnapshot.docs.isNotEmpty) {
      final Map<String, dynamic> staffData = staffSnapshot.docs.first.data();
      if (!mounted) {
        return;
      }
      setState(() {
        _assignedFacilityId =
            (staffData['establishmentID'] as String?) ??
            (staffData['facilityId'] as String?);
        _ownerId = staffData['ownerId'] as String?;
      });
      return;
    }

    if (signedInEmail.isNotEmpty) {
      final QuerySnapshot<Map<String, dynamic>> staffByEmail =
          await FirebaseFirestore.instance
              .collection('staff_accounts')
              .where('email', isEqualTo: signedInEmail)
              .limit(1)
              .get();

      if (staffByEmail.docs.isNotEmpty) {
        final Map<String, dynamic> staffData = staffByEmail.docs.first.data();
        if (!mounted) {
          return;
        }
        setState(() {
          _assignedFacilityId =
              (staffData['establishmentID'] as String?) ??
              (staffData['facilityId'] as String?);
          _ownerId = staffData['ownerId'] as String?;
        });
        return;
      }
    }

    final DocumentSnapshot<Map<String, dynamic>> userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (!mounted) {
      return;
    }

    setState(() {
      _assignedFacilityId =
          (userDoc.data()?['establishmentID'] as String?) ??
          (userDoc.data()?['facilityId'] as String?);
      _ownerId = userDoc.data()?['ownerId'] as String?;
    });
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _showChangePasswordDialog() {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) =>
          const _StaffChangePasswordDialog(),
    );
  }

  Future<void> _logStaffAction({
    required String action,
    required String transactionId,
    String? activityLogId,
    String? vehiclePlate,
  }) async {
    final String? staffId = FirebaseAuth.instance.currentUser?.uid;
    if (staffId == null) {
      return;
    }

    await FirebaseFirestore.instance
        .collection('StaffActivityLogs')
        .add(<String, dynamic>{
          'staffID': staffId,
          'ownerId': _ownerId,
          'establishmentID': _assignedFacilityId,
          'facilityId': _assignedFacilityId,
          'action': action,
          'date': FieldValue.serverTimestamp(),
          'transactionId': transactionId,
          if (activityLogId != null && activityLogId.isNotEmpty)
            'activityLogId': activityLogId,
          if (vehiclePlate != null && vehiclePlate.isNotEmpty)
            'vehiclePlate': vehiclePlate,
        });
  }

  void _presentGateResult(_GateScanResult result) {
    if (!mounted) {
      _isProcessingScan = false;
      return;
    }
    setState(() {
      _lastScanResult = result;
    });
    _isProcessingScan = false;
  }

  DateTime? _parseActivityTimestamp(dynamic value) {
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

  void _onBarcodeDetect(BarcodeCapture capture) {
    final String raw = capture.barcodes.isEmpty
        ? ''
        : (capture.barcodes.first.rawValue ?? '').trim();
    if (raw.isEmpty || _isProcessingScan) {
      return;
    }

    _isProcessingScan = true;
    unawaited(_handleScanPayload(raw));
  }

  Future<String?> _logDeniedScan({
    required String scanType,
    required String vehiclePlate,
    required String decisionReason,
    String? transactionId,
  }) async {
    final String? staffId = FirebaseAuth.instance.currentUser?.uid;
    if (staffId == null || _assignedFacilityId == null) {
      return null;
    }
    final DocumentReference<Map<String, dynamic>> logRef =
        await FirebaseFirestore.instance
            .collection('activity_logs')
            .add(<String, dynamic>{
              'establishmentID': _assignedFacilityId,
              'facilityId': _assignedFacilityId,
              'ownerId': _ownerId,
              'staffId': staffId,
              'staffEmail': (FirebaseAuth.instance.currentUser?.email ?? '')
                  .trim(),
              'vehiclePlate': vehiclePlate,
              'scanType': scanType,
              'gateMode': scanType,
              'status': 'DENIED',
              'decision': 'DENIED',
              'decisionReason': decisionReason,
              'timestamp': FieldValue.serverTimestamp(),
              'createdAt': FieldValue.serverTimestamp(),
              'isActive': false,
              if (transactionId != null && transactionId.isNotEmpty)
                'transactionId': transactionId,
            });
    await _logStaffAction(
      action: 'scan_$scanType',
      transactionId: transactionId ?? logRef.id,
      activityLogId: logRef.id,
      vehiclePlate: vehiclePlate,
    );
    return logRef.id;
  }

  Future<void> _handleScanPayload(String rawPayload) async {
    final String? staffId = FirebaseAuth.instance.currentUser?.uid;
    if (staffId == null) {
      _isProcessingScan = false;
      return;
    }
    final String? facilityId = _assignedFacilityId;
    if (facilityId == null || facilityId.isEmpty) {
      _presentGateResult(
        _GateScanResult(
          decision: 'DENIED',
          vehiclePlate: '--',
          scanType: _gateMode,
          timestamp: DateTime.now(),
          reason: 'Staff is not assigned to a facility yet.',
        ),
      );
      return;
    }
    Map<String, dynamic>? payload;
    try {
      final dynamic decoded = jsonDecode(rawPayload);
      if (decoded is Map) {
        payload = decoded.map<String, dynamic>(
          (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v),
        );
      }
    } catch (_) {
      payload = null;
    }
    if (payload == null) {
      await _logDeniedScan(
        scanType: _gateMode,
        vehiclePlate: 'unreadable',
        decisionReason: 'QR is not a SmartPark ticket.',
      );
      _presentGateResult(
        _GateScanResult(
          decision: 'DENIED',
          vehiclePlate: '--',
          scanType: _gateMode,
          timestamp: DateTime.now(),
          reason: 'Not a SmartPark ticket QR.',
        ),
      );
      return;
    }
    final String txId = ((payload['transactionId'] as String?) ?? '').trim();
    final String pPlate = ((payload['vehiclePlate'] as String?) ?? '--').trim();
    if (txId.isEmpty) {
      await _logDeniedScan(
        scanType: _gateMode,
        vehiclePlate: pPlate,
        decisionReason: 'Ticket payload missing transaction id.',
      );
      _presentGateResult(
        _GateScanResult(
          decision: 'DENIED',
          vehiclePlate: pPlate,
          scanType: _gateMode,
          timestamp: DateTime.now(),
          reason: 'Ticket is unreadable. Use plate lookup.',
        ),
      );
      return;
    }
    final String ticketKey = '$_gateMode|$txId';
    final DateTime now = DateTime.now();
    if (_lastProcessedTicketKey == ticketKey &&
        _lastProcessedAt != null &&
        now.difference(_lastProcessedAt!) < _rescanCooldown) {
      _isProcessingScan = false;
      return;
    }
    try {
      DocumentSnapshot<Map<String, dynamic>>? snap;
      try {
        snap = await FirebaseFirestore.instance
            .collection('transactions')
            .doc(txId)
            .get();
      } on FirebaseException catch (error) {
        // Staff may only read their own facility's tickets, so a ticket from
        // another facility (or a made-up id) is denied rather than returned.
        if (error.code != 'permission-denied') rethrow;
        snap = null;
      }
      if (snap == null || !snap.exists) {
        await _logDeniedScan(
          scanType: _gateMode,
          vehiclePlate: pPlate,
          decisionReason: 'Ticket does not exist.',
          transactionId: txId,
        );
        _presentGateResult(
          _GateScanResult(
            decision: 'DENIED',
            vehiclePlate: pPlate,
            scanType: _gateMode,
            timestamp: now,
            transactionId: txId,
            reason: 'Ticket not found for this facility.',
          ),
        );
        return;
      }
      final Map<String, dynamic> ticket = snap.data() ?? <String, dynamic>{};
      final String status = ((ticket['status'] as String?) ?? '').toLowerCase();
      final String tFac =
          ((ticket['establishmentId'] as String?) ??
                  (ticket['establishmentID'] as String?) ??
                  '')
              .trim();
      final String plate =
          (((ticket['vehiclePlate'] as String?) ?? pPlate)).trim().isEmpty
          ? '--'
          : (((ticket['vehiclePlate'] as String?) ?? pPlate)).trim();
      if (tFac != facilityId) {
        await _logDeniedScan(
          scanType: _gateMode,
          vehiclePlate: plate,
          decisionReason: 'Ticket belongs to another facility.',
          transactionId: txId,
        );
        _presentGateResult(
          _GateScanResult(
            decision: 'DENIED',
            vehiclePlate: plate,
            scanType: _gateMode,
            timestamp: now,
            transactionId: txId,
            reason: 'Ticket issued for another facility.',
          ),
        );
        return;
      }
      if (status != 'paid') {
        await _logDeniedScan(
          scanType: _gateMode,
          vehiclePlate: plate,
          decisionReason: 'Ticket not paid ($status).',
          transactionId: txId,
        );
        _presentGateResult(
          _GateScanResult(
            decision: 'DENIED',
            vehiclePlate: plate,
            scanType: _gateMode,
            timestamp: now,
            transactionId: txId,
            reason: 'Payment not confirmed.',
          ),
        );
        return;
      }
      if (_gateMode == 'entry') {
        await _processEntryScan(
          staffId: staffId,
          facilityId: facilityId,
          transactionId: txId,
          plate: plate,
          ticket: ticket,
          ticketKey: ticketKey,
          scannedAt: now,
        );
      } else {
        await _processExitScan(
          staffId: staffId,
          facilityId: facilityId,
          transactionId: txId,
          plate: plate,
          ticket: ticket,
          ticketKey: ticketKey,
          scannedAt: now,
        );
      }
    } catch (error, stack) {
      reportError(error, stack, reason: 'Gate scan verification failed');
      _presentGateResult(
        _GateScanResult(
          decision: 'ERROR',
          vehiclePlate: '--',
          scanType: _gateMode,
          timestamp: now,
          transactionId: txId,
          reason: 'Verification failed. Retry.',
        ),
      );
    }
  }

  Future<void> _processEntryScan({
    required String staffId,
    required String facilityId,
    required String transactionId,
    required String plate,
    required Map<String, dynamic> ticket,
    required String ticketKey,
    required DateTime scannedAt,
  }) async {
    final String entryStatus = ((ticket['entryStatus'] as String?) ?? '')
        .toLowerCase();
    if (entryStatus == 'checked_in' || entryStatus == 'inside') {
      await _logDeniedScan(
        scanType: 'entry',
        vehiclePlate: plate,
        decisionReason: 'Ticket already checked in.',
        transactionId: transactionId,
      );
      _presentGateResult(
        _GateScanResult(
          decision: 'DENIED',
          vehiclePlate: plate,
          scanType: 'entry',
          timestamp: scannedAt,
          transactionId: transactionId,
          reason: 'Already inside. Do not admit twice.',
        ),
      );
      return;
    }
    if (entryStatus == 'checked_out' || entryStatus == 'exited') {
      await _logDeniedScan(
        scanType: 'entry',
        vehiclePlate: plate,
        decisionReason: 'Ticket already used.',
        transactionId: transactionId,
      );
      _presentGateResult(
        _GateScanResult(
          decision: 'DENIED',
          vehiclePlate: plate,
          scanType: 'entry',
          timestamp: scannedAt,
          transactionId: transactionId,
          reason: 'Ticket already completed a stay.',
        ),
      );
      return;
    }
    final DocumentReference<Map<String, dynamic>> ticketRef = FirebaseFirestore
        .instance
        .collection('transactions')
        .doc(transactionId);
    final DocumentReference<Map<String, dynamic>> logRef = FirebaseFirestore
        .instance
        .collection('activity_logs')
        .doc();
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    batch.set(ticketRef, <String, dynamic>{
      'entryStatus': 'checked_in',
      'entryAt': FieldValue.serverTimestamp(),
      'entryStaffId': staffId,
      'entryLogId': logRef.id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(logRef, <String, dynamic>{
      'establishmentID': facilityId,
      'facilityId': facilityId,
      'ownerId': _ownerId,
      'staffId': staffId,
      'staffEmail': (FirebaseAuth.instance.currentUser?.email ?? '').trim(),
      'vehiclePlate': plate,
      'scanType': 'entry',
      'gateMode': 'entry',
      'status': 'ALLOWED',
      'decision': 'ALLOWED',
      'decisionReason': 'Paid ticket verified for this facility.',
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'isActive': true,
      'transactionId': transactionId,
    });
    await batch.commit();
    _lastProcessedTicketKey = ticketKey;
    _lastProcessedAt = scannedAt;
    await _logStaffAction(
      action: 'scan_entry',
      transactionId: transactionId,
      activityLogId: logRef.id,
      vehiclePlate: plate,
    );
    _presentGateResult(
      _GateScanResult(
        decision: 'ALLOWED',
        vehiclePlate: plate,
        scanType: 'entry',
        timestamp: scannedAt,
        transactionId: transactionId,
        reason: 'Paid ticket verified. Admit vehicle.',
      ),
    );
  }

  Future<void> _processExitScan({
    required String staffId,
    required String facilityId,
    required String transactionId,
    required String plate,
    required Map<String, dynamic> ticket,
    required String ticketKey,
    required DateTime scannedAt,
  }) async {
    final String entryStatus = ((ticket['entryStatus'] as String?) ?? '')
        .toLowerCase();
    if (entryStatus == 'checked_out' || entryStatus == 'exited') {
      await _logDeniedScan(
        scanType: 'exit',
        vehiclePlate: plate,
        decisionReason: 'Ticket already checked out.',
        transactionId: transactionId,
      );
      _presentGateResult(
        _GateScanResult(
          decision: 'DENIED',
          vehiclePlate: plate,
          scanType: 'exit',
          timestamp: scannedAt,
          transactionId: transactionId,
          reason: 'Already exited.',
        ),
      );
      return;
    }
    final DateTime? entryAt =
        _parseActivityTimestamp(ticket['entryAt']) ??
        _parseActivityTimestamp(ticket['createdAt']);
    if ((entryStatus != 'checked_in' && entryStatus != 'inside') &&
        entryAt == null) {
      await _logDeniedScan(
        scanType: 'exit',
        vehiclePlate: plate,
        decisionReason: 'No recorded entry scan.',
        transactionId: transactionId,
      );
      _presentGateResult(
        _GateScanResult(
          decision: 'DENIED',
          vehiclePlate: plate,
          scanType: 'exit',
          timestamp: scannedAt,
          transactionId: transactionId,
          reason: 'No entry on record. Verify first.',
        ),
      );
      return;
    }

    DateTime entryTime = entryAt ?? scannedAt;
    Duration elapsed = scannedAt.difference(entryTime);
    if (elapsed.isNegative) {
      elapsed = Duration.zero;
    }
    Map<String, dynamic>? rates;
    try {
      final DocumentSnapshot<Map<String, dynamic>> details =
          await FirebaseFirestore.instance
              .collection('establishment_details')
              .doc(facilityId)
              .get();
      final dynamic raw = details.data()?['rates'];
      if (raw is Map) {
        rates = raw.map<String, dynamic>(
          (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v),
        );
      }
    } catch (error, stack) {
      reportError(
        error,
        stack,
        reason: 'Loading facility rates for exit scan failed',
      );
      rates = null;
    }

    final String vType = (((ticket['vehicleType'] as String?) ?? 'car'))
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
        ? 'none'
        : (cashDue ? 'cash_due' : 'rate_unresolved');
    final DocumentReference<Map<String, dynamic>> ticketRef = FirebaseFirestore
        .instance
        .collection('transactions')
        .doc(transactionId);
    final DocumentReference<Map<String, dynamic>> exitRef = FirebaseFirestore
        .instance
        .collection('activity_logs')
        .doc();
    QueryDocumentSnapshot<Map<String, dynamic>>? openEntry;
    try {
      final QuerySnapshot<Map<String, dynamic>> q = await FirebaseFirestore
          .instance
          .collection('activity_logs')
          .where('establishmentID', isEqualTo: facilityId)
          .where('transactionId', isEqualTo: transactionId)
          .where('scanType', isEqualTo: 'entry')
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        openEntry = q.docs.first;
      }
    } catch (error, stack) {
      reportError(error, stack, reason: 'Looking up open entry log failed');
      openEntry = null;
    }
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    batch.set(ticketRef, <String, dynamic>{
      'entryStatus': 'checked_out',
      'exitAt': FieldValue.serverTimestamp(),
      'exitStaffId': staffId,
      'exitLogId': exitRef.id,
      'staySeconds': elapsed.inSeconds,
      'overtimeHours': extraHours,
      'overtimeRate': rate,
      'overtimeAmount': amount,
      'overtimeStatus': oStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(exitRef, <String, dynamic>{
      'establishmentID': facilityId,
      'facilityId': facilityId,
      'ownerId': _ownerId,
      'staffId': staffId,
      'staffEmail': (FirebaseAuth.instance.currentUser?.email ?? '').trim(),
      'vehiclePlate': plate,
      'scanType': 'exit',
      'gateMode': 'exit',
      'status': 'ALLOWED',
      'decision': 'ALLOWED',
      'decisionReason': extraHours <= 0
          ? 'Within paid time.'
          : (cashDue ? 'Overtime: collect cash.' : 'Overtime: rate missing.'),
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
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
    _lastProcessedTicketKey = ticketKey;
    _lastProcessedAt = scannedAt;
    await _logStaffAction(
      action: 'scan_exit',
      transactionId: transactionId,
      activityLogId: exitRef.id,
      vehiclePlate: plate,
    );
    _presentGateResult(
      _GateScanResult(
        decision: 'ALLOWED',
        vehiclePlate: plate,
        scanType: 'exit',
        timestamp: scannedAt,
        transactionId: transactionId,
        elapsed: elapsed,
        billableHours: includedHours + extraHours,
        overtimeHours: extraHours.toDouble(),
        overtimeAmount: amount,
        reason: extraHours <= 0
            ? 'Within 2-hour base. Release.'
            : (cashDue
                  ? 'Overtime: collect cash first.'
                  : 'Overtime: confirm.'),
      ),
    );
  }

  Future<void> _lookupByPlate(String rawPlate) async {
    final String plate = rawPlate.trim();
    if (plate.isEmpty) {
      _presentGateResult(
        _GateScanResult(
          decision: 'ERROR',
          vehiclePlate: '--',
          scanType: _gateMode,
          timestamp: DateTime.now(),
          reason: 'Type the plate before lookup.',
        ),
      );
      return;
    }
    final String? facilityId = _assignedFacilityId;
    if (facilityId == null || facilityId.isEmpty) {
      _presentGateResult(
        _GateScanResult(
          decision: 'DENIED',
          vehiclePlate: plate,
          scanType: _gateMode,
          timestamp: DateTime.now(),
          reason: 'Staff not assigned to a facility.',
        ),
      );
      return;
    }
    _isProcessingScan = true;
    try {
      final QuerySnapshot<Map<String, dynamic>> matches =
          await FirebaseFirestore.instance
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
            final String f =
                ((m['establishmentId'] as String?) ??
                        (m['establishmentID'] as String?) ??
                        '')
                    .trim();
            // Walk-ins are checked out from the Walk-ins panel instead.
            return f == facilityId && m['source'] != 'walk_in';
          })
          .toList();
      if (mine.isEmpty) {
        await _logDeniedScan(
          scanType: _gateMode,
          vehiclePlate: plate,
          decisionReason: 'Plate lookup: no ticket here.',
        );
        _presentGateResult(
          _GateScanResult(
            decision: 'DENIED',
            vehiclePlate: plate,
            scanType: _gateMode,
            timestamp: DateTime.now(),
            reason: 'No ticket for this plate here.',
          ),
        );
        return;
      }
      QueryDocumentSnapshot<Map<String, dynamic>>? chosen;
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in mine) {
        if (((d.data()['status'] as String?) ?? '').toLowerCase() == 'paid') {
          chosen = d;
          break;
        }
      }
      chosen ??= mine.first;
      if (((chosen.data()['status'] as String?) ?? '').toLowerCase() !=
          'paid') {
        await _logDeniedScan(
          scanType: _gateMode,
          vehiclePlate: plate,
          decisionReason: 'Plate lookup: ticket unpaid.',
          transactionId: chosen.id,
        );
        _presentGateResult(
          _GateScanResult(
            decision: 'DENIED',
            vehiclePlate: plate,
            scanType: _gateMode,
            timestamp: DateTime.now(),
            transactionId: chosen.id,
            reason: 'Ticket for plate is unpaid.',
          ),
        );
        return;
      }
      await _handleScanPayload(
        jsonEncode(<String, dynamic>{
          'transactionId': chosen.id,
          'vehiclePlate': plate,
        }),
      );
    } catch (error, stack) {
      reportError(error, stack, reason: 'Plate lookup failed');
      _presentGateResult(
        _GateScanResult(
          decision: 'ERROR',
          vehiclePlate: plate,
          scanType: _gateMode,
          timestamp: DateTime.now(),
          reason: 'Lookup failed. Retry.',
        ),
      );
    }
  }

  Future<void> _pickHistoryDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedHistoryDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _selectedHistoryDate = picked;
    });
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _matchesHistoryFilter(Map<String, dynamic> data) {
    if (_historyFilter == 'all') {
      return true;
    }

    final String scanType = ((data['scanType'] as String?) ?? '').toLowerCase();
    final bool isActive = (data['isActive'] as bool?) ?? false;

    if (_historyFilter == 'entry') {
      return scanType == 'entry';
    }
    if (_historyFilter == 'exit') {
      return scanType == 'exit';
    }
    return isActive;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _userFuture,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
          ) {
            final Map<String, dynamic> userData =
                snapshot.data?.data() ??
                <String, dynamic>{'firstName': 'Staff', 'role': 'Guard'};

            return Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                title: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_parking_rounded, color: AppTheme.textDark),
                    SizedBox(width: 8),
                    Text(
                      'SmartPark',
                      style: TextStyle(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    onPressed: _showChangePasswordDialog,
                    icon: const Icon(Icons.settings_rounded),
                    tooltip: 'Change Password',
                  ),
                  IconButton(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout_rounded),
                    tooltip: 'Sign Out',
                  ),
                ],
              ),
              body: _buildBody(userData),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _selectedNavIndex,
                selectedItemColor: const Color(0xFF22252C),
                unselectedItemColor: const Color(0xFF6C727F),
                showSelectedLabels: true,
                showUnselectedLabels: true,
                type: BottomNavigationBarType.fixed,
                selectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                onTap: (int index) {
                  setState(() {
                    _selectedNavIndex = index;
                  });
                },
                items: [
                  _navItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
                  _navItem(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'QR Scanning',
                    emphasized: true,
                  ),
                  _navItem(icon: Icons.history_rounded, label: 'History'),
                ],
              ),
            );
          },
    );
  }
}

/// Lets a signed-in staff member change their own password. Firebase
/// requires a recent sign-in before `updatePassword`, so the current
/// password is re-collected here and used to reauthenticate first.
class _StaffChangePasswordDialog extends StatefulWidget {
  const _StaffChangePasswordDialog();

  @override
  State<_StaffChangePasswordDialog> createState() =>
      _StaffChangePasswordDialogState();
}

class _StaffChangePasswordDialogState
    extends State<_StaffChangePasswordDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateNewPassword(String? value) {
    final String password = value ?? '';
    if (password.length < 8) {
      return 'At least 8 characters.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Include an uppercase letter.';
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Include a number.';
    }
    return null;
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    required bool obscured,
    required VoidCallback onToggleObscure,
  }) {
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppTheme.border),
    );
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF8F9FC),
      prefixIcon: Icon(icon, color: AppTheme.textMuted, size: 20),
      suffixIcon: IconButton(
        icon: Icon(
          obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          color: AppTheme.textMuted,
          size: 20,
        ),
        onPressed: onToggleObscure,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'New passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('No signed-in staff account found.');
      }

      await user.updatePassword(_newPasswordController.text);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));
    } on FirebaseAuthException catch (error) {
      setState(() {
        _errorMessage = error.code == 'requires-recent-login'
            ? 'For security, please sign out and sign back in, then try again.'
            : (error.message ?? 'Unable to update password.');
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.lock_reset_rounded,
                    color: Color(0xFF9A7B12),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Change Password',
                  style: TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Set a new password for your staff account.',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDECEC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF3C6C6)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFB3261E),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNew,
                  decoration: _fieldDecoration(
                    label: 'New Password',
                    icon: Icons.lock_outline_rounded,
                    obscured: _obscureNew,
                    onToggleObscure: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                  validator: _validateNewPassword,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  decoration: _fieldDecoration(
                    label: 'Confirm New Password',
                    icon: Icons.lock_outline_rounded,
                    obscured: _obscureConfirm,
                    onToggleObscure: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (value) =>
                      (value == null || value.isEmpty) ? 'Required.' : null,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F4F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E7EF)),
                  ),
                  child: const Text(
                    'Password should be at least 8 characters with one uppercase letter and one number.',
                    style: TextStyle(
                      color: Color(0xFF596173),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textDark,
                          side: const BorderSide(color: AppTheme.border),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: const Color(0xFF22252C),
                          minimumSize: const Size.fromHeight(46),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF22252C),
                                ),
                              )
                            : const Text(
                                'Update',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
