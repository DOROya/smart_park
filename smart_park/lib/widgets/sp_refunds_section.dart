import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/parking_refunds.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'smartpark_ui.dart';
import 'sp_dialog.dart';

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
  static const int _shown = 6;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _refunds;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _balance;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _balances;
  final Set<String> _busy = <String>{};

  /// Refunds whose calculation is open.
  final Set<String> _open = <String>{};
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
      final String? rejectNote = await spAskNote(
        context,
        icon: Icons.cancel_outlined,
        tone: SpDialogTone.danger,
        title: 'Reject this refund request?',
        body: 'The driver is not refunded for this ticket.',
        facts: _refundFacts(r),
        label: 'Reason (optional)',
        hint: 'e.g. The vehicle used the full time it paid for',
        audience: 'The driver sees this reason.',
        confirm: 'Reject',
        destructive: true,
      );
      if (rejectNote == null) return;
      note = rejectNote;
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
        // An owner's part (older refunds charged less SmartPark's
        // commission; newer ones are charged in full).
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_admin && toReview > 0)
                SpChip(label: '$toReview to review', color: spInsideColor),
              _help(),
            ],
          ),
          child: snapshot.hasError
              ? Text(
                  'Could not load refunds.',
                  style: TextStyle(color: AppTheme.textMuted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _summary(
                      done,
                      byOwner,
                      byPlatform,
                      all.where((ParkingRefund r) => r.isInProgress).toList(),
                    ),
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

  /// How refunds work, step by step, for whoever is reading.
  Widget _help() {
    final String you = _admin ? 'the owner' : 'you';
    final String yours = _admin ? 'the owner\'s' : 'your';
    return SpHelpButton(
      title: 'How refunds work',
      points: <SpDialogPoint>[
        SpDialogPoint(
          icon: Icons.gpp_maybe_outlined,
          text:
              '1. When: only if SmartPark suspends or deactivates a '
              'facility, so drivers can no longer park on tickets they '
              'bought there. It happens by itself on deactivation or after '
              '$kSuspensionRefundDays days of suspension; before that, a '
              'driver can ask for it.',
          tone: SpDialogTone.warning,
        ),
        const SpDialogPoint(
          icon: Icons.timelapse_rounded,
          text:
              '2. How much: the hours the driver paid for but could not use. '
              'Hours already parked are not refunded.',
        ),
        SpDialogPoint(
          icon: Icons.account_balance_wallet_outlined,
          text:
              '3. Who covers it: $you, if the '
              'facility was pulled for its own reasons (rates, complaints, '
              'safety, not operating). SmartPark, if it was pulled over '
              'permits or documents SmartPark had approved.',
        ),
        SpDialogPoint(
          icon: Icons.replay_rounded,
          text:
              '4. Paying it back: ${_admin ? 'the owner does' : 'you do'} not '
              'pay separately. Up to half of $yours '
              'share of each online sale goes to it until it is paid off.',
          tone: SpDialogTone.success,
        ),
        SpDialogPoint(
          icon: Icons.gavel_rounded,
          text: _admin
              ? '5. Disputes: an owner can dispute a refund charged to them '
                    'once. If you uphold it, SmartPark covers it instead.'
              : '5. Disagree? Tap "Dispute this charge" once per refund. '
                    'If SmartPark agrees, it covers the refund instead.',
        ),
        if (_admin)
          SpDialogPoint(
            icon: Icons.how_to_reg_outlined,
            text:
                '6. Driver requests: while a facility is suspended, a '
                'driver can ask for their refund before the '
                '$kSuspensionRefundDays days are up. You approve or reject '
                'it here, and PayMongo sends approved money back.',
          ),
      ],
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

  /// The summary box for a refund pop-up: facility, plate and amount.
  List<(String, String)> _refundFacts(ParkingRefund r) {
    final int amount = r.amountCentavos > 0
        ? r.amountCentavos
        : r.ticketAmountCentavos;
    return <(String, String)>[
      if (r.establishmentName.isNotEmpty) ('Facility', r.establishmentName),
      if (r.vehiclePlate.isNotEmpty) ('Plate', r.vehiclePlate),
      if (amount > 0)
        (r.amountCentavos > 0 ? 'Refund' : 'Ticket', spPeso(amount / 100)),
    ];
  }

  /// Owner: says this refund should not be charged to them.
  Future<void> _dispute(ParkingRefund r) async {
    final String? message = await spAskNote(
      context,
      icon: Icons.currency_exchange_rounded,
      title: 'Dispute this charge?',
      body:
          'An administrator reviews it and, if you are right, SmartPark '
          'covers the refund instead. You can dispute a refund once.',
      facts: _refundFacts(r),
      label: 'Why it should not be charged to you',
      hint: 'e.g. The driver left early on their own; the gate was open',
      audience: 'SmartPark admins see this.',
      confirm: 'Send dispute',
      minLength: 10,
      maxLength: 500,
    );
    if (message == null || !mounted) return;
    await _call(
      r,
      () => ParkingRefundService().dispute(r.ticketId, message),
      'Dispute sent. SmartPark will review it.',
    );
  }

  /// Admin: moves the charge to SmartPark, or keeps it on the owner.
  Future<void> _resolveDispute(ParkingRefund r, {required bool uphold}) async {
    final String? note = await spAskNote(
      context,
      icon: uphold ? Icons.task_alt_rounded : Icons.gavel_rounded,
      tone: uphold ? SpDialogTone.success : SpDialogTone.warning,
      title: uphold ? 'Uphold this dispute?' : 'Turn down this dispute?',
      body: uphold
          ? 'SmartPark covers this refund instead of the owner, and the '
                'owner\'s balance drops by what they owed for it.'
          : 'The refund stays charged to the owner.',
      facts: <(String, String)>[
        ..._refundFacts(r),
        if (r.disputeMessage.isNotEmpty) ('Owner says', r.disputeMessage),
      ],
      label: 'Note to the owner (optional)',
      hint: uphold
          ? 'e.g. Confirmed from the gate log'
          : 'e.g. The gate log shows the ticket was used',
      audience: 'The owner sees this note.',
      confirm: uphold ? 'SmartPark covers it' : 'Turn down',
      maxLength: 500,
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
        scrollable: true,
        icon: const SpDialogIcon(
          Icons.payments_outlined,
          tone: SpDialogTone.success,
        ),
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
    spDisposeAfterClose(controller);
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

  /// The total refunded, a bar splitting it by who covered it, each part
  /// with a one-line why, and what is still on its way.
  Widget _summary(
    List<ParkingRefund> paidOut,
    int byOwner,
    int byPlatform,
    List<ParkingRefund> inProgress,
  ) {
    final int count = paidOut.length;
    final int total = byOwner + byPlatform;
    // What drivers first paid for these tickets, when the server saved it.
    final List<ParkingRefund> priced = paidOut
        .where((ParkingRefund r) => r.hasBreakdown)
        .toList();
    final int paidTotal = priced.fold<int>(
      0,
      (int t, ParkingRefund r) => t + r.ticketAmountCentavos,
    );
    final int pending = inProgress.fold<int>(
      0,
      (int t, ParkingRefund r) => t + r.amountCentavos,
    );
    final Color ownerColor = AppTheme.warning;
    final Color platformColor = spExitColor;

    Widget line(Color color, String who, int centavos, String why) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(who, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  why,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppTheme.textMuted,
                  ),
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
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Refunded to drivers',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    Text(
                      spPeso(total / 100),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                    Text(
                      <String>[
                        '$count ticket${count == 1 ? '' : 's'} refunded',
                        if (priced.length == count && paidTotal > 0)
                          'Out of ${spPeso(paidTotal / 100)} paid',
                      ].joinDots(),
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              if (inProgress.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    SpChip(
                      label: '${inProgress.length} in progress',
                      color: spInsideColor,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${spPeso(pending / 100)} on its way',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (total > 0) ...<Widget>[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 10,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (byOwner > 0)
                      Expanded(
                        flex: byOwner,
                        child: ColoredBox(color: ownerColor),
                      ),
                    if (byOwner > 0 && byPlatform > 0) const SizedBox(width: 2),
                    if (byPlatform > 0)
                      Expanded(
                        flex: byPlatform,
                        child: ColoredBox(color: platformColor),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          line(
            ownerColor,
            _admin ? 'Covered by owners' : 'Covered by you',
            byOwner,
            _admin
                ? 'Facility pulled for its own reasons: rates, complaints, '
                      'safety or not operating.'
                : 'Your facility was pulled for its own reasons: rates, '
                      'complaints, safety or not operating. It comes out of '
                      'your share only. SmartPark\'s commission and '
                      'PayMongo\'s fee are kept back from the refund.',
          ),
          line(
            platformColor,
            'Covered by SmartPark',
            byPlatform,
            'Pulled over permits or documents SmartPark had approved, or a '
                'dispute SmartPark agreed with.',
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
    'rejected' => ('Not approved · No refund', AppTheme.textMuted),
    _ => (r.statusLabel, AppTheme.textMuted),
  };

  /// The refund's steps for its status: labels, how many are done, and
  /// whether the current one is stuck. Null when there is nothing to show.
  ({List<String> labels, int done, bool stuck})? _steps(ParkingRefund r) {
    final String first = r.status == 'requested' || r.cause == 'driver_request'
        ? 'Driver asked'
        : 'Started';
    const String last = 'Refunded';
    return switch (r.status) {
      'requested' => (
        labels: <String>[first, 'In review', last],
        done: 1,
        stuck: false,
      ),
      'awaiting_exit' => (
        labels: <String>[first, 'Waits for exit', last],
        done: 1,
        stuck: false,
      ),
      'approved' || 'processing' => (
        labels: <String>[first, 'Sending', last],
        done: 1,
        stuck: false,
      ),
      'failed' => (
        labels: <String>[first, 'Delayed', last],
        done: 1,
        stuck: true,
      ),
      'sent' => (
        labels: <String>[first, 'Sent', 'Confirming'],
        done: 2,
        stuck: false,
      ),
      'refunded' => (
        labels: <String>[first, 'Sent', last],
        done: 3,
        stuck: false,
      ),
      _ => null,
    };
  }

  /// Three dots joined by lines: done (filled), current (ring), to come.
  Widget _stepper(ParkingRefund r) {
    final ({List<String> labels, int done, bool stuck})? s = _steps(r);
    if (s == null) return const SizedBox.shrink();
    final List<DateTime?> dates = <DateTime?>[
      r.createdAt,
      r.sentAt,
      r.refundedAt,
    ];
    final Color doneColor = spEntryColor;
    final Color nowColor = s.stuck ? spDeniedColor : spInsideColor;
    Widget step(int i) {
      final bool done = i < s.done;
      final bool now = i == s.done;
      final Color color = done
          ? doneColor
          : now
          ? nowColor
          : AppTheme.borderStrong;
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: done ? color : AppTheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: done
                      ? Icon(Icons.check, size: 9, color: AppTheme.surface)
                      : null,
                ),
                if (i < 2)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: i < s.done ? doneColor : AppTheme.border,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              s.labels[i],
              style: TextStyle(
                fontSize: 11,
                fontWeight: now ? FontWeight.w700 : FontWeight.w500,
                color: done || now ? AppTheme.textDark : AppTheme.textMuted,
              ),
            ),
            if (done && dates[i] != null)
              Text(
                spFormatDate(dates[i]!),
                style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[step(0), step(1), step(2)],
      ),
    );
  }

  /// How the amount was worked out, line by line, like a receipt.
  Widget _breakdown(ParkingRefund r) {
    final int? owed = r.ownerOwedCentavos;
    final TextStyle muted = TextStyle(
      fontSize: 12.5,
      color: AppTheme.textSecondary,
    );
    const List<FontFeature> figures = <FontFeature>[
      FontFeature.tabularFigures(),
    ];
    Widget money(
      String label,
      String value, {
      bool strong = false,
      bool minus = false,
      String? note,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: strong
                      ? TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        )
                      : muted,
                ),
                if (note != null)
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: AppTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            minus ? '− $value' : value,
            style: TextStyle(
              fontSize: strong ? 13 : 12.5,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: minus ? AppTheme.textSecondary : AppTheme.textDark,
              fontFeatures: figures,
            ),
          ),
        ],
      ),
    );
    String peso(int c) => spPeso(c / 100);
    final Widget rule = Divider(height: 12, color: AppTheme.border);

    final int smartParkPart = r.paidByOwner && owed != null
        ? r.amountCentavos - owed
        : 0;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (r.hasBreakdown) ...<Widget>[
            money('Ticket price', peso(r.ticketAmountCentavos)),
            if (r.keptCommissionCentavos > 0)
              money(
                'SmartPark commission',
                peso(r.keptCommissionCentavos),
                minus: true,
                note: 'Kept back, not refunded',
              ),
            if (r.keptProcessorFeeCentavos > 0)
              money(
                'PayMongo fee',
                peso(r.keptProcessorFeeCentavos),
                minus: true,
                note: 'Kept back, not refunded',
              ),
            if (!r.feesSaved)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  'Made before fees were kept back from refunds, so the '
                  'driver got the unused share of the full price.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            rule,
            money('Refundable part', peso(r.refundableCentavos)),
            money(
              'Unused hours',
              '${r.refundedHours} of ${r.totalHours}',
              note:
                  '${peso(r.refundableCentavos)} × ${r.refundedHours} ÷ '
                  '${r.totalHours} hours',
            ),
          ] else
            money('Unused hours', '${r.unusedHours}'),
          rule,
          money('Refunded to driver', peso(r.amountCentavos), strong: true),
          if (r.paidByOwner) ...<Widget>[
            money(
              _admin ? 'Charged to the owner' : 'Charged to you',
              peso(owed ?? r.amountCentavos),
              strong: true,
              note: smartParkPart > 0
                  ? 'SmartPark covers ${peso(smartParkPart)}, its commission '
                        'on the refund.'
                  : r.isPaidOut
                  ? 'Taken from your share of later online sales.'
                  : 'Charged once the refund is sent.',
            ),
          ] else
            money(
              'Covered by SmartPark',
              peso(r.amountCentavos),
              strong: true,
              note: _admin ? null : 'Nothing is charged to you.',
            ),
          rule,
          _reference('Ticket', r.ticketId),
          if (r.paymongoRefundId.isNotEmpty)
            _reference('PayMongo refund', r.paymongoRefundId),
        ],
      ),
    );
  }

  /// Paid, kept back, refunded: the three figures an owner checks first,
  /// shown without opening the calculation.
  Widget _moneyStrip(ParkingRefund r) {
    final int fees = r.keptCommissionCentavos + r.keptProcessorFeeCentavos;
    final int used = (r.refundableCentavos - r.amountCentavos).clamp(
      0,
      r.refundableCentavos,
    );
    final int kept = fees + used;
    Widget cell(String label, int centavos, String? note, {Color? color}) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
              Text(
                spPeso(centavos / 100),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color ?? AppTheme.textDark,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              if (note != null)
                Text(
                  note,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.3,
                    color: AppTheme.textMuted,
                  ),
                ),
            ],
          ),
        );
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border.all(color: spCardBorder),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          cell('Driver paid', r.ticketAmountCentavos, null),
          cell(
            'Not refunded',
            kept,
            fees > 0 && used > 0
                ? 'Fees ${spPeso(fees / 100)}\n'
                      'Hours used ${spPeso(used / 100)}'
                : fees > 0
                ? 'Fees'
                : used > 0
                ? 'Hours used'
                : null,
          ),
          cell(
            'Refunded',
            r.amountCentavos,
            '${r.refundedHours} of ${r.totalHours} hours',
            color: spEntryColor,
          ),
        ],
      ),
    );
  }

  /// An id to quote to SmartPark or PayMongo; long-press copies it.
  Widget _reference(String label, String id) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            id,
            textAlign: TextAlign.right,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _row(ParkingRefund r) {
    final (String statusLabel, Color statusColor) = _status(r);
    final bool busy = _busy.contains(r.ticketId);
    final bool open = _open.contains(r.ticketId);
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
    final String coveredBy = r.paidByOwner
        ? (_admin ? 'Covered by the owner' : 'Covered by you')
        : 'Covered by SmartPark';
    final Color coveredColor = r.paidByOwner ? AppTheme.warning : spExitColor;
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
    final List<String> meta = <String>[
      if (_admin && r.establishmentName.isNotEmpty) r.establishmentName,
      if (when != null)
        '${r.isRefunded ? 'Refunded' : 'Since'} ${spFormatDate(when)}',
      '${r.unusedHours} unused hour${r.unusedHours == 1 ? '' : 's'}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: spCardBorder),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            onTap: () => setState(
              () => open ? _open.remove(r.ticketId) : _open.add(r.ticketId),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    meta.joinDots(),
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    why.isEmpty
                        ? whatHappened
                        : '$whatHappened (${why.join(', ')})',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: coveredColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          coveredBy,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (r.hasBreakdown) _moneyStrip(r),
                  _stepper(r),
                  if (open) _breakdown(r),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            open
                                ? 'Hide the calculation'
                                : 'See the calculation',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: spExitColor,
                            ),
                          ),
                          Icon(
                            open
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                            color: spExitColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (disputeLine != null)
                  Text(
                    disputeLine,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                if (_admin && r.isFailed && r.failureReason.isNotEmpty)
                  Text(
                    r.failureReason,
                    style: TextStyle(fontSize: 11.5, color: spDeniedColor),
                  ),
                if (!_admin && r.canDispute && !r.isRejected)
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => _dispute(r),
                      icon: const Icon(Icons.gavel_rounded, size: 16),
                      label: Text(busy ? 'Sending...' : 'Dispute this charge'),
                    ),
                  ),
                if (_admin && r.hasOpenDispute)
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
                if (_admin && (r.isPendingApproval || r.isFailed))
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      if (r.isPendingApproval)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => _decide(r, approve: false),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                          ),
                          child: const Text('Reject'),
                        ),
                      const SizedBox(width: 6),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => _decide(r, approve: true),
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
            ),
          ),
        ],
      ),
    );
  }
}
