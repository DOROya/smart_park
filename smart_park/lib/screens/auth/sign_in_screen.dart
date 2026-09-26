import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_email_service.dart';
import '../../services/email_rate_limiter.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/staff_credentials.dart';
import '../../widgets/auth_widgets.dart';
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
  bool _sendingReset = false;

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
      if (user != null &&
          !user.emailVerified &&
          !isStaffAuthEmail(user.email)) {
        if (!mounted) {
          return;
        }
        unawaited(
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const VerifyEmailScreen()),
          ),
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

      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const RoleBasedHomePage()),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      final bool staffLogin = !_emailController.text.contains('@');
      _showSnackBar(
        // Owners deactivate staff, which disables the staff sign-in.
        error.code == 'user-disabled' && staffLogin
            ? 'This staff account has been deactivated. Ask your parking '
                  'owner to reactivate it.'
            : friendlyError(
                error,
                fallback: 'Unable to sign in. Please try again.',
              ),
      );
      debugPrint(
        'Sign-in FirebaseAuthException(${error.code}): ${error.message}',
      );
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
      _showSnackBar(
        friendlyError(error, fallback: 'Unable to sign in. Please try again.'),
      );
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

  Future<void> _sendPasswordReset() async {
    final String input = _emailController.text.trim();
    if (input.isEmpty || !input.contains('@')) {
      _showSnackBar(
        input.isEmpty
            ? 'Enter your email above, then tap Forgot Password.'
            : 'Username accounts are reset by whoever set up your account.',
      );
      return;
    }
    const String rateLimitAction = 'password-reset';
    final Duration wait = EmailRateLimiter.remaining(rateLimitAction, input);
    if (wait > Duration.zero) {
      _showSnackBar(
        'A reset link was already sent. Please wait '
        '${EmailRateLimiter.describe(wait)} before requesting another.',
      );
      return;
    }
    if (_sendingReset) return;
    _sendingReset = true;
    try {
      await AuthEmailService().sendPasswordResetEmail(input);
      EmailRateLimiter.recordSend(rateLimitAction, input);
      if (mounted) {
        _showSnackBar('Password reset link sent to $input.');
      }
    } on FirebaseFunctionsException catch (error) {
      final bool throttled = AuthEmailService.isThrottled(error);
      if (throttled) {
        EmailRateLimiter.recordSend(rateLimitAction, input);
      }
      if (mounted) {
        _showSnackBar(
          throttled
              ? EmailRateLimiter.tooManyRequestsMessage
              : friendlyError(error, fallback: 'Unable to send reset email.'),
        );
      }
    } finally {
      _sendingReset = false;
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
          const AuthBadge(icon: Icons.lock_rounded, label: 'Secure access'),
          const SizedBox(height: 14),
          const AuthHeader(
            first: 'Hello ',
            accent: 'Again!',
            subtitle: 'Sign in to continue parking smarter.',
          ),
          const SizedBox(height: 24),
          AuthFormCard(
            icon: Icons.person_outline_rounded,
            title: 'Sign in details',
            children: [
              AuthTextField(
                label: 'Email or Username',
                hint: 'you@example.com',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                controller: _emailController,
              ),
              const SizedBox(height: 14),
              AuthTextField(
                label: 'Password',
                hint: 'Enter your password',
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _sendPasswordReset,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Forgot Password?'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          PrimaryAuthButton(
            text: 'Login',
            icon: Icons.arrow_forward_rounded,
            onPressed: _signIn,
            isLoading: _isSigningIn,
          ),
          const SizedBox(height: 10),
          AuthSwitchPrompt(
            question: 'No account yet?',
            action: 'Create one',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
