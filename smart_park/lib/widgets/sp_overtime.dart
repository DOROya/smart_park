import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/gate_scan_service.dart'
    show kOvertimeCashDue, kOvertimeCollected;
import '../services/parking_pricing.dart';
import '../theme/app_theme.dart';
import 'smartpark_ui.dart';

/// Overtime tracking for the owner: vehicles past their paid time right now,
/// and overtime cash still owed versus handed over at the gate.

String spOvertimeStatus(Map<String, dynamic> data) =>
    ((data['overtimeStatus'] as String?) ?? '').toLowerCase();

String spPeso(double value) => 'PHP ${value.toStringAsFixed(2)}';

/// Overtime cash across exit logs or tickets: flagged at the gate but not
/// yet collected, and collected.
class SpOvertimeCash {
  SpOvertimeCash.from(Iterable<Map<String, dynamic>> docs) {
    for (final Map<String, dynamic> data in docs) {
      final double amount = ((data['overtimeAmount'] as num?) ?? 0).toDouble();
      switch (spOvertimeStatus(data)) {
        case kOvertimeCashDue:
          dueCount++;
          dueAmount += amount;
        case kOvertimeCollected:
          collectedCount++;
          collectedAmount += amount;
      }
    }
  }

  int dueCount = 0;
  double dueAmount = 0;
  int collectedCount = 0;
  double collectedAmount = 0;

  bool get isEmpty => dueCount == 0 && collectedCount == 0;
}

/// Overtime cash for a period: amber while some is still uncollected,
/// green once everything flagged was collected. Empty when there was none.
class SpOvertimeCashBanner extends StatelessWidget {
  const SpOvertimeCashBanner({
    super.key,
    required this.cash,
    this.period = 'today',
  });

  final SpOvertimeCash cash;

  /// e.g. "today" or "on this day".
  final String period;

  @override
  Widget build(BuildContext context) {
    if (cash.isEmpty) return const SizedBox.shrink();
    final bool owed = cash.dueCount > 0;
    final String title = owed
        ? '${spPeso(cash.dueAmount)} overtime cash not collected'
        : '${spPeso(cash.collectedAmount)} overtime cash collected';
    final String subtitle = owed
        ? '${cash.dueCount} exit${cash.dueCount == 1 ? '' : 's'} $period '
              'still waiting on staff to confirm the cash'
              '${cash.collectedCount > 0 ? ' · ${spPeso(cash.collectedAmount)} collected' : ''}.'
        : '${cash.collectedCount} overtime exit'
              '${cash.collectedCount == 1 ? '' : 's'} $period, all settled at '
              'the gate.';
    final Color color = owed ? spInsideColor : spEntryColor;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: owed ? AppTheme.warningSoft : AppTheme.successSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: owed ? AppTheme.accent : color),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            owed ? Icons.payments_rounded : Icons.check_circle_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: owed ? AppTheme.accentText : AppTheme.textSecondary,
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

/// A paid vehicle still parked, with when its paid time runs out.
class SpParkedStay {
  SpParkedStay._({
    required this.transactionId,
    required this.plate,
    required this.vehicleType,
    required this.entryAt,
    required this.includedHours,
    required this.rate,
  });

  /// Null for walk-ins (no paid time) and tickets with no entry time yet.
  static SpParkedStay? fromTicket(
    String transactionId,
    Map<String, dynamic> ticket,
    Map<String, dynamic>? rates,
  ) {
    if (ticket['source'] == 'walk_in') return null;
    final DateTime? entryAt =
        spParseDateTime(ticket['entryAt']) ??
        spParseDateTime(ticket['createdAt']);
    if (entryAt == null) return null;
    final String vehicleType = ((ticket['vehicleType'] as String?) ?? 'car')
        .trim()
        .toLowerCase();
    return SpParkedStay._(
      transactionId: transactionId,
      plate: ((ticket['vehiclePlate'] as String?) ?? '').trim(),
      vehicleType: vehicleType,
      entryAt: entryAt,
      includedHours: includedStayHours(
        plan: ((ticket['plan'] as String?) ?? 'base').trim().toLowerCase(),
        duration: ticketDuration(ticket),
      ),
      rate: resolveOvertimeRate(rates, vehicleType),
    );
  }

  final String transactionId;
  final String plate;
  final String vehicleType;
  final DateTime entryAt;
  final int includedHours;

  /// Hourly overtime rate; null when the facility has none set.
  final double? rate;

  DateTime get paidUntil => entryAt.add(Duration(hours: includedHours));
  DateTime get overtimeFrom => overtimeStartsAt(entryAt, includedHours);

  /// Whole overtime hours the gate would bill if the car left at [now].
  int overtimeHoursAt(DateTime now) =>
      overtimeHours(now.difference(entryAt), includedHours);

  bool isOverAt(DateTime now) => overtimeHoursAt(now) > 0;

  /// Paid time ends within [window] (or already ended, still in grace).
  bool endsSoonAt(DateTime now, {Duration window = spEndsSoonWindow}) =>
      !isOverAt(now) && now.isAfter(paidUntil.subtract(window));

  /// Cash the gate would ask for at [now]; null when there is no rate.
  double? owedAt(DateTime now) =>
      rate == null ? null : overtimeHoursAt(now) * rate!;
}

/// How far ahead the owner is warned that a vehicle's paid time runs out.
const Duration spEndsSoonWindow = Duration(minutes: 15);

/// Live card for the owner's home tab: vehicles past their paid time now,
/// the cash they will owe, and vehicles whose time is about to run out.
/// Refreshes each minute, since overtime grows with the clock, not with data.
class SpOverstayCard extends StatefulWidget {
  const SpOverstayCard({super.key, required this.facilityId, this.rates});

  final String facilityId;

