import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/smartpark_ui.dart';
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
  static const String _driverRole = 'Driver';
  static const String _parkingOwnerRole = 'Parking Owner';

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

    if (widget.role != _driverRole && widget.role != _parkingOwnerRole) {
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

  String _getPlaceholderContent() {
    if (widget.role == _driverRole) {
      return "Driver Terms of Condition go here...\n\n"
          "This is placeholder text for the Driver role. "
          "Replace with actual terms and conditions later.";
    }

    if (widget.role == _parkingOwnerRole) {
      return "Parking Owner Terms of Condition go here...\n\n"
          "This is placeholder text for the Parking Owner role. "
          "Replace with actual terms and conditions later.";
    }

    return 'Invalid role selected. Please go back and choose a valid role.';
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
                  color: const Color(0xFFF6F7FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getPlaceholderContent(),
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppTheme.textDark,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: _agreed ? const Color(0xFFFFF7DD) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
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
              activeColor: const Color(0xFFB58A10),
              title: const Text(
                'I have read and agree to the Terms and Conditions.',
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
