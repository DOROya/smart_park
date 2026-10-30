import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../services/facility_status.dart';
import '../../../services/parking_pricing.dart';
import '../../../services/ticket_plate.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../widgets/smartpark_ui.dart';
import '../../../widgets/sp_loading.dart';
import '../../../widgets/sp_overtime.dart';
import '../../../widgets/sp_vehicle_type.dart';

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
  if (entry == 'checked_in' || entry == 'inside') {
    return _TicketState.parked;
  }
  // Tickets are reusable until their hours run out.
  return ticketHoursLeft(data) > 0
      ? _TicketState.ready
      : _TicketState.completed;
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
      AppTheme.textMuted,
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
      return Center(
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

            // Only tickets with time left can be invalidated by their
            // facility being pulled, so only those facilities are watched.
            final List<String> facilityIds = <String>{
              for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                  in tickets)
                if (_hasTimeLeft(_ticketState(doc.data())))
                  _ticketFacilityId(doc.data()),
            }.where((String id) => id.isNotEmpty).toList()..sort();

            return StreamBuilder<Map<String, Map<String, dynamic>>>(
              stream: facilityIds.isEmpty
                  ? null
                  : cachedStream(
                      'facility_details_${facilityIds.join(',')}',
                      () => _facilityDetailsStream(facilityIds),
                    ),
              builder: (BuildContext context, facilitySnapshot) => _buildList(
                snapshot,
                tickets,
                facilitySnapshot.data ?? const <String, Map<String, dynamic>>{},
              ),
            );
          },
    );
  }

  Widget _buildList(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets,
    Map<String, Map<String, dynamic>> facilities,
  ) {
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> active =
        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> invalid =
        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> past =
        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in tickets) {
      final _TicketState state = _ticketState(doc.data());
      final bool restricted = isFacilityRestricted(
        facilities[_ticketFacilityId(doc.data())],
      );
      // A vehicle already inside keeps its ticket on top: it still
      // needs the QR to get out.
      if (state == _TicketState.ready && restricted) {
        invalid.add(doc);
      } else if (_hasTimeLeft(state)) {
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
          const Padding(padding: EdgeInsets.all(24), child: SpSkeletonList())
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
              message: 'No active tickets. Your next ticket shows up here.',
            )
          else
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                in active)
              _ActiveTicketCard(
                doc: doc,
                facility: facilities[_ticketFacilityId(doc.data())],
              ),
          if (invalid.isNotEmpty) ...[
            const SizedBox(height: 16),
            SpSectionLabel(
              'Invalid Tickets',
              trailing: SpChip(
                label: '${invalid.length}',
                color: spDeniedColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'These still have parking time, but SmartPark has '
              'pulled their facility. Tap one to see why.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 10),
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                in invalid)
              _InvalidTicketCard(
                doc: doc,
                facility: facilities[_ticketFacilityId(doc.data())],
              ),
          ],
          if (past.isNotEmpty) ...[
            const SizedBox(height: 16),
            const SpSectionLabel('Past Tickets'),
            const SizedBox(height: 8),
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in past)
              _PastTicketRow(doc: doc),
          ],
        ],
      ],
    );
  }
}

bool _hasTimeLeft(_TicketState state) =>
    state == _TicketState.ready || state == _TicketState.parked;

String _ticketFacilityId(Map<String, dynamic> data) =>
    ((data['establishmentId'] as String?) ??
            (data['establishmentID'] as String?) ??
            '')
        .trim();

/// Live `establishment_details` for [ids], keyed by id. Firestore's `whereIn`
/// takes at most 30 values, so larger sets are watched in chunks.
Stream<Map<String, Map<String, dynamic>>> _facilityDetailsStream(
  List<String> ids,
) {
  final Map<String, Map<String, dynamic>> details =
      <String, Map<String, dynamic>>{};
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  subscriptions = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  late final StreamController<Map<String, Map<String, dynamic>>> controller;
  controller = StreamController<Map<String, Map<String, dynamic>>>(
    onListen: () {
      for (int i = 0; i < ids.length; i += 30) {
        final List<String> chunk = ids.sublist(
          i,
          i + 30 > ids.length ? ids.length : i + 30,
        );
        subscriptions.add(
          FirebaseFirestore.instance
              .collection('establishment_details')
              .where(FieldPath.documentId, whereIn: chunk)
              .snapshots()
              .listen((QuerySnapshot<Map<String, dynamic>> snap) {
                details.removeWhere((String id, _) => chunk.contains(id));
                for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                    in snap.docs) {
                  details[doc.id] = doc.data();
                }
                controller.add(Map<String, Map<String, dynamic>>.of(details));
              }, onError: controller.addError),
        );
      }
    },
    onCancel: () async {
      for (final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> s
          in subscriptions) {
        await s.cancel();
      }
      await controller.close();
    },
  );
  return controller.stream;
}

