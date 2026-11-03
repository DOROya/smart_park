import 'package:flutter/material.dart';

import '../../content/terms_content.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_terms_view.dart';
import 'verify_email_screen.dart';

class TermsScreen extends StatefulWidget {
  final String role;
  final String firstName;
  final String lastName;
  final String email;
  final String password;

  const TermsScreen({
    super.key,
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.password,
  });

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _agreed = false;

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _goToVerifyEmail() {
    if (!_agreed) {
      _showSnackBar(
        'You must agree to the Terms and Conditions before continuing.',
      );
      return;
    }

    if (widget.role != kDriverRole && widget.role != kParkingOwnerRole) {
      _showSnackBar('Invalid role selected. Please go back and choose again.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VerifyEmailScreen(
          firstName: widget.firstName,
          lastName: widget.lastName,
          email: widget.email,
          role: widget.role,
          password: widget.password,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthBadge(
            icon: Icons.description_outlined,
            label: 'Step 3 of 3 · Terms',
          ),
          const SizedBox(height: 14),
          const AuthHeader(
            first: 'Terms ',
            accent: 'and Conditions.',
            subtitle: 'Please review and agree before continuing.',
          ),
          const SizedBox(height: 24),
          AuthFormCard(
            icon: Icons.gavel_rounded,
            title: '${widget.role} Terms',
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
                child: termsFor(widget.role).isEmpty
                    ? Text(
                        'Invalid role selected. Please go back and choose a '
                        'valid role.',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppTheme.textDark,
                          height: 1.5,
                        ),
                      )
                    : SpTermsBody(role: widget.role),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: _agreed ? AppTheme.accentSoft : AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              side: BorderSide(color: _agreed ? AppTheme.accent : spCardBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: CheckboxListTile(
              value: _agreed,
              onChanged: (value) {
                setState(() {
                  _agreed = value ?? false;
                });
              },
              activeColor: AppTheme.accentText,
              title: const Text(
                'I have read and agree to the Terms and Conditions and the '
                'Privacy Notice.',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
          const SizedBox(height: 24),
          PrimaryAuthButton(
            text: 'Create Account',
            icon: Icons.arrow_forward_rounded,
            enabled: _agreed,
            onPressed: _goToVerifyEmail,
          ),
        ],
      ),
    );
  }
}