  /// The facility's `establishment_details.rates`.
  final Map<String, dynamic>? rates;

  @override
  State<SpOverstayCard> createState() => _SpOverstayCardState();
}

class _SpOverstayCardState extends State<SpOverstayCard> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _parked;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  Stream<QuerySnapshot<Map<String, dynamic>>> _query() => FirebaseFirestore
      .instance
      .collection('transactions')
      .where('establishmentId', isEqualTo: widget.facilityId)
      .where('entryStatus', isEqualTo: 'checked_in')
      .snapshots();

  @override
  void initState() {
    super.initState();
    _parked = _query();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(SpOverstayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.facilityId != widget.facilityId) _parked = _query();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _parked,
      builder: (BuildContext context, snapshot) {
        final DateTime now = _now;
        final List<SpParkedStay> stays = <SpParkedStay>[
          for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
              in snapshot.data?.docs ??
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            ?SpParkedStay.fromTicket(doc.id, doc.data(), widget.rates),
        ];
        final List<SpParkedStay> over =
            stays.where((SpParkedStay s) => s.isOverAt(now)).toList()..sort(
              (SpParkedStay a, SpParkedStay b) =>
                  a.overtimeFrom.compareTo(b.overtimeFrom),
            );
        final List<SpParkedStay> soon =
            stays.where((SpParkedStay s) => s.endsSoonAt(now)).toList()..sort(
              (SpParkedStay a, SpParkedStay b) =>
                  a.paidUntil.compareTo(b.paidUntil),
            );
        double owed = 0;
        bool rateMissing = false;
        for (final SpParkedStay stay in over) {
          final double? amount = stay.owedAt(now);
          if (amount == null) {
            rateMissing = true;
          } else {
            owed += amount;
          }
        }

        final Widget content;
        if (snapshot.hasError) {
          content = const SpEmptyState(
            boxed: false,
            icon: Icons.error_outline_rounded,
            message: 'Unable to check parked vehicles right now.',
          );
        } else if (!snapshot.hasData) {
          content = const SizedBox(
            height: 24,
            child: Center(child: LinearProgressIndicator()),
          );
        } else if (over.isEmpty && soon.isEmpty) {
          content = SpEmptyState(
            boxed: false,
            icon: Icons.check_circle_outline_rounded,
            message: stays.isEmpty
                ? 'No paid vehicles parked right now.'
                : 'All ${stays.length} parked vehicle'
                      '${stays.length == 1 ? ' is' : 's are'} within paid time.',
          );
        } else {
          final List<SpParkedStay> preview = <SpParkedStay>[
            ...over,
            ...soon,
          ].take(3).toList();
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (over.isNotEmpty)
                Text(
                  '${spPeso(owed)} to collect if they leave now'
                  '${rateMissing ? ' (some rates missing)' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: spInsideColor,
                  ),
                ),
              const SizedBox(height: 8),
              for (final SpParkedStay stay in preview)
                SpParkedStayRow(stay: stay, now: now),
              if (over.length + soon.length > preview.length)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _showAll(context, over, soon),
                    child: Text('View all (${over.length + soon.length})'),
                  ),
                ),
            ],
          );
        }

        return SpSectionCard(
          icon: Icons.more_time_rounded,
          title: 'Overtime',
          subtitle: 'Vehicles still parked past the time they paid for.',
          trailing: over.isEmpty
              ? (soon.isEmpty
                    ? null
                    : SpChip(
                        label: '${soon.length} ending soon',
                        color: AppTheme.textMuted,
                      ))
              : SpChip(label: '${over.length} over', color: spInsideColor),
          child: content,
        );
      },
    );
  }

  void _showAll(
    BuildContext context,
    List<SpParkedStay> over,
    List<SpParkedStay> soon,
  ) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppTheme.surface,
        builder: (BuildContext sheetContext) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: <Widget>[
                if (over.isNotEmpty) ...<Widget>[
                  SpSectionLabel('Past paid time (${over.length})'),
                  const SizedBox(height: 8),
                  for (final SpParkedStay stay in over)
                    SpParkedStayRow(stay: stay, now: _now),
                ],
                if (soon.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  SpSectionLabel('Ending soon (${soon.length})'),
                  const SizedBox(height: 8),
                  for (final SpParkedStay stay in soon)
                    SpParkedStayRow(stay: stay, now: _now),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One parked vehicle: plate, when it came in and what it paid for, and how
/// far past (or close to) the end of its paid time it is.
class SpParkedStayRow extends StatelessWidget {
  const SpParkedStayRow({super.key, required this.stay, required this.now});

  final SpParkedStay stay;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final bool over = stay.isOverAt(now);
    final double? owed = stay.owedAt(now);
    final Duration delta = over
        ? now.difference(stay.paidUntil)
        : stay.paidUntil.difference(now);
    final String timing = over
        ? '+${spFormatDuration(delta)} over'
        : delta.isNegative
        ? 'in grace period'
        : 'ends in ${spFormatDuration(delta)}';
    final Color color = over ? spInsideColor : AppTheme.textMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: over ? AppTheme.warningSoft : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: over ? AppTheme.accent : spCardBorder),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            stay.vehicleType == 'motorcycle'
                ? Icons.two_wheeler_rounded
                : Icons.directions_car_filled_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SpPlateBadge(plate: stay.plate),
                const SizedBox(height: 4),
                Text(
                  'In ${spFormatClockTime(stay.entryAt)}'
                  '${spSameDate(stay.entryAt, now) ? '' : ' (${spFormatDate(stay.entryAt)})'}'
                  ' · paid ${stay.includedHours}h'
                  ' · until ${spFormatClockTime(stay.paidUntil)}',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                timing,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              if (over)
                Text(
                  owed == null ? 'rate missing' : '~${spPeso(owed)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