/// How a pulled facility's tickets are explained to the driver.
({String verb, String undo}) _restrictionWording(
  Map<String, dynamic>? facility,
) => facilityStatus(facility) == 'deactivated'
    ? (verb: 'deactivated', undo: 'reactivated')
    : (verb: 'suspended', undo: 'reinstated');

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
  const _ActiveTicketCard({required this.doc, this.facility});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  /// The issuing facility's `establishment_details`, once loaded.
  final Map<String, dynamic>? facility;

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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: spCardBorder),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppTheme.accentLight, AppTheme.accentWarm],
              ),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppTheme.radiusLarge),
              ),
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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state == _TicketState.parked
                            ? enteredAt == null
                                  ? 'Show this QR at the exit'
                                  : 'Parked since '
                                        '${spFormatClockTime(enteredAt)} · '
                                        'show this QR at the exit'
                            : 'Show this QR at the entrance',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
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
                    color: AppTheme.surface,
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
                if (isFacilityRestricted(facility)) ...[
                  _NoticeStrip(
                    icon: Icons.warning_amber_rounded,
                    color: spDeniedColor,
                    background: AppTheme.dangerSoft,
                    text:
                        'SmartPark ${_restrictionWording(facility).verb} this '
                        'facility while you were parked. Show this QR to exit '
                        'as usual, but the ticket can\'t be used to enter '
                        'again until the facility is '
                        '${_restrictionWording(facility).undo}.',
                  ),
                  const SizedBox(height: 12),
                ],
                _TimeLeftPanel(
                  hoursLeft: ticketHoursLeft(data),
                  parkedSince: state == _TicketState.parked ? enteredAt : null,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    border: Border.all(color: spCardBorder),
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  ),
                  child: QrImageView(
                    data: _resolveTicketQrPayload(doc),
                    size: 190,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                SpVehicleTypeBadge(
                  vehicleType: data['vehicleType'],
                  large: true,
                ),
                const SizedBox(height: 8),
                Text(
                  spTicketSharingRule(_vehicleLabel(data)),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppTheme.textSecondary,
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
                // Not while parked: the vehicle inside is the one on the
                // ticket until it exits.
                if (canChangeTicketPlate(data))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _showChangePlateDialog(context, doc),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text(
                        'Change plate',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.accentText,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.isEmpty
                            ? _vehicleLabel(data)
                            : '${_vehicleLabel(data)} · $plan',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    Text(
                      _dateTimeLabel(_issuedAt(data)),
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Ticket #${doc.id}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the driver put the ticket on another plate of the same vehicle type.
Future<void> _showChangePlateDialog(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) async {
  final bool? changed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => _ChangePlateDialog(doc: doc),
  );
  if (changed == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Plate updated.')));
  }
}

class _ChangePlateDialog extends StatefulWidget {
  const _ChangePlateDialog({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  State<_ChangePlateDialog> createState() => _ChangePlateDialogState();
}

class _ChangePlateDialogState extends State<_ChangePlateDialog> {
  late final TextEditingController _plate = TextEditingController(
    text: ((widget.doc.data()['vehiclePlate'] as String?) ?? '').trim(),
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String plate = normalizePlate(_plate.text);
    if (plate.isEmpty || plate.length > kMaxPlateLength) {
      setState(() => _error = 'Enter a plate number.');
      return;
    }
    final String current = normalizePlate(
      (widget.doc.data()['vehiclePlate'] as String?) ?? '',
    );
    if (plate == current) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await changeTicketPlate(transactionId: widget.doc.id, plate: plate);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(
            error,
            fallback:
                'Could not change the plate. It can\'t be changed while the '
                'vehicle is parked.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> data = widget.doc.data();
    return AlertDialog(
      title: const Text('Change plate'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SpVehicleTypeBadge(vehicleType: data['vehicleType']),
              const SizedBox(height: 10),
              Text(
                'Use this ticket for another ${_vehicleLabel(data).toLowerCase()}. '
                'The vehicle type stays the same, and the hours left are '
                'shared by every visit.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _plate,
                enabled: !_saving,
                autofocus: true,
                maxLength: kMaxPlateLength,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'Plate number',
                  hintText: 'ABC 1234',
                  errorText: _error,
                  errorMaxLines: 3,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save plate'),
        ),
      ],
    );
  }
}

/// The parking time a ticket still covers, worded so it can't be read as an
/// expiry date: the hours only run down while the vehicle is parked.
class _TimeLeftPanel extends StatelessWidget {
  const _TimeLeftPanel({required this.hoursLeft, this.parkedSince});

  final int hoursLeft;

  /// When the current visit began; null when the vehicle isn't parked.
  final DateTime? parkedSince;

  @override
  Widget build(BuildContext context) {
    final DateTime? since = parkedSince;
    final DateTime? paidUntil = since?.add(Duration(hours: hoursLeft));
    final String label = since == null
        ? 'Parking time left'
        : 'Parking time left when you entered';
    final String note = paidUntil == null
        ? 'Counts down only while you\'re parked, at least '
              '$spBaseStayHours hours per visit. This is not an expiry date: '
              'reuse this ticket on later visits until the time runs out.'
        : 'Covers you until ${spFormatClockTime(paidUntil)}'
              '${spSameDate(paidUntil, DateTime.now()) ? '' : ', ${spFormatDate(paidUntil)}'}. '
              'Staying longer adds overtime, paid in cash at the exit.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: spCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Icon(
                  Icons.timelapse_rounded,
                  size: 20,
                  color: AppTheme.accentText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatParkingHours(hoursLeft),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  note,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One-line coloured notice with an icon, for warnings inside a card.
class _NoticeStrip extends StatelessWidget {
  const _NoticeStrip({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A ticket that still has time on it but whose facility an admin pulled.
/// Collapsed it says so at a glance; tapping it explains why it is invalid
/// and what happens to the time left. The QR is withheld, since no gate will
/// take it.
class _InvalidTicketCard extends StatefulWidget {
  const _InvalidTicketCard({required this.doc, this.facility});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Map<String, dynamic>? facility;

  @override
  State<_InvalidTicketCard> createState() => _InvalidTicketCardState();
}

class _InvalidTicketCardState extends State<_InvalidTicketCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> data = widget.doc.data();
    final Map<String, dynamic>? facility = widget.facility;
    final String name = ((data['establishmentName'] as String?) ?? '').trim();
    final String facilityName = name.isEmpty ? 'This facility' : name;
    final int hoursLeft = ticketHoursLeft(data);
    final String plate = ((data['vehiclePlate'] as String?) ?? '').trim();
    final String plan = _planLabel(data);
    final (:String verb, :String undo) = _restrictionWording(facility);
    final DateTime? since = spParseDateTime(facility?['reviewedAt']);
    // Only the predefined reason is shown; the admin's free-text note is
    // for the owner.
    // "Other" alone tells the driver nothing.
    final List<String> reasons = facilityRestrictionReasons(
      facility,
    ).where((String r) => r != 'Other').toList();
    final String? reason = reasons.isEmpty ? null : joinReasons(reasons);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: _expanded ? AppTheme.dangerBorder : spCardBorder,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.dangerSoft,
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                        ),
                        child: Icon(
                          Icons.block_rounded,
                          color: spDeniedColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? 'Parking Ticket' : name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                SpChip(label: 'Invalid', color: spDeniedColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Facility $verb',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatParkingHours(hoursLeft),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                          ),
                          Text(
                            'unused',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerSoft,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Why is this ticket invalid?',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$facilityName was $verb by SmartPark'
                            '${since == null ? '' : ' on ${spFormatDate(since)}'}. '
                            'While it is $verb, its gate does not accept '
                            'tickets, so this one can\'t be used to enter.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppTheme.textDark,
                            ),
                          ),
                          if (reason != null) ...[
                            const SizedBox(height: 8),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Reason given: ',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: reason,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                ],
                              ),
                              style: const TextStyle(fontSize: 12, height: 1.4),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'Your ${formatParkingHours(hoursLeft)} of parking '
                            'time stay on the ticket. It becomes valid again '
                            'if the facility is $undo.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (plate.isNotEmpty) SpPlateBadge(plate: plate),
                        Text(
                          plan.isEmpty
                              ? _vehicleLabel(data)
                              : '${_vehicleLabel(data)} · $plan',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bought ${_dateTimeLabel(_issuedAt(data))} · '
                      'Ticket #${widget.doc.id}',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ] else ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 52),
                      child: Text(
                        'Tap to see why',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: spDeniedColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
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
              borderRadius: BorderRadius.circular(AppTheme.radius),
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
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PHP ${amount.toStringAsFixed(2)}',
                      style: TextStyle(
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
                        style: TextStyle(
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
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
                if (overtimeHours > 0 && overtimeAmount > 0) ...[
                  const SizedBox(height: 8),
                  SpOvertimeBreakdown.fromRecord(data, forDriver: true),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
