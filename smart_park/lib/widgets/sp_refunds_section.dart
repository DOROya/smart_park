import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/parking_refunds.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'smartpark_ui.dart';

/// Refunds for tickets at facilities SmartPark pulled, on the Report tab.
/// Admins see every refund and approve or reject drivers' requests; owners
/// see their facility's refunds in plain words: what was refunded, why, who
/// pays for it, and how much of their share is still going to it.
class SpRefundsSection extends StatefulWidget {
  /// Every refund, with approve / reject for requests.
  const SpRefundsSection.admin({super.key}) : ownerId = null;

  /// [ownerId]'s facilities only, read-only.
  const SpRefundsSection.owner({super.key, required String this.ownerId});

  final String? ownerId;

  @override
  State<SpRefundsSection> createState() => _SpRefundsSectionState();
}

class _SpRefundsSectionState extends State<SpRefundsSection> {
  static const int _shown = 10;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _refunds;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _balance;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _balances;
  final Set<String> _busy = <String>{};
  bool _showAll = false;

  bool get _admin => widget.ownerId == null;

  @override
  void initState() {
    super.initState();
    final CollectionReference<Map<String, dynamic>> col = FirebaseFirestore
        .instance
        .collection('refunds');
    _refunds = (_admin ? col : col.where('ownerId', isEqualTo: widget.ownerId))
        .snapshots();
    if (!_admin) {
      _balance = FirebaseFirestore.instance
          .collection('owner_refund_balances')
          .doc(widget.ownerId)
          .snapshots();
    }
  }

