import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/error_reporter.dart';
import '../../../services/gate_cash.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../widgets/smartpark_ui.dart';
import '../../../widgets/sp_dialog.dart';

/// Cash each staff member took at the gate (overtime and walk-in fees) and
/// hasn't handed over yet, with "Received" to record the handover, and the
/// latest handovers as receipts: who, how much, when, received by whom.
class OwnerCashHandoverCard extends StatefulWidget {
  const OwnerCashHandoverCard({
    super.key,
    required this.facilityId,
    required this.ownerId,
    this.staffNames = const <String, String>{},
  });

  final String facilityId;
  final String ownerId;

  /// Staff uid -> name, from the owner's staff list.
  final Map<String, String> staffNames;

  @override
  State<OwnerCashHandoverCard> createState() => _OwnerCashHandoverCardState();
}

class _OwnerCashHandoverCardState extends State<OwnerCashHandoverCard> {
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs =
      <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

  /// Latest results of each gate cash query, merged by log id.
  final List<Map<String, Map<String, dynamic>>> _parts =
      <Map<String, Map<String, dynamic>>>[];
  bool _loaded = false;
  final Set<String> _busy = <String>{};

  /// Staff uid -> (name, role) for the facility, so a receipt can say who
  /// received the cash: the owner or a supervisor.
  Map<String, ({String name, bool supervisor})> _staff =
      <String, ({String name, bool supervisor})>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _staffSub;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _handovers =
      FirebaseFirestore.instance
          .collection('cash_handovers')
          .where('establishmentId', isEqualTo: widget.facilityId)
          .snapshots();

