import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/admin_access.dart';
import '../../services/announcements.dart';
import '../../services/platform_fees.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_dialog.dart';

/// Settings › Commission rate: the rate now, any scheduled change and how
/// many owners acknowledged it. A super admin schedules or calls off a
/// change (functions/src/commission.js); owners are told in the app at
/// least 30 days before a higher rate.
class AdminCommissionCard extends StatefulWidget {
  const AdminCommissionCard({super.key});

  @override
  State<AdminCommissionCard> createState() => _AdminCommissionCardState();
}

class _AdminCommissionCardState extends State<AdminCommissionCard> {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );
  bool _busy = false;

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _settings =>
      FirebaseFirestore.instance
          .collection('settings')
          .doc('platform')
          .snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _me => FirebaseFirestore
      .instance
      .collection('users')
      .doc(FirebaseAuth.instance.currentUser?.uid ?? '-')
      .snapshots();

  Future<void> _call(
    String name,
    Map<String, dynamic> data,
    String done,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _functions.httpsCallable(name).call(data);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyError(error, fallback: 'Could not save.')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _schedule(double current) async {
    final ({double rate, DateTime at, String message})? picked =
        await showDialog<({double rate, DateTime at, String message})>(
          context: context,
          builder: (_) => _ScheduleDialog(current: current),
        );
    if (picked == null) return;
    await _call('scheduleCommissionChange', <String, dynamic>{
      'rate': picked.rate,
      'effectiveAt': picked.at.millisecondsSinceEpoch,
      'message': picked.message,
    }, 'Scheduled. Owners have been told.');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _me,
      builder: (BuildContext context, meSnap) {
        final bool superAdmin =
            accessLevelOf(meSnap.data?.data()) == AccessLevel.superAdmin;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _settings,
          builder: (BuildContext context, snap) {
            final PlatformCommissionSettings c = PlatformCommissionSettings.of(
              snap.data?.data(),
            );
            return SpSectionCard(
              icon: Icons.percent_rounded,
              title: 'Commission rate',
              subtitle:
                  'SmartPark\'s share of each payment made in the app. A '
                  'change applies only to purchases from its date.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Now ${commissionPercent(c.currentRate)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textDark,
                    ),
                  ),
                  if (c.hasPending) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      '${commissionPercent(c.pendingRate!)} from '
                      '${spFormatDate(c.pendingEffectiveAt!)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: spInsideColor,
                      ),
                    ),
                    if (c.pendingAnnouncementId.isNotEmpty)
                      _AckCount(announcementId: c.pendingAnnouncementId),
                  ],
                  const SizedBox(height: 12),
                  if (!superAdmin)
                    Text(
                      'Only a super admin can change the rate.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    )
                  else if (c.hasPending)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _call(
                              'cancelCommissionChange',
                              <String, dynamic>{},
                              'Change called off. Owners have been told.',
                            ),
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Call off the change'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _schedule(c.currentRate),
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: const Text('Schedule a change'),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// "12 of 15 owners acknowledged": the record if an owner later disputes
/// the change.
class _AckCount extends StatelessWidget {
  const _AckCount({required this.announcementId});

  final String announcementId;

  Future<(int, int)> _load() async {
    final AggregateQuerySnapshot owners = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'Parking Owner')
        .count()
        .get();
    final int acked = await AnnouncementService().acknowledgedCount(
      announcementId,
    );
    return (acked, owners.count ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(int, int)>(
      future: _load(),
      builder: (BuildContext context, snap) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          snap.hasData
              ? '${snap.data!.$1} of ${snap.data!.$2} owners acknowledged'
              : snap.hasError
              ? 'Acknowledgements unavailable'
              : 'Counting acknowledgements…',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
      ),
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.current});

  final double current;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late final TextEditingController _percent = TextEditingController(
    text: (widget.current * 100).toStringAsFixed(1),
  );
  final TextEditingController _message = TextEditingController();
  DateTime _at = DateTime.now().add(const Duration(days: 31));
  String? _error;

  @override
  void dispose() {
    _percent.dispose();
    _message.dispose();
    super.dispose();
  }

  double? get _rate {
    final double? p = double.tryParse(_percent.text.trim());
    return p == null ? null : p / 100;
  }

  @override
  Widget build(BuildContext context) {
    final double? rate = _rate;
    final DateTime earliest = DateTime.now().add(
      Duration(days: rate != null && rate < widget.current ? 1 : 30),
    );
    return AlertDialog(
      icon: const SpDialogIcon(Icons.percent_rounded, tone: SpDialogTone.info),
      title: const Text('Schedule a commission change'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _percent,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(
                labelText: 'New rate (%)',
                helperText: '1% to 15%',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final DateTime? day = await showDatePicker(
                  context: context,
                  initialDate: _at.isBefore(earliest) ? earliest : _at,
                  firstDate: DateTime.now().add(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (day != null) setState(() => _at = day);
              },
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text('Takes effect ${spFormatDate(_at)}'),
            ),
            Text(
              'A higher rate needs 30 days\' notice; a lower one may start '
              'tomorrow.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Message to owners (optional)',
              ),
            ),
            if (rate != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Preview: on a PHP 100 sale, SmartPark keeps '
                '${spPeso(100 * widget.current)} now and '
                '${spPeso(100 * rate)} from ${spFormatDate(_at)}.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
            if (_error != null)
              Text(_error!, style: TextStyle(color: spDeniedColor)),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (rate == null || rate < 0.01 || rate > 0.15) {
              setState(() => _error = 'Pick a rate from 1% to 15%.');
              return;
            }
            // Midnight starts the day; the server checks the notice too.
            final DateTime at = DateTime(_at.year, _at.month, _at.day);
            if (at.isBefore(earliest)) {
              setState(
                () => _error = rate > widget.current
                    ? 'A higher rate needs at least 30 days\' notice.'
                    : 'A lower rate can start tomorrow at the earliest.',
              );
              return;
            }
            Navigator.of(
              context,
            ).pop((rate: rate, at: at, message: _message.text.trim()));
          },
          child: const Text('Send to owners'),
        ),
      ],
    );
  }
}
