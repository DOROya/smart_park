import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../services/driver_reports.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/smartpark_ui.dart';

/// Shows the signed-in driver, once, the warnings the SmartPark admin sent
/// since they last opened the app. Checked when the app opens or comes back
/// to the foreground, never in the middle of use (e.g. at a gate). A warning
/// counts as seen as soon as it pops up (`acknowledgedAt`), so it never pops
/// up again; Account Notices on the Profile keeps every warning to read
/// later. Reports themselves are never shown to drivers, only the warning.
class DriverWarningWatcher with WidgetsBindingObserver {
  DriverWarningWatcher(
    this._context,
    this.driverId, {
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final BuildContext Function() _context;
  final String driverId;
  final FirebaseFirestore _db;
  bool _checking = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(check());
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  /// Pops up the warnings not seen yet, oldest first, in one dialog.
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await _db
          .collection('driver_warnings')
          .where('driverId', isEqualTo: driverId)
          .get();
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> unseen =
          snap.docs.where((d) => d.data()['acknowledgedAt'] == null).toList()
            ..sort(
              (a, b) =>
                  (spParseDateTime(a.data()['createdAt']) ?? DateTime.now())
                      .compareTo(
                        spParseDateTime(b.data()['createdAt']) ??
                            DateTime.now(),
                      ),
            );
      if (unseen.isEmpty) return;
      final BuildContext context = _context();
      if (!context.mounted) return;
      // Seen once shown, however the dialog is closed. If saving fails it
      // pops up again next time rather than never.
      unawaited(
        Future.wait(<Future<void>>[
          for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in unseen)
            acknowledgeDriverWarning(doc.id, firestore: _db),
        ]).catchError((Object _) => <void>[]),
      );
      await showDialog<void>(
        context: context,
        builder: (_) => _WarningDialog(
          warnings: <Map<String, dynamic>>[
            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                in unseen)
              doc.data(),
          ],
        ),
      );
    } catch (_) {
      // Offline or unreadable: try again the next time the app opens.
    } finally {
      _checking = false;
    }
  }
}

/// The reasons a warning was sent for, as small labels. Older warnings may
/// still name "Other", which tells the driver nothing, so it is left out.
class _ReasonChips extends StatelessWidget {
  const _ReasonChips({required this.warning});

  final Map<String, dynamic> warning;

  @override
  Widget build(BuildContext context) {
    final List<String> reasons = warningReasons(warning);
    if (reasons.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final String reason in reasons)
          SpChip(label: reason, color: AppTheme.accentText),
      ],
    );
  }
}

/// Where and when a warning's report came from, e.g. "Mall Parking ·
/// Oct 21, 2026".
String _warningSource(Map<String, dynamic> warning) {
  final String facility = ((warning['establishmentName'] as String?) ?? '')
      .trim();
  final DateTime? at = spParseDateTime(warning['createdAt']);
  return <String>[
    if (facility.isNotEmpty) facility,
    if (at != null) spFormatDate(at),
  ].join(' · ');
}

class _WarningDialog extends StatelessWidget {
  const _WarningDialog({required this.warnings});

  final List<Map<String, dynamic>> warnings;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: AppTheme.warning,
        size: 36,
      ),
      title: Text(
        warnings.length == 1
            ? 'Warning from SmartPark'
            : '${warnings.length} warnings from SmartPark',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < warnings.length; i++) ...[
                if (i > 0) const Divider(height: 24),
                _ReasonChips(warning: warnings[i]),
                const SizedBox(height: 10),
                Text(
                  ((warnings[i]['message'] as String?) ?? '').trim(),
                  style: TextStyle(height: 1.4, color: AppTheme.textDark),
                ),
                if (_warningSource(warnings[i]).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _warningSource(warnings[i]),
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              Text(
                'You can read this again under Account Notices in your '
                'Profile.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('I understand'),
        ),
      ],
    );
  }
}

/// Profile card listing every warning the SmartPark admin has sent the
/// driver, newest first, so one already seen can be read again.
class DriverNoticesCard extends StatefulWidget {
  const DriverNoticesCard({super.key, required this.driverId, this.firestore});

  final String driverId;
  final FirebaseFirestore? firestore;

  @override
  State<DriverNoticesCard> createState() => _DriverNoticesCardState();
}

class _DriverNoticesCardState extends State<DriverNoticesCard> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _warnings =
      (widget.firestore ?? FirebaseFirestore.instance)
          .collection('driver_warnings')
          .where('driverId', isEqualTo: widget.driverId)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _warnings,
      builder: (BuildContext context, snapshot) {
        final List<Map<String, dynamic>> notices =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .map((d) => d.data())
                .toList()
              ..sort(
                (a, b) => (spParseDateTime(b['createdAt']) ?? DateTime.now())
                    .compareTo(
                      spParseDateTime(a['createdAt']) ?? DateTime.now(),
                    ),
              );
        return SpSectionCard(
          icon: Icons.notifications_outlined,
          title: 'Account Notices',
          subtitle: 'Warnings from SmartPark about your parking.',
          trailing: notices.isEmpty
              ? null
              : SpChip(label: '${notices.length}', color: AppTheme.accentText),
          child: !snapshot.hasData
              ? const SizedBox(
                  height: 24,
                  child: Center(child: LinearProgressIndicator()),
                )
              : notices.isEmpty
              ? const SpEmptyState(
                  boxed: false,
                  icon: Icons.verified_outlined,
                  message: 'No notices. Your account is in good standing.',
                )
              : Column(
                  children: [
                    for (final Map<String, dynamic> notice in notices)
                      _NoticeRow(notice: notice),
                  ],
                ),
        );
      },
    );
  }
}

/// One warning, collapsed to its reasons, date and the start of the message
/// to save space; tapping shows the whole thing.
class _NoticeRow extends StatefulWidget {
  const _NoticeRow({required this.notice});

  final Map<String, dynamic> notice;

  @override
  State<_NoticeRow> createState() => _NoticeRowState();
}

class _NoticeRowState extends State<_NoticeRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> notice = widget.notice;
    final DateTime? at = spParseDateTime(notice['createdAt']);
    final List<String> reasons = warningReasons(notice);
    final String facility = ((notice['establishmentName'] as String?) ?? '')
        .trim();
    final String message = ((notice['message'] as String?) ?? '').trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.warningSoft,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
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
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: AppTheme.accentText,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          reasons.isEmpty ? 'Warning' : reasons.join(', '),
                          maxLines: _expanded ? null : 1,
                          overflow: _expanded ? null : TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                      if (at != null)
                        Text(
                          spFormatDate(at),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 20,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    maxLines: _expanded ? null : 2,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  if (_expanded && facility.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Facility: $facility',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ],
                  if (!_expanded) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Tap to read more',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accentText,
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
