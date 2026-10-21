import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../services/driver_reports.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/smartpark_ui.dart';

/// Watches the signed-in driver's warnings from the SmartPark admin and
/// shows each unread one in a dialog the driver has to acknowledge. Live, so
/// a warning sent while the app is open appears straight away. Reports
/// themselves are never shown to drivers, only the admin's warning.
class DriverWarningWatcher {
  DriverWarningWatcher(this._context, this.driverId);

  final BuildContext Function() _context;
  final String driverId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _showing = false;

  void start() {
    _sub = FirebaseFirestore.instance
        .collection('driver_warnings')
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .listen(_onWarnings, onError: (Object _) {});
  }

  void dispose() => unawaited(_sub?.cancel());

  Future<void> _onWarnings(QuerySnapshot<Map<String, dynamic>> snap) async {
    if (_showing) return;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> unread =
        snap.docs.where((d) => d.data()['acknowledgedAt'] == null).toList()
          ..sort(
            (a, b) => (spParseDateTime(a.data()['createdAt']) ?? DateTime.now())
                .compareTo(
                  spParseDateTime(b.data()['createdAt']) ?? DateTime.now(),
                ),
          );
    if (unread.isEmpty) return;
    final BuildContext context = _context();
    if (!context.mounted) return;
    _showing = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WarningDialog(doc: unread.first),
    );
    _showing = false;
  }
}

class _WarningDialog extends StatefulWidget {
  const _WarningDialog({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  State<_WarningDialog> createState() => _WarningDialogState();
}

class _WarningDialogState extends State<_WarningDialog> {
  bool _saving = false;

  Future<void> _acknowledge() async {
    setState(() => _saving = true);
    try {
      await acknowledgeDriverWarning(widget.doc.id);
    } catch (_) {
      // Shown again next time; don't trap the driver in the dialog.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> data = widget.doc.data();
    final DateTime? at = spParseDateTime(data['createdAt']);
    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: AppTheme.warning,
        size: 36,
      ),
      title: const Text('Warning from SmartPark'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (((data['reason'] as String?) ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SpChip(
                label: data['reason'] as String,
                color: AppTheme.accentText,
              ),
            ),
          Text(
            ((data['message'] as String?) ?? '').trim(),
            style: TextStyle(height: 1.4, color: AppTheme.textDark),
          ),
          if (at != null) ...[
            const SizedBox(height: 10),
            Text(
              'Sent ${spFormatDate(at)}',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: _saving ? null : _acknowledge,
          child: Text(_saving ? 'Saving...' : 'I understand'),
        ),
      ],
    );
  }
}
