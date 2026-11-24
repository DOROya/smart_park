import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../services/facility_contact.dart';
import '../theme/app_theme.dart';
import 'smartpark_ui.dart';

/// A facility's contact number: selectable, with Call and Copy. `tel:`
/// links don't open on every phone, so the number always stays readable
/// and copyable. Nothing is shown when [stored] is empty.
class SpFacilityContactRow extends StatelessWidget {
  const SpFacilityContactRow({super.key, required this.stored});

  final String stored;

  /// The number from `establishments/{facilityId}`, live.
  static Widget forFacility(String facilityId) {
    if (facilityId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('establishments')
          .doc(facilityId)
          .snapshots(),
      builder: (BuildContext context, snap) => SpFacilityContactRow(
        stored: ((snap.data?.data()?['contactNumber'] as String?) ?? '').trim(),
      ),
    );
  }

  Future<void> _call(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    bool opened = false;
    try {
      opened = await launchUrl(
        Uri(scheme: 'tel', path: dialableFacilityContact(stored)),
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the dialer. Call '
            '${displayFacilityContact(stored)}.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (stored.trim().isEmpty) return const SizedBox.shrink();
    final String shown = displayFacilityContact(stored);
    return Row(
      children: <Widget>[
        Icon(Icons.phone_outlined, size: 18, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            shown,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy number',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.copy_rounded, size: 18, color: AppTheme.textMuted),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: shown));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Number copied.')));
            }
          },
        ),
        OutlinedButton.icon(
          onPressed: () => _call(context),
          icon: const Icon(Icons.call_rounded, size: 18),
          label: const Text('Call'),
          style: OutlinedButton.styleFrom(
            foregroundColor: spEntryColor,
            side: BorderSide(color: spCardBorder),
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ],
    );
  }
}