  Future<void> _decide(ParkingRefund r, {required bool approve}) async {
    String note = '';
    if (!approve) {
      final TextEditingController controller = TextEditingController();
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Reject this refund request?'),
          content: TextField(
            controller: controller,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Reason shown to the driver (optional)',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      note = controller.text.trim();
      controller.dispose();
      if (ok != true) return;
    }
    setState(() => _busy.add(r.ticketId));
    try {
      final String status = await ParkingRefundService().decide(
        r.ticketId,
        approve: approve,
        note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (status) {
            'refunded' => '${spPeso(r.amountCentavos / 100)} refunded.',
            'sent' =>
              '${spPeso(r.amountCentavos / 100)} sent. PayMongo will '
                  'confirm it shortly.',
            'rejected' => 'Request rejected.',
            'failed' => 'PayMongo did not accept the refund. See its details.',
            _ => 'Refund is processing.',
          }),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(error, fallback: 'Could not save.')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(r.ticketId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _refunds,
      builder: (BuildContext context, snapshot) {
        final List<ParkingRefund> all =
            refundsByTicket(snapshot.data).values.toList()..sort(
              (ParkingRefund a, ParkingRefund b) => (b.createdAt ?? DateTime(0))
                  .compareTo(a.createdAt ?? DateTime(0)),
            );
        final List<ParkingRefund> requests = all
            .where((ParkingRefund r) => r.isPendingApproval)
            .toList();
        // Admins review requests in their own list; owners see everything
        // in one list, requests included, so nothing is hidden from them.
        final List<ParkingRefund> list = _admin
            ? all.where((ParkingRefund r) => !r.isPendingApproval).toList()
            : all;
        final List<ParkingRefund> done = all
            .where((ParkingRefund r) => r.isPaidOut)
            .toList();
        int sum(Iterable<ParkingRefund> rs) =>
            rs.fold<int>(0, (int t, ParkingRefund r) => t + r.amountCentavos);
        // An owner's part is the refund less SmartPark's commission on it.
        final int byOwner = done.fold<int>(
          0,
          (int t, ParkingRefund r) => t + r.ownerShareCentavos,
        );
        final int byPlatform = sum(done) - byOwner;
        final List<ParkingRefund> disputes = all
            .where((ParkingRefund r) => r.hasOpenDispute)
            .toList();
        final int toReview = requests.length + disputes.length;

        return SpSectionCard(
          icon: Icons.currency_exchange_rounded,
          title: 'Refunds',
          subtitle: _admin
              ? 'Unused hours refunded to drivers because SmartPark '
                    'suspended or deactivated a facility.'
              : 'If SmartPark suspends or deactivates your facility, drivers '
                    'get back the hours they paid for but could not use.',
          trailing: toReview == 0 || !_admin
              ? null
              : SpChip(label: '$toReview to review', color: spInsideColor),
          child: snapshot.hasError
              ? Text(
                  'Could not load refunds.',
                  style: TextStyle(color: AppTheme.textMuted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _summary(done.length, byOwner, byPlatform),
                    if (_balance != null) _repayment(),
                    if (_admin && requests.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      _heading('Driver requests to review'),
                      for (final ParkingRefund r in requests) _row(r),
                    ],
                    if (_admin && disputes.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      _heading('Owner disputes to review'),
                      for (final ParkingRefund r in disputes) _row(r),
                    ],
                    if (_admin) _ownerBalances(all),
                    const SizedBox(height: 16),
                    _heading(_admin ? 'History' : 'Refunded tickets'),
                    if (list.isEmpty)
                      Text(
                        _admin
                            ? 'No refunds yet.'
                            : 'None. Refunds only happen if SmartPark '
                                  'suspends or deactivates your facility.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textMuted,
                        ),
                      )
                    else ...<Widget>[
                      for (final ParkingRefund r
                          in _showAll ? list : list.take(_shown))
                        _row(r),
                      if (list.length > _shown)
                        TextButton(
                          onPressed: () => setState(() => _showAll = !_showAll),
                          child: Text(
                            _showAll ? 'Show fewer' : 'Show all ${list.length}',
                          ),
                        ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: AppTheme.textDark,
      ),
    ),
  );

  Future<void> _call(
    ParkingRefund r,
    Future<void> Function() action,
    String done,
  ) async {
    setState(() => _busy.add(r.ticketId));
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(error, fallback: 'Could not save.')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(r.ticketId));
    }
  }

  /// A short text answer; null when cancelled.
  Future<String?> _ask({
    required String title,
    required String body,
    required String label,
    required String confirm,
  }) async {
    final TextEditingController controller = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(body, style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 500,
              maxLines: 3,
              decoration: InputDecoration(labelText: label),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    final String text = controller.text.trim();
    controller.dispose();
    return ok == true ? text : null;
  }

  /// Owner: says this refund should not be charged to them.
  Future<void> _dispute(ParkingRefund r) async {
    final String? message = await _ask(
      title: 'Dispute this charge?',
      body:
          'Tell SmartPark why this refund should not be charged to you. An '
          'administrator reviews it and, if you are right, SmartPark covers '
          'the refund instead. You can dispute a refund once.',
      label: 'Why it should not be charged to you',
      confirm: 'Send dispute',
    );
    if (message == null || !mounted) return;
    if (message.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Explain why in a sentence or two.')),
      );
      return;
    }
    await _call(
      r,
      () => ParkingRefundService().dispute(r.ticketId, message),
      'Dispute sent. SmartPark will review it.',
    );
  }

  /// Admin: moves the charge to SmartPark, or keeps it on the owner.
  Future<void> _resolveDispute(ParkingRefund r, {required bool uphold}) async {
    final String? note = await _ask(
      title: uphold ? 'Uphold this dispute?' : 'Turn down this dispute?',
      body: uphold
          ? 'SmartPark covers this refund instead of the owner, and the '
                'owner\'s balance drops by what they owed for it.'
          : 'The refund stays charged to the owner.',
      label: 'Note to the owner (optional)',
      confirm: uphold ? 'SmartPark covers it' : 'Turn down',
    );
    if (note == null || !mounted) return;
    await _call(
      r,
      () => ParkingRefundService().resolveDispute(
        r.ticketId,
        uphold: uphold,
        note: note,
      ),
      uphold ? 'Charge moved to SmartPark.' : 'Dispute turned down.',
    );
  }

  /// Admin: what each owner still owes, with a way to record money they
  /// paid SmartPark directly (asked for when there are no later sales to
  /// take it from).
  Widget _ownerBalances(List<ParkingRefund> all) {
    _balances ??= FirebaseFirestore.instance
        .collection('owner_refund_balances')
        .where('owedCentavos', isGreaterThan: 0)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _balances,
      builder: (BuildContext context, snap) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> owing =
            snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (owing.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 16),
            _heading('Owner balances'),
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in owing)
              _balanceRow(
                doc.id,
                ((doc.data()['owedCentavos'] as num?) ?? 0).toInt(),
                all
                    .where((ParkingRefund r) => r.ownerId == doc.id)
                    .map((ParkingRefund r) => r.establishmentName)
                    .where((String n) => n.isNotEmpty)
                    .toSet()
                    .join(', '),
              ),
          ],
        );
      },
    );
  }

  Widget _balanceRow(String ownerId, int owed, String facilities) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: spCardBorder),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  facilities.isEmpty ? 'Owner' : facilities,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${spPeso(owed / 100)} still owed for refunds',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _recordPayment(ownerId, owed),
            child: const Text('Record payment'),
          ),
        ],
      ),
    );
  }

  Future<void> _recordPayment(String ownerId, int owed) async {
    final TextEditingController controller = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Record a direct payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Enter what the owner paid SmartPark directly. '
              '${spPeso(owed / 100)} is still owed.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount received (PHP)',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Record'),
          ),
        ],
      ),
    );
    final int centavos = ((double.tryParse(controller.text.trim()) ?? 0) * 100)
        .round();
    controller.dispose();
    if (ok != true || !mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (centavos <= 0 || centavos > owed) {
      messenger.showSnackBar(
        SnackBar(content: Text('Enter an amount up to ${spPeso(owed / 100)}.')),
      );
      return;
    }
    try {
      await ParkingRefundService().recordRepayment(ownerId, centavos);
      messenger.showSnackBar(
        SnackBar(content: Text('${spPeso(centavos / 100)} recorded.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(error, fallback: 'Could not save.')),
        ),
      );
    }
  }

  /// The total refunded, then who paid for it, each with a one-line why.
  Widget _summary(int count, int byOwner, int byPlatform) {
    final int total = byOwner + byPlatform;
    Widget line(String who, int centavos, String why) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(who, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  why,
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            spPeso(centavos / 100),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Refunded to drivers',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          Text(
            spPeso(total / 100),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          Text(
            '$count ticket${count == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const Divider(height: 18),
          line(
            _admin ? 'Paid by owners' : 'Paid by you',
            byOwner,
            _admin
                ? 'Facility pulled for its own reasons (rates, complaints, '
                      'safety, not operating...).'
                : 'Your facility was pulled for reasons such as rates, '
                      'complaints, safety or not operating. SmartPark\'s '
                      'commission on each refund is given back, so it is '
                      'not counted here.',
          ),
          line(
            'Paid by SmartPark',
            byPlatform,
            'Pulled over permits or documents SmartPark had approved.',
          ),
        ],
      ),
    );
  }

  /// Owner only: how much of what they owe is paid back, as a bar.
  Widget _repayment() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _balance,
      builder: (BuildContext context, snap) {
        final Map<String, dynamic> b = snap.data?.data() ?? <String, dynamic>{};
        final int balance =
            ((b['owedCentavos'] as num?) ?? 0).toInt() +
            ((b['reservedCentavos'] as num?) ?? 0).toInt();
        // Below zero after an upheld dispute on a refund already repaid.
        if (balance < 0) return _credit(-balance);
        final int left = balance;
        final int repaid = ((b['recoveredCentavos'] as num?) ?? 0).toInt();
        final int total = left + repaid;
        if (total <= 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: left > 0 ? AppTheme.warningSoft : AppTheme.successSoft,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  left > 0
                      ? 'Paying back the refunds you cover'
                      : 'All refunds you covered are paid back',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: repaid / total,
                    minHeight: 8,
                    backgroundColor: AppTheme.surface,
                    color: spEntryColor,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${spPeso(repaid / 100)} paid back',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Text(
                      '${spPeso(left / 100)} left',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (left > 0) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'You do not pay this separately. Up to half of your share '
                    'of each online sale goes to it automatically until it is '
                    'paid off, and your earnings above already reflect it.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Owner only: SmartPark took over a refund the owner had already repaid.
  Widget _credit(int centavos) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.successSoft,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Text(
        'You have ${spPeso(centavos / 100)} in credit: SmartPark took over '
        'a refund you had already paid back. It is used up first if a '
        'refund is charged to you again, or ask SmartPark to pay it out.',
        style: const TextStyle(fontSize: 12.5, height: 1.4),
      ),
    ),
  );

  /// Status in words for whoever is reading.
  (String, Color) _status(ParkingRefund r) => switch (r.status) {
    'refunded' => ('Refunded', spEntryColor),
    'sent' => ('Sent · PayMongo confirming', spInsideColor),
    'requested' => (
      _admin ? 'Awaiting your approval' : 'Driver asked · SmartPark reviewing',
      spInsideColor,
    ),
    'awaiting_exit' => ('Refunds when the driver exits', spInsideColor),
    'approved' || 'processing' => ('Sending to driver', spInsideColor),
    'failed' => (
      _admin ? 'Failed' : 'Delayed · SmartPark retrying',
      spDeniedColor,
    ),
    'rejected' => ('Not approved · no refund', AppTheme.textMuted),
    _ => (r.statusLabel, AppTheme.textMuted),
  };

  Widget _row(ParkingRefund r) {
    final (String statusLabel, Color statusColor) = _status(r);
    final bool busy = _busy.contains(r.ticketId);
    final DateTime? when = r.refundedAt ?? r.createdAt;
    final List<String> why = r.reasons
        .where((String x) => x != 'Other')
        .toList();
    final String whatHappened = switch (r.cause) {
      'deactivated' => 'Facility deactivated',
      'suspended_14_days' => 'Suspended for $kSuspensionRefundDays days',
      'driver_request' => 'Driver asked during a suspension',
      _ => r.causeLabel,
    };
    final int? owed = r.ownerOwedCentavos;
    final String payer = !r.paidByOwner
        ? 'SmartPark'
        : '${_admin ? 'Owner' : 'You'}'
              '${owed == null || owed == r.amountCentavos ? '' : ' (${spPeso(owed / 100)}; SmartPark gives back its commission)'}';
    final String? disputeLine = switch (r.disputeStatus) {
      'open' =>
        _admin
            ? 'Owner disputes this charge: ${r.disputeMessage}'
            : 'You disputed this charge. SmartPark is reviewing it.',
      'upheld' => 'Dispute upheld: SmartPark covers this refund.',
      'rejected' =>
        'Dispute turned down.'
            '${r.disputeNote.isEmpty ? '' : ' ${r.disputeNote}'}',
      _ => null,
    };

    TextSpan label(String k, String v) => TextSpan(
      children: <InlineSpan>[
        TextSpan(
          text: '$k  ',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        TextSpan(
          text: v,
          style: TextStyle(color: AppTheme.textDark),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: spCardBorder),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (r.vehiclePlate.isNotEmpty) ...<Widget>[
                SpPlateBadge(plate: r.vehiclePlate),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SpChip(label: statusLabel, color: statusColor),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                spPeso(r.amountCentavos / 100),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                if (_admin) ...<InlineSpan>[
                  label('Facility', r.establishmentName),
                  const TextSpan(text: '\n'),
                ],
                label(
                  'Why',
                  why.isEmpty
                      ? whatHappened
                      : '$whatHappened (${why.join(', ')})',
                ),
                const TextSpan(text: '\n'),
                label('Unused', '${r.unusedHours} hours of the ticket'),
                const TextSpan(text: '\n'),
                label('Paid by', payer),
                if (when != null) ...<InlineSpan>[
                  const TextSpan(text: '\n'),
                  label(
                    r.isRefunded ? 'Refunded' : 'Since',
                    spFormatDate(when),
                  ),
                ],
              ],
            ),
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
          if (disputeLine != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              disputeLine,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
          ],
          if (!_admin && r.canDispute && !r.isRejected)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : () => _dispute(r),
                child: Text(busy ? 'Sending...' : 'Dispute this charge'),
              ),
            ),
          if (_admin && r.hasOpenDispute) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _resolveDispute(r, uphold: false),
                  child: const Text('Turn down'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => _resolveDispute(r, uphold: true),
                  child: Text(busy ? 'Saving...' : 'SmartPark covers it'),
                ),
              ],
            ),
          ],
          if (_admin && r.isFailed && r.failureReason.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              r.failureReason,
              style: TextStyle(fontSize: 11.5, color: spDeniedColor),
            ),
          ],
          if (_admin && (r.isPendingApproval || r.isFailed)) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (r.isPendingApproval)
                  TextButton(
                    onPressed: busy ? null : () => _decide(r, approve: false),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                    ),
                    child: const Text('Reject'),
                  ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: busy ? null : () => _decide(r, approve: true),
                  child: Text(
                    busy
                        ? 'Sending...'
                        : r.isFailed
                        ? 'Retry refund'
                        : 'Approve & refund',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
