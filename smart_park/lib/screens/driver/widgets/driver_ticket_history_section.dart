import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../widgets/sp_facility_contact.dart';
import '../../../services/app_shortcuts.dart'
    show savedTicketFrom, ticketQrPayload;
import '../../../services/facility_status.dart';
import '../../../services/last_ticket_store.dart';
import '../../../content/terms_content.dart' show kSupportEmail;
import '../../../widgets/sp_facility_report.dart';
import '../../../services/parking_pricing.dart';
import '../../../services/parking_refunds.dart';
import '../../../services/platform_fees.dart'
    show commissionPercent, saleCommissionRate;
import '../../../services/parking_receipt.dart';
import '../../../services/ticket_plate.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../widgets/smartpark_ui.dart';
import '../../../widgets/sp_dialog.dart';
import '../../../widgets/sp_loading.dart';
import '../../../widgets/sp_max_brightness.dart'
    show SpMaxBrightness, kTicketQrEyeStyle, kTicketQrModuleStyle;
import '../../../widgets/sp_overtime.dart';
import '../../../widgets/sp_receipt_button.dart';
import '../../../widgets/sp_save_qr_button.dart';
import '../../../widgets/sp_ticket_cost.dart' show spPackageParts;
import '../../../widgets/sp_vehicle_type.dart';
import '../driver_parking_pass_page.dart';
import '../driver_transaction_history_page.dart';
import 'add_hours_sheet.dart';
import 'rate_facility.dart';

