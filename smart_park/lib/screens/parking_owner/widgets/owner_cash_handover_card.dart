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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _name(d),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  <String>[
                    spPeso(d.total),
                    if (d.overtime > 0 && d.walkIn > 0)
                      'overtime ${spPeso(d.overtime)} + walk-in ${spPeso(d.walkIn)}',
                    if (d.since != null) 'since ${spFormatDate(d.since!)}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
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
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            for (final Map<String, dynamic> h in recent.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${spPeso(((h['amount'] as num?) ?? 0).toDouble())} from '
                  '${(h['staffName'] as String?)?.trim().isNotEmpty == true ? h['staffName'] : 'staff'}'
                  '${spParseDateTime(h['receivedAt']) == null ? '' : ' · ${spFormatDate(spParseDateTime(h['receivedAt'])!)} ${spFormatClockTime(spParseDateTime(h['receivedAt'])!)}'}'
                  '${((h['note'] as String?) ?? '').trim().isEmpty ? '' : ' · "${(h['note'] as String).trim()}"'}',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textDark),
                ),
              ),
          ],
        );
      },
    );
  }
}
