import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/error_reporter.dart';
import '../../../services/gate_cash.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../widgets/smartpark_ui.dart';

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
  }

  @override
  void dispose() {
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
    return due.staffName.isNotEmpty ? due.staffName : 'Staff member';
  }

  Future<void> _receive(StaffCashDue due) async {
    final TextEditingController note = TextEditingController();
    final String name = _name(due);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
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
                hintText: 'e.g. short by ₱20, will settle tomorrow',
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
    note.dispose();
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
          'Overtime and walk-in fees your staff took at the gate. Mark it '
          'received when they hand it over.',
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
          _recentHandovers(),
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
              // A supervisor's own cash is received by the owner, not by them.
              if (d.staffId == FirebaseAuth.instance.currentUser?.uid)
                Text(
                  'The owner receives this',
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

  Widget _recentHandovers() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _handovers,
      builder: (context, snapshot) {
        final List<Map<String, dynamic>> recent =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .map((d) => d.data())
                .toList()
              ..sort(
                (a, b) => (spParseDateTime(b['receivedAt']) ?? DateTime(0))
                    .compareTo(spParseDateTime(a['receivedAt']) ?? DateTime(0)),
              );
        if (recent.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
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
        );
      },
    );
  }

  /// One received handover: the amount and when, then who and what for.
  Widget _handoverRow(Map<String, dynamic> h) {
    final DateTime? at = spParseDateTime(h['receivedAt']);
    final String name = ((h['staffName'] as String?) ?? '').trim();
    final String note = ((h['note'] as String?) ?? '').trim();
    final String parts = _handoverParts(h);
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
      if (overtime > 0) 'overtime ${spPeso(overtime)}',
      if (walkIn > 0) 'walk-in ${spPeso(walkIn)}',
    ];
    return parts.isEmpty ? '' : ' · ${parts.join(' + ')}';
  }
}
