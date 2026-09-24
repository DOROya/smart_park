import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/email_rate_limiter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_widgets.dart';
import 'role_based_home_page.dart';
import 'sign_in_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    this.firstName,
    this.lastName,
    this.email,
    this.role,
    this.password,
  });

  final String? firstName;
  final String? lastName;
  final String? email;
  final String? role;
  final String? password;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static const String _driverRole = 'Driver';
  static const String _parkingOwnerRole = 'Parking Owner';
  static const String _adminRole = 'admin';

  static const String _rateLimitAction = 'verify';

  bool _sendingVerification = false;
  bool _checking = false;
  Duration _resendWait = Duration.zero;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Coming back to this screen within the cooldown should not trigger
      // another email; the countdown shows when the next one is allowed.
      _sendVerificationEmail(silentIfThrottled: true);
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  String get _rateLimitEmail =>
      FirebaseAuth.instance.currentUser?.email ?? widget.email ?? '';

  /// Refreshes [_resendWait] and ticks it down once a second until zero.
  void _syncResendCooldown() {
    _resendTimer?.cancel();
    void tick() {
      final Duration wait = EmailRateLimiter.remaining(
        _rateLimitAction,
        _rateLimitEmail,
      );
      if (!mounted) return;
      setState(() => _resendWait = wait);
      if (wait == Duration.zero) _resendTimer?.cancel();
    }

    tick();
    if (_resendWait > Duration.zero) {
      _resendTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<User?> _ensureAuthenticatedUser() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      return currentUser;
    }

    final String email = widget.email?.trim() ?? '';
    final String password = widget.password?.trim() ?? '';
    if (email.isEmpty || password.isEmpty) {
      return null;
    }

    final UserCredential userCredential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: password);

    final User? createdUser = userCredential.user;
    if (createdUser == null) {
      throw FirebaseAuthException(
        code: 'user-not-created',
        message: 'Unable to create the user account.',
      );
    }

    if (widget.firstName != null && widget.lastName != null) {
      await createdUser.updateDisplayName(
        '${widget.firstName}|${widget.lastName}',
      );
    }

    return createdUser;
  }

  Future<void> _sendVerificationEmail({bool silentIfThrottled = false}) async {
    if (_sendingVerification) {
      return;
    }

    final Duration wait = EmailRateLimiter.remaining(
      _rateLimitAction,
      _rateLimitEmail,
    );
    if (wait > Duration.zero) {
      _syncResendCooldown();
      if (!silentIfThrottled) {
        _showSnackBar(
          'Please wait ${EmailRateLimiter.describe(wait)} before requesting another email.',
        );
      }
      return;
    }

    final User? user = await _ensureAuthenticatedUser();
    if (user == null) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        'Unable to prepare the account. Please return and try again.',
      );
      return;
    }

    setState(() => _sendingVerification = true);
    try {
      await user.sendEmailVerification();
      EmailRateLimiter.recordSend(
        _rateLimitAction,
        user.email ?? _rateLimitEmail,
      );
      if (!mounted) {
        return;
      }
      _showSnackBar('Verification email sent. Check your inbox.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == 'too-many-requests') {
        // Firebase is throttling this account; hold the button off too.
        EmailRateLimiter.recordSend(_rateLimitAction, _rateLimitEmail);
        _showSnackBar(EmailRateLimiter.tooManyRequestsMessage);
      } else {
        _showSnackBar(error.message ?? 'Unable to send verification email.');
      }
    } finally {
      if (mounted) {
        setState(() => _sendingVerification = false);
        _syncResendCooldown();
      }
    }
  }

  ({String firstName, String lastName}) _resolveName(User user) {
    if (widget.firstName != null && widget.lastName != null) {
      return (firstName: widget.firstName!, lastName: widget.lastName!);
    }

    final String displayName = user.displayName ?? '';
    if (displayName.contains('|')) {
      final List<String> parts = displayName.split('|');
      return (
        firstName: parts.isNotEmpty ? parts.first : '',
        lastName: parts.length > 1 ? parts.sublist(1).join('|') : '',
      );
    }

    final List<String> parts = displayName.trim().split(' ');
    return (
      firstName: parts.isNotEmpty ? parts.first : '',
      lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
    );
  }

  String? _canonicalizeRole(String? role) {
    final String value = (role ?? '').trim();
    if (value.isEmpty) {
      return null;
    }

    if (value == _driverRole || value.toLowerCase() == 'driver') {
      return _driverRole;
    }

    if (value == _parkingOwnerRole || value.toLowerCase() == 'parking owner') {
      return _parkingOwnerRole;
    }

    if (value == _adminRole || value.toLowerCase() == 'admin') {
      return _adminRole;
    }

    return null;
  }

  Future<void> _ensureUserDocument(User user) async {
    final String uid = user.uid;
    final ({String firstName, String lastName}) name = _resolveName(user);
    final String email = widget.email ?? user.email ?? '';
    final String? canonicalRole = _canonicalizeRole(widget.role);

    final Map<String, dynamic> userData = {
      'userID': uid,
      'firstName': name.firstName,
      'lastName': name.lastName,
      'email': email,
    };
    if (canonicalRole != null) {
      userData['role'] = canonicalRole;
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set(userData, SetOptions(merge: true));
  }

  Future<void> _checkVerification() async {
    if (_checking) {
      return;
    }
    setState(() => _checking = true);
    try {
      await _checkVerificationInner();
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _checkVerificationInner() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
        (route) => false,
      );
      return;
    }

    await user.reload();
    final User? refreshedUser = FirebaseAuth.instance.currentUser;
    final bool isVerified = refreshedUser?.emailVerified ?? false;

    if (!mounted) {
      return;
    }

    if (isVerified) {
      await refreshedUser!.getIdToken(true);
      await _ensureUserDocument(refreshedUser);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const RoleBasedHomePage()),
        (route) => false,
      );
      return;
    }

    _showSnackBar(
      'Your email is not verified yet. Check your inbox and try again.',
    );
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final String email =
        (widget.email ?? FirebaseAuth.instance.currentUser?.email ?? '').trim();

    return AuthShell(
      trailing: TextButton.icon(
        onPressed: _signOut,
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: const Text('Sign Out'),
        style: TextButton.styleFrom(foregroundColor: const Color(0xFFAF2E2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_unread_rounded,
                size: 42,
                color: Color(0xFF8A6A0C),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const AuthHeader(
            first: 'Check your ',
            accent: 'inbox.',
            subtitle: 'Verify your email to finish setting up your account.',
          ),
          const SizedBox(height: 20),
          AuthFormCard(
            icon: Icons.alternate_email_rounded,
            title: 'Verification link sent',
            children: [
              if (email.isNotEmpty) ...[
                Text(
                  email,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                widget.password == null
                    ? 'Open the link in the email we sent, then come back and tap the button below.'
                    : 'Your account is created. Open the link in the email we sent, then come back and tap the button below.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Can't find it? Check your spam folder.",
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 24),
          PrimaryAuthButton(
            text: 'I Verified My Email',
            icon: Icons.check_rounded,
            isLoading: _checking,
            onPressed: _checkVerification,
          ),
          const SizedBox(height: 12),
          SecondaryAuthButton(
            text: _resendWait > Duration.zero
                ? 'Resend Email in ${EmailRateLimiter.describe(_resendWait)}'
                : 'Resend Email',
            isLoading: _sendingVerification,
            onPressed: _resendWait > Duration.zero
                ? null
                : () => _sendVerificationEmail(),
          ),
        ],
      ),
    );
  }
}
