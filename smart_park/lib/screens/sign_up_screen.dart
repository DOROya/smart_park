import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/smartpark_ui.dart';
import 'sign_in_screen.dart';
import 'select_role_screen.dart';
import 'welcome_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _uppercaseRegex = RegExp(r'[A-Z]');
  static final RegExp _numberRegex = RegExp(r'\d');

  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Rebuild so the password checklist ticks off as the user types.
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // Keep validation messages specific so users can correct one field at a time.
  String? _validateInputs({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) {
    if (firstName.isEmpty) {
      return 'Please enter your first name.';
    }

    if (lastName.isEmpty) {
      return 'Please enter your last name.';
    }

    if (email.isEmpty) {
      return 'Please enter your email address.';
    }

    if (!_emailRegex.hasMatch(email)) {
      return 'Please enter a valid email address.';
    }

    if (password.isEmpty) {
      return 'Please enter a password.';
    }

    if (password.length < 8) {
      return 'Password must be at least 8 characters long.';
    }

    if (!_uppercaseRegex.hasMatch(password)) {
      return 'Password must contain at least one uppercase letter.';
    }

    if (!_numberRegex.hasMatch(password)) {
      return 'Password must contain at least one number.';
    }

    return null;
  }

  void _goToRoleSelection() {
    // Collect and validate input first; the auth account is created later.
    final String firstName = _firstNameController.text.trim();
    final String lastName = _lastNameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    final String? validationMessage = _validateInputs(
      firstName: firstName,
      lastName: lastName,
      email: email,
      password: password,
    );
    if (validationMessage != null) {
      _showSnackBar(validationMessage);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SelectRoleScreen(
          firstName: firstName,
          lastName: lastName,
          email: email,
          password: password,
        ),
      ),
    );
  }

  Widget _requirement(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: met ? spEntryColor : const Color(0xFFE4E7EF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 12,
              color: met ? Colors.white : Colors.transparent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: met ? spEntryColor : AppTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String password = _passwordController.text;

    return AuthShell(
      showBack: true,
      onBackPressed: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthBadge(
            icon: Icons.person_add_alt_1_rounded,
            label: 'Step 1 of 3 · Your details',
          ),
          const SizedBox(height: 14),
          const AuthHeader(
            first: 'Let\'s ',
            accent: 'Start.',
            subtitle: 'Create your SmartPark account.',
          ),
          const SizedBox(height: 24),
          AuthFormCard(
            icon: Icons.badge_outlined,
            title: 'Basic Information',
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AuthTextField(
                      label: 'First Name',
                      hint: 'Juan',
                      textInputAction: TextInputAction.next,
                      controller: _firstNameController,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AuthTextField(
                      label: 'Last Name',
                      hint: 'Dela Cruz',
                      textInputAction: TextInputAction.next,
                      controller: _lastNameController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AuthTextField(
                label: 'Email Address',
                hint: 'you@example.com',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                controller: _emailController,
              ),
              const SizedBox(height: 14),
              AuthTextField(
                label: 'Password',
                hint: 'Create a password',
                icon: Icons.lock_outline_rounded,
                textInputAction: TextInputAction.done,
                controller: _passwordController,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _requirement(
                'At least 8 characters',
                password.trim().length >= 8,
              ),
              _requirement(
                'One uppercase letter',
                _uppercaseRegex.hasMatch(password),
              ),
              _requirement('One number', _numberRegex.hasMatch(password)),
            ],
          ),
          const SizedBox(height: 24),
          PrimaryAuthButton(
            text: 'Next',
            icon: Icons.arrow_forward_rounded,
            onPressed: _goToRoleSelection,
          ),
          const SizedBox(height: 10),
          AuthSwitchPrompt(
            question: 'Already have an account?',
            action: 'Sign In',
            onTap: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
