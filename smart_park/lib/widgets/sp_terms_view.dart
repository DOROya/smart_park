import 'package:flutter/material.dart';

import '../content/terms_content.dart';
import '../theme/app_theme.dart';
import 'smartpark_ui.dart';

/// The terms for [role] as headed sections of bullet points, under the date
/// they were last updated.
class SpTermsBody extends StatelessWidget {
  const SpTermsBody({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final List<TermsSection> sections = termsFor(role);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Last updated $kTermsUpdatedLabel',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        for (final TermsSection section in sections) ...[
          const SizedBox(height: 16),
          Text(
            section.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          for (final String point in section.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppTheme.accentText,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      point,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// The terms on their own page, opened from the Profile.
class SpTermsPage extends StatelessWidget {
  const SpTermsPage({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        surfaceTintColor: AppTheme.surface,
        title: const Text('Terms and Conditions'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [SpTermsBody(role: role)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Profile card that opens the terms the user agreed to at sign-up.
class SpTermsCard extends StatelessWidget {
  const SpTermsCard({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return SpSectionCard(
      icon: Icons.gavel_rounded,
      title: 'Terms and Privacy',
      subtitle: 'The terms you agreed to, and how SmartPark uses your data.',
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => SpTermsPage(role: role)),
          ),
          icon: const Icon(Icons.description_outlined, size: 18),
          label: const Text(
            'Read Terms and Conditions',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            foregroundColor: AppTheme.textDark,
            side: BorderSide(color: AppTheme.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
          ),
        ),
      ),
    );
  }
}