/// The QR a ticket shows (see [ticketQrPayload]).
String _resolveTicketQrPayload(
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) => ticketQrPayload(doc.id, doc.data());

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
            // So the offline note clears once the server answers again.
            .snapshots(includeMetadataChanges: true),
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
              builder: (BuildContext context, facilitySnapshot) =>
                  // Refunds for tickets at facilities SmartPark pulled.
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: cachedStream(
                      'refunds_$uid',
                      () => FirebaseFirestore.instance
                          .collection('refunds')
                          .where('driverId', isEqualTo: uid)
                          .snapshots(),
                    ),
                    builder: (BuildContext context, refundSnapshot) =>
                        _buildList(
                          snapshot,
                          tickets,
                          facilitySnapshot.data ??
                              const <String, Map<String, dynamic>>{},
                          refundsByTicket(refundSnapshot.data),
                        ),
                  ),
            );
          },
    );
  }

  Widget _buildList(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets,
    Map<String, Map<String, dynamic>> facilities,
    Map<String, ParkingRefund> refunds,
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

    // Kept on this phone so "Show my ticket" opens it with no signal: the
    // one parked first, else the newest with hours left.
    if (active.isNotEmpty) {
      final QueryDocumentSnapshot<Map<String, dynamic>> best = active
          .firstWhere(
            (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                _ticketState(d.data()) == _TicketState.parked,
            orElse: () => active.first,
          );
      unawaited(
        LastTicketStore.save(savedTicketFrom('ticket', best.id, best.data())),
      );
    }
    final bool offline = snapshot.data?.metadata.isFromCache ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (offline && tickets.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(color: spCardBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 18, color: spInsideColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Offline: showing your saved tickets. Hours left may '
                    'have changed; staff check them at the gate.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        SpPageHeader(
          title: 'Tickets',
          subtitle: 'Show the QR code to gate staff on entry and exit.',
          trailing: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const DriverTransactionHistoryPage(),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('Transactions'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _TemporaryQrList(
          stream: cachedStream(
            'passes_${FirebaseAuth.instance.currentUser?.uid}',
            () => FirebaseFirestore.instance
                .collection('parking_checkouts')
                .where(
                  'driverId',
                  isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                )
                .where('kind', isEqualTo: 'gate_pass')
                .where('status', whereIn: <String>['awaiting_gate', 'pending'])
                .snapshots(),
          ),
        ),
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
                'Home tab to get a temporary QR, then pay at the gate.',
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
                refund: refunds[doc.id],
              ),
          ],
          if (past.isNotEmpty) ...[
            const SizedBox(height: 16),
            SpSectionLabel(
              'Past Tickets',
              trailing: SpChip(
                label: '${past.length}',
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            SpShowMore(
              pageSize: 5,
              children: <Widget>[
                for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                    in past)
                  _PastTicketRow(doc: doc),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// Unpaid temporary QRs, paid at the gate. Expired ones are left out; the
/// server deletes them after a while.
class _TemporaryQrList extends StatelessWidget {
  const _TemporaryQrList({required this.stream});

  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (BuildContext context, snapshot) {
        final DateTime now = DateTime.now();
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> passes =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .where((QueryDocumentSnapshot<Map<String, dynamic>> d) {
                  final Object? expiresAt = d.data()['expiresAt'];
                  return d.data()['status'] == 'pending' ||
                      (expiresAt is Timestamp &&
                          now.isBefore(expiresAt.toDate()));
                })
                .toList();
        if (passes.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SpSectionLabel('Temporary QRs'),
            const SizedBox(height: 4),
            Text(
              'Not paid yet. Show one at the gate and pay once staff confirm '
              'there is space.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 8),
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                in passes)
              _TemporaryQrRow(doc: doc),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _TemporaryQrRow extends StatelessWidget {
  const _TemporaryQrRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final ParkingReceipt t = ParkingReceipt.fromTicket(doc.id, doc.data());
    final bool paying = doc.data()['status'] == 'pending';
    final Object? expiresAt = doc.data()['expiresAt'];
    final (String package, String covers) = spPackageParts(t);
    final TextStyle muted = TextStyle(
      fontSize: 12,
      color: AppTheme.textMuted,
      fontWeight: FontWeight.w600,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => DriverParkingPassPage(checkoutId: doc.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: <Widget>[
              Icon(
                paying ? Icons.payments_outlined : Icons.qr_code_2_rounded,
                color: AppTheme.accentText,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.facilityName.isEmpty
                          ? 'Parking facility'
                          : t.facilityName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('${t.plate} · ${t.vehicleLabel}', style: muted),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: <InlineSpan>[
                                TextSpan(
                                  text: '$package  ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                TextSpan(
                                  text: covers.split('\n').first,
                                  style: muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          spPeso(t.amountCentavos / 100),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      paying
                          ? 'Paying now at the gate'
                          : expiresAt is Timestamp
                          ? 'Due at the gate · valid until '
                                '${spFormatDate(expiresAt.toDate())}'
                          : 'Due at the gate',
                      style: muted,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tickets that were paid for, and so have a receipt.
bool _isPaid(_TicketState state) =>
    state == _TicketState.ready ||
    state == _TicketState.parked ||
    state == _TicketState.completed;

/// Shares the ticket's receipt from the data already on screen, so it works
/// offline and always matches the card. Beside it, the driver can report the
/// ticket's facility to SmartPark.
Widget _receiptButton(QueryDocumentSnapshot<Map<String, dynamic>> doc) => Wrap(
  alignment: WrapAlignment.end,
  crossAxisAlignment: WrapCrossAlignment.center,
  spacing: 4,
  children: <Widget>[
    SpReportFacilityButton(ticketId: doc.id, ticket: doc.data()),
    SpReceiptButton(
      onExport: (ReceiptFormat format, bool save, Rect? origin) =>
          exportParkingReceiptAs(
            ParkingReceipt.fromTicket(doc.id, doc.data()),
            format,
            save: save,
            origin: origin,
          ),
    ),
  ],
);

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
  return spVehicleTypeLabel(
    ((data['vehicleType'] as String?) ?? '').trim().toLowerCase(),
  );
}

IconData _vehicleIcon(Map<String, dynamic> data) =>
    spVehicleTypeIcon(spVehicleTypeKey(data['vehicleType']));

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
                  graceMinutes: facilityGraceMinutes(facility),
                  extraHours: ((data['extraHoursBought'] as num?) ?? 0).toInt(),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  // Always white, even in dark mode: scanners need a light
                  // border around the code.
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: spCardBorder),
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  ),
                  child: SpMaxBrightness(
                    child: QrImageView(
                      data: _resolveTicketQrPayload(doc),
                      size: 190,
                      backgroundColor: Colors.white,
                      eyeStyle: kTicketQrEyeStyle,
                      dataModuleStyle: kTicketQrModuleStyle,
                    ),
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
                      spPeso(amount),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
                if (plateHistoryLabel(data).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Plates: ${plateHistoryLabel(data)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                // Not while parked: the vehicle inside is the one on the
                // ticket until it exits.
                // More paid time, before it runs out (or to stop overtime).
                if (canAddTicketHours(data))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => showAddHoursSheet(
                        context,
                        ticketId: doc.id,
                        ticket: data,
                      ),
                      icon: const Icon(Icons.more_time_rounded, size: 16),
                      label: const Text(
                        'Add hours',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.accentText,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                if (canRateTicket(data))
                  RateFacilityRow(ticketId: doc.id, ticket: data),
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
                // So a driver at the gate can call the facility.
                SpFacilityContactRow.forFacility(_ticketFacilityId(data)),
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
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ticket #${doc.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    SpSaveQrButton(
                      ticket: ParkingReceipt.fromTicket(doc.id, data),
                      qrData: _resolveTicketQrPayload(doc),
                    ),
                    if (_isPaid(state)) _receiptButton(doc),
                  ],
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
      icon: const SpDialogIcon(Icons.edit_rounded, tone: SpDialogTone.info),
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
  const _TimeLeftPanel({
    required this.hoursLeft,
    this.parkedSince,
    this.graceMinutes = kDefaultGraceMinutes,
    this.extraHours = 0,
  });

  final int hoursLeft;

  /// Hours the driver bought on top of the package, already in [hoursLeft].
  final int extraHours;

  /// The facility's grace period after the paid time.
  final int graceMinutes;

  /// When the current visit began; null when the vehicle isn't parked.
  final DateTime? parkedSince;

  @override
  Widget build(BuildContext context) {
    final DateTime? since = parkedSince;
    final DateTime? paidUntil = since?.add(Duration(hours: hoursLeft));
    // Hours added during a visit count from its entry too.
    final String label = since == null
        ? 'Parking time left'
        : 'Paid time from your entry';
    final String validUntil = paidUntil == null
        ? 'Until the hours run out · no expiry date'
        : '${spFormatClockTime(paidUntil)}'
              '${spSameDate(paidUntil, DateTime.now()) ? ' today' : ', ${spFormatDate(paidUntil)}'}';
    final String note = paidUntil == null
        ? 'Counts down only while you\'re parked, at least '
              '$spBaseStayHours hours per visit. Reuse this ticket on later '
              'visits until the time runs out.'
        : graceMinutes <= 0
        ? 'Staying longer adds overtime, paid in cash at the exit.'
        : 'With the ${formatGracePeriod(graceMinutes)}, leave by '
              '${spFormatClockTime(paidUntil.add(Duration(minutes: graceMinutes)))} '
              'to pay no overtime. Later than that, overtime is paid in cash '
              'at the exit.';

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
                    if (extraHours > 0)
                      Text(
                        'Includes ${formatParkingHours(extraHours)} you added',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: spEntryColor,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: paidUntil == null ? 'Valid  ' : 'Covers you until  ',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
                TextSpan(
                  text: validUntil,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
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
  const _InvalidTicketCard({required this.doc, this.facility, this.refund});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Map<String, dynamic>? facility;
  final ParkingRefund? refund;

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
                                    text: reasons.length > 1
                                        ? 'Reasons given: '
                                        : 'Reason given: ',
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _RefundPanel(
                      ticketId: widget.doc.id,
                      ticket: data,
                      facility: facility,
                      refund: widget.refund,
                      undo: undo,
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
                    // Still a paid ticket: the driver may need proof of
                    // payment while the facility is pulled.
                    Align(
                      alignment: Alignment.centerRight,
                      child: _receiptButton(widget.doc),
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

/// What happens to the money on a ticket at a pulled facility: a refund on
/// its way, or (while suspended) the automatic date and a way to ask now.
class _RefundPanel extends StatefulWidget {
  const _RefundPanel({
    required this.ticketId,
    required this.ticket,
    required this.facility,
    required this.refund,
    required this.undo,
  });

  final String ticketId;
  final Map<String, dynamic> ticket;
  final Map<String, dynamic>? facility;
  final ParkingRefund? refund;

  /// "reinstated" or "reactivated".
  final String undo;

  @override
  State<_RefundPanel> createState() => _RefundPanelState();
}

class _RefundPanelState extends State<_RefundPanel> {
  bool _requesting = false;

  Future<void> _request(int amountCentavos) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const SpDialogIcon(Icons.currency_exchange_rounded),
        title: const Text('Request a refund?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'You get about ${spPeso(amountCentavos / 100)} back for the '
                'unused hours, to the account you paid with. A SmartPark '
                'admin reviews requests first. The ticket can no longer be '
                'used once refunded.',
              ),
              const SizedBox(height: 12),
              _RefundCalculation(ticket: widget.ticket),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Request refund'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _requesting = true);
    try {
      await ParkingRefundService().request(widget.ticketId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(error, fallback: 'Could not request a refund.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ParkingRefund? refund = widget.refund;
    final bool suspended = facilityStatus(widget.facility) == 'suspended';
    // Once sent, the amount is fixed; before that the server works it out
    // again from the hours left, as the estimate does.
    final bool sent = const <String>{
      'processing',
      'sent',
      'refunded',
    }.contains(refund?.status);
    final int amount = sent
        ? refund!.amountCentavos
        : estimatedRefundCentavos(widget.ticket);
    final String peso = spPeso(amount / 100);
    final DateTime? autoDate = suspensionRefundDate(
      widget.facility?['suspendedAt'],
    );
    final String hours = formatParkingHours(ticketHoursLeft(widget.ticket));
    final String autoWhen = autoDate == null
        ? 'If it stays suspended for $kSuspensionRefundDays days'
        : 'If it is still suspended on ${spFormatDate(autoDate)}';

    final (
      IconData icon,
      Color color,
      String title,
      String body,
    ) = switch (refund?.status) {
      'requested' => (
        Icons.hourglass_top_rounded,
        spInsideColor,
        'Refund of about $peso requested',
        'A SmartPark admin will review it. If nobody decides within '
            '$kRefundRequestAutoApproveDays days, it is approved '
            'automatically.',
      ),
      'approved' || 'processing' || 'sent' => (
        Icons.sync_rounded,
        spInsideColor,
        'Refund of $peso on its way',
        'It goes back to the account you paid with. Card refunds can '
            'take several days to show.',
      ),
      'refunded' => (
        Icons.check_circle_rounded,
        spEntryColor,
        '$peso refunded',
        'Sent back to the account you paid with.',
      ),
      'failed' => (
        Icons.error_outline_rounded,
        spDeniedColor,
        'Refund of $peso not sent yet',
        'SmartPark will try again. If it does not arrive, email '
            '$kSupportEmail with ticket #${widget.ticketId}.',
      ),
      'rejected' => (
        Icons.cancel_outlined,
        spDeniedColor,
        'Refund request not approved',
        '${refund!.decisionNote.isEmpty ? '' : '${refund.decisionNote} '}'
            'Your $hours stay on the ticket. $autoWhen, you still get '
            'about $peso back automatically.',
      ),
      _ when !suspended => (
        Icons.sync_rounded,
        spInsideColor,
        'Refund of about $peso being prepared',
        'The facility was closed, so the unused hours are refunded '
            'automatically.',
      ),
      _ => (
        Icons.schedule_rounded,
        spInsideColor,
        'Your $hours stay on the ticket',
        'It works again if the facility is ${widget.undo}. $autoWhen, '
            'you get about $peso back automatically. You can also ask for '
            'it now.',
      ),
    };
    final bool canRequest =
        suspended &&
        amount > 0 &&
        (refund == null || refund.isRejected) &&
        !_isParked(widget.ticket);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppTheme.textSecondary,
            ),
          ),
          if (!sent && amount > 0) ...<Widget>[
            const SizedBox(height: 10),
            _RefundCalculation(ticket: widget.ticket),
          ],
          if (canRequest) ...<Widget>[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _requesting ? null : () => _request(amount),
                icon: const Icon(Icons.currency_exchange_rounded, size: 18),
                label: Text(
                  _requesting
                      ? 'Requesting...'
                      : refund == null
                      ? 'Request refund now ($peso)'
                      : 'Request again ($peso)',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Why a refund is less than the price, and how it is worked out: the
/// fees that can't be refunded, then the unused share of the rest.
class _RefundCalculation extends StatelessWidget {
  const _RefundCalculation({required this.ticket});

  final Map<String, dynamic> ticket;

  @override
  Widget build(BuildContext context) {
    final RefundBreakdown b = RefundBreakdown.of(ticket);
    final String method = switch (((ticket['paymentMethod'] as String?) ?? '')
        .trim()) {
      'gcash' => 'GCash',
      'paymaya' => 'Maya',
      'card' => 'card',
      'qrph' => 'QR Ph',
      _ => '',
    };
    final int extraHours = ((ticket['extraHoursBought'] as num?) ?? 0).toInt();
    final String feeRate = commissionPercent(saleCommissionRate(ticket));
    final TextStyle muted = TextStyle(
      fontSize: 12,
      color: AppTheme.textSecondary,
    );
    final TextStyle strong = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: AppTheme.textDark,
    );
    Widget line(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label, style: bold ? strong : muted)),
          const SizedBox(width: 8),
          Text(value, style: bold ? strong : muted),
        ],
      ),
    );
    String peso(int centavos) => spPeso(centavos / 100);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: spCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
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
                  'Refunds are not the full price. SmartPark\'s $feeRate fee '
                  'and PayMongo\'s processing fee were taken when you paid, '
                  'and the facility can\'t refund them, so they are kept '
                  'back.'
                  '${extraHours > 0 ? ' Extra hours you added are not refunded.' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          line('Ticket price', peso(b.paidCentavos)),
          line('SmartPark fee ($feeRate)', '- ${peso(b.platformFeeCentavos)}'),
          line(
            'PayMongo fee${method.isEmpty ? '' : ' ($method)'}, estimated',
            '- ${peso(b.processorFeeCentavos)}',
          ),
          line('Refundable', peso(b.refundableCentavos)),
          line(
            'Unused: ${formatParkingHours(b.refundedHours)} of '
                '${formatParkingHours(b.totalHours)}',
            '× ${b.refundedHours}/${b.totalHours}',
          ),
          const Divider(height: 14),
          line('Likely refund', peso(b.refundCentavos), bold: true),
        ],
      ),
    );
  }
}

bool _isParked(Map<String, dynamic> ticket) {
  final String entry = ((ticket['entryStatus'] as String?) ?? '').toLowerCase();
  return entry == 'checked_in' || entry == 'inside';
}

class _PastTicketRow extends StatelessWidget {
  const _PastTicketRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> data = doc.data();
    final _TicketState state = _ticketState(data);
    var (String stateLabel, Color stateColor, IconData stateIcon) = _stateStyle(
      state,
    );
    // A ticket SmartPark refunded when its facility was pulled.
    if (data['refundStatus'] == 'refunded' || data['refundStatus'] == 'sent') {
      final int refunded = ((data['refundedCentavos'] as num?) ?? 0).toInt();
      stateLabel =
          '${data['refundStatus'] == 'sent' ? 'Refund sent' : 'Refunded'} '
          '${spPeso(refunded / 100)}';
      stateColor = spEntryColor;
      stateIcon = Icons.currency_exchange_rounded;
    }
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
                      spPeso(amount),
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
                if (canRateTicket(data))
                  RateFacilityRow(ticketId: doc.id, ticket: data),
                if (_isPaid(state))
                  Align(
                    alignment: Alignment.centerRight,
                    child: _receiptButton(doc),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