  @override
  void initState() {
    super.initState();
    final List<Query<Map<String, dynamic>>> queries = gateCashQueries(
      widget.facilityId,
    );
    for (int i = 0; i < queries.length; i++) {
      _parts.add(<String, Map<String, dynamic>>{});
      _subs.add(
        queries[i].snapshots().listen(
          (QuerySnapshot<Map<String, dynamic>> snap) {
            if (!mounted) return;
            setState(() {
              _parts[i] = <String, Map<String, dynamic>>{
                for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                    in snap.docs)
                  d.id: d.data(),
              };
              _loaded = true;
            });
          },
          onError: (Object error, StackTrace stack) =>
              reportError(error, stack, reason: 'Gate cash query'),
        ),
      );
    }
    // The rules let the owner list staff by ownerId and a supervisor by
    // facilityId.
    final CollectionReference<Map<String, dynamic>> staff = FirebaseFirestore
        .instance
        .collection('staff_accounts');
    final bool owner = FirebaseAuth.instance.currentUser?.uid == widget.ownerId;
    _staffSub =
        (owner
                ? staff.where('ownerId', isEqualTo: widget.ownerId)
                : staff.where('facilityId', isEqualTo: widget.facilityId))
            .snapshots()
            .listen(
              (QuerySnapshot<Map<String, dynamic>> snap) {
                if (!mounted) return;
                setState(() {
                  _staff = <String, ({String name, bool supervisor})>{
                    for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                        in snap.docs)
                      _uidOf(d): (
                        name: ((d.data()['name'] as String?) ?? '').trim(),
                        supervisor: d.data()['role'] == 'supervisor',
                      ),
                  };
                });
              },
              onError: (Object error, StackTrace stack) =>
                  reportError(error, stack, reason: 'Cash card staff names'),
            );
  }

  static String _uidOf(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final String uid = ((d.data()['userId'] as String?) ?? '').trim();
    return uid.isEmpty ? d.id : uid;
  }

  @override
  void dispose() {
    _staffSub?.cancel();
    for (final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> s
        in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Map<String, Map<String, dynamic>> get _logs => <String, Map<String, dynamic>>{
    for (final p in _parts) ...p,
  };

  String _name(StaffCashDue due) {
    final String listed = (widget.staffNames[due.staffId] ?? '').trim();
    if (listed.isNotEmpty) return listed;
    final String known = _staff[due.staffId]?.name ?? '';
    if (known.isNotEmpty) return known;
    return due.staffName.isNotEmpty ? due.staffName : 'Staff member';
  }

  Future<void> _receive(StaffCashDue due) async {
    final TextEditingController note = TextEditingController();
    final String name = _name(due);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        scrollable: true,
        icon: const SpDialogIcon(
          Icons.payments_outlined,
          tone: SpDialogTone.success,
        ),
        title: Text('Received ${spPeso(due.total)} from $name?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              <String>[
                if (due.overtime > 0) 'Overtime: ${spPeso(due.overtime)}',
                if (due.walkIn > 0) 'Walk-in fees: ${spPeso(due.walkIn)}',
                'From ${due.logIds.length} gate scan'
                    '${due.logIds.length == 1 ? '' : 's'}.',
              ].join('\n'),
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. short by PHP 20, will settle tomorrow',
                border: OutlineInputBorder(),
              ),
            ),
            Text(
              'This is saved as a receipt and can\'t be undone.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
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
            child: const Text('Mark received'),
          ),
        ],
      ),
    );
    final String noteText = note.text;
    spDisposeAfterClose(note);
    if (ok != true || !mounted) return;
    setState(() => _busy.add(due.staffId));
    try {
      await recordCashHandover(
        facilityId: widget.facilityId,
        ownerId: widget.ownerId,
        receivedBy: FirebaseAuth.instance.currentUser?.uid,
        due: due,
        staffName: name,
        logsById: _logs,
        note: noteText,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Recorded: received from $name.')));
    } catch (error, stack) {
      reportError(error, stack, reason: 'Cash handover');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(error, fallback: 'Could not save. Try again.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(due.staffId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<StaffCashDue> due = cashDueByStaff(
      _logs.entries.map((e) => (id: e.key, data: e.value)),
    );
    final double total = due.fold<double>(0, (a, d) => a + d.total);
    return SpSectionCard(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Cash to Receive',
      subtitle:
          'Overtime and walk-in fees staff took at the gate. The owner or a '
          'supervisor marks it received when it is handed over.',
      trailing: total > 0
          ? SpChip(label: spPeso(total), color: spInsideColor)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (due.isEmpty)
            Text(
              'Nothing to receive. All gate cash has been handed over.',
              style: TextStyle(color: AppTheme.textSecondary),
            )
          else
            for (final StaffCashDue d in due) _dueRow(d),
          const SizedBox(height: 12),
          _handoverSections(),
        ],
      ),
    );
  }

  Widget _dueRow(StaffCashDue d) {
    final bool busy = _busy.contains(d.staffId);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _name(d),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              // A supervisor never receives their own cash.
              if (d.staffId == FirebaseAuth.instance.currentUser?.uid)
                Text(
                  'The owner or another supervisor receives this',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                )
              else
                FilledButton(
                  onPressed: busy ? null : () => _receive(d),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.onAccent,
                  ),
                  child: Text(busy ? 'Saving...' : 'Received'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            spPeso(d.total),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          if (d.overtime > 0)
            _cashLine(Icons.timer_outlined, 'Overtime cash', d.overtime),
          if (d.walkIn > 0)
            _cashLine(Icons.directions_walk_rounded, 'Walk-in fees', d.walkIn),
          if (d.since != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'With them since ${spFormatDate(d.since!)} '
                '${spFormatClockTime(d.since!)}',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  /// One kind of cash in a staff member's total, labelled.
  Widget _cashLine(IconData icon, String label, double amount) {
    final TextStyle style = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: AppTheme.textDark,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: style)),
          Text(spPeso(amount), style: style),
        ],
      ),
    );
  }

  bool get _isOwner => FirebaseAuth.instance.currentUser?.uid == widget.ownerId;

  /// Cash supervisors received from staff and still hold, then the latest
  /// receipts.
  Widget _handoverSections() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _handovers,
      builder: (context, snapshot) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
            snapshot.data?.docs ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final List<SupervisorCashHeld> held = cashHeldBySupervisors(
          docs.map((d) => (id: d.id, data: d.data())),
          widget.ownerId,
        );
        final List<Map<String, dynamic>> recent =
            docs.map((d) => d.data()).toList()..sort(
              (a, b) => (spParseDateTime(b['receivedAt']) ?? DateTime(0))
                  .compareTo(spParseDateTime(a['receivedAt']) ?? DateTime(0)),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _heldSection(held),
            if (recent.isNotEmpty) ...<Widget>[
              Text(
                'Recent handovers',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              for (final Map<String, dynamic> h in recent.take(5))
                _handoverRow(h),
            ],
          ],
        );
      },
    );
  }

  /// Supervisors holding cash for the owner. The owner marks it received;
  /// a supervisor sees only what they hold, to hand to the owner.
  Widget _heldSection(List<SupervisorCashHeld> held) {
    final String? me = FirebaseAuth.instance.currentUser?.uid;
    final List<SupervisorCashHeld> shown = _isOwner
        ? held
        : held.where((h) => h.supervisorId == me).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _isOwner ? 'With supervisors' : 'With you, for the owner',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _isOwner
                ? 'Cash a supervisor received from staff. Mark it received '
                      'when they hand it to you.'
                : 'Cash you received from staff. Hand it to the owner; they '
                      'mark it received.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          for (final SupervisorCashHeld h in shown) _heldRow(h),
        ],
      ),
    );
  }

  Widget _heldRow(SupervisorCashHeld h) {
    final String key = 'held_${h.supervisorId}';
    final bool busy = _busy.contains(key);
    final String name = _staff[h.supervisorId]?.name ?? '';
    final int count = h.handoverIds.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _isOwner ? (name.isEmpty ? 'Supervisor' : name) : 'You hold',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  '${spPeso(h.total)} · $count handover'
                  '${count == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          if (_isOwner)
            FilledButton(
              onPressed: busy ? null : () => _receiveFromSupervisor(h, name),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.onAccent,
              ),
              child: Text(busy ? 'Saving...' : 'Received'),
            ),
        ],
      ),
    );
  }

  Future<void> _receiveFromSupervisor(SupervisorCashHeld h, String name) async {
    final String who = name.isEmpty ? 'the supervisor' : name;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const SpDialogIcon(
          Icons.payments_outlined,
          tone: SpDialogTone.success,
        ),
        title: Text('Received ${spPeso(h.total)} from $who?'),
        content: const Text(
          'This is saved on each handover and can\'t be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark received'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final String key = 'held_${h.supervisorId}';
    setState(() => _busy.add(key));
    try {
      await recordSupervisorCashToOwner(ownerId: widget.ownerId, held: h);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Recorded: received from $who.')));
    } catch (error, stack) {
      reportError(error, stack, reason: 'Supervisor cash to owner');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(error, fallback: 'Could not save. Try again.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  /// Who took the cash: "the owner", "you", "Maria Santos (supervisor)",
  /// or "a supervisor" while names load. Records made before supervisors
  /// existed were all the owner's.
  String _receiverLabel(Map<String, dynamic> h) {
    final String by = ((h['receivedBy'] as String?) ?? '').trim();
    if (by == FirebaseAuth.instance.currentUser?.uid) return 'you';
    if (by.isEmpty || by == widget.ownerId) return 'the owner';
    final String name = _staff[by]?.name ?? '';
    return name.isEmpty ? 'a supervisor' : '$name (supervisor)';
  }

  /// One received handover: the amount and when, then who and what for.
  Widget _handoverRow(Map<String, dynamic> h) {
    final DateTime? at = spParseDateTime(h['receivedAt']);
    final String name = ((h['staffName'] as String?) ?? '').trim();
    final String note = ((h['note'] as String?) ?? '').trim();
    final String parts = _handoverParts(h);
    final String receiver = _receiverLabel(h);
    // A supervisor's handover also says whether the owner has the cash.
    final String passedOn = heldBySupervisor(h, widget.ownerId)
        ? ' · Not yet with the owner'
        : (h['ownerReceivedAt'] != null ? ' · Now with the owner' : '');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: AppTheme.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  spPeso(((h['amount'] as num?) ?? 0).toDouble()),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              if (at != null)
                Text(
                  '${spFormatDate(at)} · ${spFormatClockTime(at)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text(
              'From ${name.isEmpty ? 'staff' : name}$parts'
              '\nReceived by $receiver$passedOn'
              '${note.isEmpty ? '' : '\n"$note"'}',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// " · overtime PHP 30.00 + walk-in PHP 30.00" from a handover record.
  String _handoverParts(Map<String, dynamic> h) {
    final double overtime = ((h['overtimeAmount'] as num?) ?? 0).toDouble();
    final double walkIn = ((h['walkInAmount'] as num?) ?? 0).toDouble();
    final List<String> parts = <String>[
      if (overtime > 0) 'Overtime ${spPeso(overtime)}',
      if (walkIn > 0) 'Walk-in ${spPeso(walkIn)}',
    ];
    return parts.isEmpty ? '' : ' · ${parts.join(' + ')}';
  }
}
