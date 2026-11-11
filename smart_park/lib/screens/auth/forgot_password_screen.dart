import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../services/auth_email_service.dart';
import '../../services/email_rate_limiter.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/auth_widgets.dart';

const String _rateLimitAction = 'password-reset';

/// Asks for the account's email, sends a reset link, then confirms it was
/// sent and lets the user resend after a short wait.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  /// What was typed on the sign-in screen, if it looks like an email.
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail.contains('@') ? widget.initialEmail.trim() : '',
  );

  bool _sending = false;
  String? _error;

  /// The address the link went to; non-null shows the confirmation.
  String? _sentTo;

  Duration _resendWait = Duration.zero;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _email.dispose();
    super.dispose();
  }

  void _startResendCountdown(String email) {
    _resendTimer?.cancel();
    void tick() {
      if (!mounted) return;
      final Duration wait = EmailRateLimiter.remaining(_rateLimitAction, email);
      setState(() => _resendWait = wait);
      if (wait == Duration.zero) _resendTimer?.cancel();
    }

    tick();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _send([String? address]) async {
    if (_sending) return;
    final String email = (address ?? _email.text).trim();
    String? problem;
    if (email.isEmpty) {
      problem = 'Enter the email you signed up with.';
    } else if (!email.contains('@') || !email.contains('.')) {
      problem =
          "That doesn't look like an email. Staff accounts that sign in "
          'with a username are reset by the parking owner who set them up.';
    } else {
      final Duration wait = EmailRateLimiter.remaining(_rateLimitAction, email);
      if (wait > Duration.zero) {
        problem =
            'A link was just sent. Please wait '
            '${EmailRateLimiter.describe(wait)} before requesting another.';
      }
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      // The first call can wait several seconds for the server to start.
      await AuthEmailService()
          .sendPasswordResetEmail(email)
          .timeout(const Duration(seconds: 45));
      EmailRateLimiter.recordSend(_rateLimitAction, email);
      if (!mounted) return;
      setState(() => _sentTo = email);
      _startResendCountdown(email);
      if (address != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('A new reset link was sent to $email.')),
          );
      }
    } on TimeoutException {
      _fail(
        'This is taking too long. Check your internet connection and try '
        'again.',
      );
    } on FirebaseFunctionsException catch (error) {
      if (AuthEmailService.isThrottled(error)) {
        EmailRateLimiter.recordSend(_rateLimitAction, email);
        _fail(EmailRateLimiter.tooManyRequestsMessage);
      } else {
        _fail(
          friendlyError(error, fallback: 'Unable to send the reset email.'),
        );
      }
    } catch (error) {
      _fail(
        friendlyError(
          error,
          fallback: 'Unable to send the reset email. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      showBack: true,
      onBackPressed: () => Navigator.of(context).pop(),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _sentTo == null ? _requestForm() : _confirmation(_sentTo!),
      ),
    );
  }

  Widget _requestForm() {
    return Column(
      key: const ValueKey<String>('form'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthBadge(icon: Icons.key_rounded, label: 'Account recovery'),
        const SizedBox(height: 14),
        const AuthHeader(
          first: 'Forgot ',
          accent: 'password?',
          subtitle:
              "Enter the email you signed up with and we'll send you a link "
              'to set a new password.',
        ),
        const SizedBox(height: 24),
        AuthFormCard(
          icon: Icons.mail_outline_rounded,
          title: 'Your email',
          children: [
            AuthTextField(
              label: 'Email',
              hint: 'you@example.com',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              controller: _email,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorNote(message: _error!),
            ],
          ],
        ),
        const SizedBox(height: 22),
        PrimaryAuthButton(
          text: _sending ? 'Sending link...' : 'Send reset link',
          icon: Icons.send_rounded,
          isLoading: _sending,
          enabled: !_sending,
          onPressed: _send,
        ),
        const SizedBox(height: 16),
        AuthSwitchPrompt(
          question: 'Remembered it? ',
          action: 'Back to sign in',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _confirmation(String email) {
    final bool canResend = _resendWait == Duration.zero && !_sending;
    return Column(
      key: const ValueKey<String>('sent'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthBadge(
          icon: Icons.mark_email_read_rounded,
          label: 'Reset link sent',
        ),
        const SizedBox(height: 14),
        const AuthHeader(
          first: 'Check your ',
          accent: 'inbox.',
          subtitle: 'Follow the link in the email to set a new password.',
        ),
        const SizedBox(height: 24),
        AuthFormCard(
          icon: Icons.outgoing_mail,
          title: 'Sent to',
          children: [
            Text(
              email,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              // The server answers the same for unknown emails, so don't
              // claim the account exists.
              'If this email has a SmartPark account, the link is on its way. '
              'It can take a minute or two to arrive.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            const _Step(n: 1, text: 'Open the email from SmartPark.'),
            const _Step(
              n: 2,
              text: 'Tap the reset link and enter a new password.',
            ),
            const _Step(n: 3, text: 'Come back here and sign in with it.'),
            const SizedBox(height: 6),
            _Tip(
              text:
                  "Can't find it? Check your Spam or Junk folder, and make "
                  'sure the email above is spelled correctly.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorNote(message: _error!),
            ],
          ],
        ),
        const SizedBox(height: 22),
        PrimaryAuthButton(
          text: 'Back to sign in',
          icon: Icons.login_rounded,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 10),
        SecondaryAuthButton(
          text: canResend
              ? 'Resend link'
              : _sending
              ? 'Sending...'
              : 'Resend in ${EmailRateLimiter.describe(_resendWait)}',
          isLoading: _sending,
          onPressed: canResend ? () => _send(email) : null,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _sending
                ? null
                : () => setState(() {
                    _sentTo = null;
                    _error = null;
                  }),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
            ),
            child: const Text('Use a different email'),
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.onAccent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: AppTheme.textDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppTheme.accentText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dangerSoft,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.dangerBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: AppTheme.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppTheme.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
