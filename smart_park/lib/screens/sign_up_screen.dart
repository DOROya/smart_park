import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
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

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3F8),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFDCE2EC)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 16,
                  color: Color(0xFF3C465B),
                ),
                SizedBox(width: 6),
                Text(
                  'New account setup',
                  style: TextStyle(
                    color: Color(0xFF3C465B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const AuthHeader(
            first: 'Let\'s ',
            accent: 'Start.',
            subtitle: 'Fill in any details that are missing.',
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE4E7EF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x11000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Basic Information',
                  style: TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                AuthTextField(
                  label: 'First Name',
                  hint: 'Enter your first name',
                  controller: _firstNameController,
                ),
                const SizedBox(height: 14),
                AuthTextField(
                  label: 'Last Name',
                  hint: 'Enter your last name',
                  controller: _lastNameController,
                ),
                const SizedBox(height: 14),
                AuthTextField(
                  label: 'Email Address',
                  hint: 'Enter your email',
                  controller: _emailController,
                ),
                const SizedBox(height: 14),
                AuthTextField(
                  label: 'Password',
                  hint: 'Enter your password',
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F4F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E7EF)),
            ),
            child: const Text(
              'Password should be at least 8 characters with one uppercase letter and one number.',
              style: TextStyle(
                color: Color(0xFF596173),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 28),
          PrimaryAuthButton(text: 'Next', onPressed: _goToRoleSelection),
          const SizedBox(height: 12),
          Center(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: Color(0xFF8E929C),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  const TextSpan(text: 'Already have an account? '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => const SignInScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          color: Color(0xFF20222A),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
