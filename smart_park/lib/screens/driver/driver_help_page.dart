import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../content/driver_help_content.dart';
import '../../content/terms_content.dart' show kSupportEmail;
import '../../theme/app_theme.dart';
import '../../widgets/smartpark_ui.dart';
import 'driver_guide_page.dart';

/// Help & FAQ for drivers: the guide again, common questions, and how to
/// reach SmartPark.
class DriverHelpPage extends StatelessWidget {
  const DriverHelpPage({super.key});

  Future<void> _email(BuildContext context) async {
    final Uri uri = Uri(
      scheme: 'mailto',
      path: kSupportEmail,
      query: 'subject=${Uri.encodeComponent('SmartPark help')}',
    );
    bool opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;
    // No email app: copy the address instead.
    await Clipboard.setData(const ClipboardData(text: kSupportEmail));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No email app found. Address copied: $kSupportEmail'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Help & FAQ'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          SpSectionCard(
            icon: Icons.school_outlined,
            title: 'How SmartPark works',
            subtitle:
                'Four short steps: finding parking, the temporary QR, paying '
                'at the gate, and using your ticket.',
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => const DriverGuidePage(),
                  ),
                ),
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: const Text(
                  'Show the guide',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
          ),
          for (final DriverFaqGroup group in kDriverFaqGroups) ...<Widget>[
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Icon(group.icon, size: 18, color: AppTheme.textMuted),
                const SizedBox(width: 6),
                Text(
                  group.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Material(
              color: AppTheme.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                side: BorderSide(color: spCardBorder),
              ),
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < group.items.length; i++) ...<Widget>[
                    if (i > 0) Divider(height: 1, color: spCardBorder),
                    _FaqTile(faq: group.items[i]),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SpSectionCard(
            icon: Icons.mail_outline_rounded,
            title: 'Still need help?',
            subtitle:
                'Email the SmartPark team. Include the facility, the time '
                'and, for payments, the amount.',
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _email(context),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text(
                  'Email $kSupportEmail',
                  overflow: TextOverflow.ellipsis,
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.onAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.faq});

  final DriverFaq faq;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          faq.question,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.textDark,
          ),
        ),
        children: <Widget>[
          Text(
            faq.answer,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
