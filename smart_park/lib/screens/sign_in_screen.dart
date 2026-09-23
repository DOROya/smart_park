import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import '../utils/staff_credentials.dart';
import 'role_based_home_page.dart';
import 'sign_up_screen.dart';
import 'verify_email_screen.dart';
import 'welcome_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSigningIn = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signIn() async {
    if (_isSigningIn) {
      return;
    }

    setState(() {
      _isSigningIn = true;
    });

    try {
      final String rawInput = _emailController.text.trim();
      final String password = _passwordController.text;

      if (rawInput.isEmpty || password.isEmpty) {
        _showSnackBar('Please enter both your email/username and password.');
        return;
      }

      // Staff sign in with a plain username (no '@'); everyone else uses a
      // real email. A bare username is mapped to its synthetic auth email.
      final String email = rawInput.contains('@')
          ? rawInput
          : staffUsernameToAuthEmail(rawInput);

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(const Duration(seconds: 20));

      final User? user = userCredential.user;
      if (user != null && !user.emailVerified && !isStaffAuthEmail(user.email)) {
        if (!mounted) {
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const VerifyEmailScreen()),
        );
        return;
      }

      if (user != null) {
        // Firestore rules use request.auth.token.email_verified; force-refresh token
        // so verified users immediately receive updated claims.
        await user.getIdToken(true);
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const RoleBasedHomePage()),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      final String message = error.message ?? 'Authentication failed.';
      _showSnackBar('${error.code}: $message');
      debugPrint('Sign-in FirebaseAuthException(${error.code}): $message');
    } on TimeoutException {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        'Sign-in timed out. Check your internet connection and try again.',
      );
      debugPrint('Sign-in timed out after 20 seconds.');
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Unexpected sign-in error: $error');
      debugPrint('Unexpected sign-in error: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
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
          const SizedBox(height: 14),
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
                  Icons.security_rounded,
                  size: 16,
                  color: Color(0xFF3C465B),
                ),
                SizedBox(width: 6),
                Text(
                  'Secure access',
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
            first: 'Hello ',
            accent: 'Again!',
            subtitle: 'Enter your credentials to continue.',
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
                  'Sign in details',
                  style: TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                AuthTextField(
                  label: 'Email or Staff Username',
                  hint: 'Enter your email or staff username',
                  controller: _emailController,
                ),
                const SizedBox(height: 16),
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
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF404552),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Forgot Password?'),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryAuthButton(
            text: 'Login',
            onPressed: _signIn,
            isLoading: _isSigningIn,
          ),
          const SizedBox(height: 14),
          Center(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: Color(0xFF8E929C),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  const TextSpan(text: 'No account yet? '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SignUpScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Create one',
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
          const SizedBox(height: 18),
          const DividerLabel(text: 'or do it via other accounts'),
          const SizedBox(height: 18),
          const SocialButtonsRow(),
        ],
      ),
    );
  }
}
