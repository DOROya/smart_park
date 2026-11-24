import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'sp_terms_view.dart' show SpTermsBody;
import '../services/announcements.dart';
import '../services/platform_fees.dart' show commissionPercent;
import '../theme/app_theme.dart';
import 'smartpark_ui.dart';

/// Pops up announcements for the signed-in [role], one at a time, when the
/// app opens or comes back: never seen ones, and a commission change until
/// it is acknowledged (up to its date). Only while [isCurrent] says this
/// screen is on top, so never over the gate scanner.
class AnnouncementWatcher with WidgetsBindingObserver {
  AnnouncementWatcher(
    this._context,
    this.role, {
    AnnouncementService? service,
    this.isCurrent,
  }) : _service = service ?? AnnouncementService();

  final BuildContext Function() _context;
  final String role;
  final AnnouncementService _service;

  /// Whether the watching screen is the one on top (no scanner over it).
  final bool Function()? isCurrent;
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

  Future<void> check() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (_checking || uid == null) return;
    _checking = true;
    try {
      final List<Announcement> show = announcementsToShow(
        await _service.forRole(role),
        await _service.reads(uid),
      );
      for (final Announcement a in show) {
        final BuildContext context = _context();
        if (!context.mounted || !(isCurrent?.call() ?? true)) return;
        if (!a.isCommissionChange) {
          // Seen once shown, however the dialog is closed.
          unawaited(_service.markSeen(uid, a.id).catchError((Object _) {}));
        }
        final bool? understood = await showDialog<bool>(
          context: context,
          builder: (_) => AnnouncementDialog(announcement: a, role: role),
        );
        if (a.isCommissionChange) {
          await (understood == true
                  ? _service.acknowledge(uid, a.id)
                  : _service.markSeen(uid, a.id))
              .catchError((Object _) {});
        }
      }
    } catch (_) {
      // Offline or unreadable: try again the next time the app opens.
    } finally {
      _checking = false;
    }
  }
}

/// One announcement. A commission change shows the old and new rate, a
/// PHP 100 example, a link to the terms and "I understand".
class AnnouncementDialog extends StatelessWidget {
  const AnnouncementDialog({
    super.key,
    required this.announcement,
    required this.role,
  });

  final Announcement announcement;
  final String role;

  @override
  Widget build(BuildContext context) {
    final Announcement a = announcement;
    final double? from = a.oldRate;
    final double? to = a.newRate;
    return AlertDialog(
      title: Text(a.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (a.isCommissionChange && from != null && to != null) ...[
              Row(
                children: <Widget>[
                  SpChip(
                    label: commissionPercent(from),
                    color: AppTheme.textMuted,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 18),
                  ),
                  SpChip(label: commissionPercent(to), color: spInsideColor),
                  if (a.effectiveAt != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      'from ${spFormatDate(a.effectiveAt!)}',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text(a.body),
            if (a.isCommissionChange) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (BuildContext c) => AlertDialog(
                    title: const Text('Terms and Conditions'),
                    content: SizedBox(
                      width: 480,
                      child: SingleChildScrollView(
                        child: SpTermsBody(role: role),
                      ),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(c).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                icon: const Icon(Icons.gavel_rounded, size: 18),
                label: const Text('Read the updated terms'),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        if (a.isCommissionChange) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('I understand'),
          ),
        ] else
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('OK'),
          ),
      ],
    );
  }
}

/// Profile › Announcements: every announcement for [role], newest first,
/// to read again.
class SpAnnouncementsCard extends StatefulWidget {
  const SpAnnouncementsCard({super.key, required this.role, this.service});

  final String role;
  final AnnouncementService? service;

  @override
  State<SpAnnouncementsCard> createState() => _SpAnnouncementsCardState();
}

class _SpAnnouncementsCardState extends State<SpAnnouncementsCard> {
  late final Future<List<Announcement>> _all =
      (widget.service ?? AnnouncementService()).forRole(widget.role);

  @override
  Widget build(BuildContext context) {
    return SpSectionCard(
      icon: Icons.campaign_outlined,
      title: 'Announcements',
      subtitle: 'Notices from SmartPark, such as commission changes.',
      child: FutureBuilder<List<Announcement>>(
        future: _all,
        builder: (BuildContext context, snap) {
          final List<Announcement> list = snap.data ?? const <Announcement>[];
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            );
          }
          if (list.isEmpty) {
            return Text(
              'No announcements yet.',
              style: TextStyle(color: AppTheme.textMuted),
            );
          }
          return Column(
            children: <Widget>[
              for (final Announcement a in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    a.isCommissionChange
                        ? Icons.percent_rounded
                        : Icons.campaign_outlined,
                  ),
                  title: Text(a.title),
                  subtitle: a.createdAt == null
                      ? null
                      : Text(spFormatDate(a.createdAt!)),
                  onTap: () => showDialog<bool>(
                    context: context,
                    builder: (_) =>
                        AnnouncementDialog(announcement: a, role: widget.role),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
