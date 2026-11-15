import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../content/terms_content.dart' show kParkingOwnerRole;
import '../screens/auth/sign_in_screen.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'smartpark_ui.dart';

/// Profile card that deletes the signed-in driver's or owner's account. The
/// password is asked for again first, and the server refuses while anything
/// would be left hanging (a parked vehicle, a refund on its way, drivers
/// holding unused hours).
class SpDeleteAccountCard extends StatelessWidget {
  const SpDeleteAccountCard({super.key, required this.roleLabel});

  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    return SpSectionCard(
      icon: Icons.person_remove_outlined,
      title: 'Delete Account',
      subtitle: 'Remove your name, email and sign-in from SmartPark.',
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _DeleteAccountDialog(roleLabel: roleLabel),
          ),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text(
            'Delete My Account',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            foregroundColor: AppTheme.danger,
            side: BorderSide(color: AppTheme.dangerBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.roleLabel});

  final String roleLabel;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _password = TextEditingController();
  bool _deleting = false;
  String? _error;

  bool get _owner => widget.roleLabel == kParkingOwnerRole;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final User? user = FirebaseAuth.instance.currentUser;
    final String? email = user?.email;
    if (user == null || email == null) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password to confirm.');
      return;
    }
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: _password.text),
      );
      // The server checks that the password was confirmed just now.
      await user.getIdToken(true);
      await FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('deleteMyAccount').call<dynamic>();
      if (!mounted) return;
      final NavigatorState navigator = Navigator.of(
        context,
        rootNavigator: true,
      );
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {
        // The sign-in is already gone on the server.
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Your account was deleted.')),
      );
      await navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
        (Route<dynamic> route) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = switch (error.code) {
          'wrong-password' ||
          'invalid-credential' => 'That password is incorrect.',
          'too-many-requests' => 'Too many attempts. Wait a few minutes.',
          _ => friendlyError(error, fallback: 'Could not confirm it is you.'),
        };
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        // The server says exactly what is still in the way.
        _error = error.code == 'failed-precondition'
            ? (error.message ?? 'Your account cannot be deleted yet.')
            : friendlyError(error, fallback: 'Could not delete your account.');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = friendlyError(
          error,
          fallback: 'Could not delete your account.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _owner
                    ? 'Your facility is removed from SmartPark, your staff '
                          'can no longer sign in, and your business documents '
                          'are deleted. This cannot be undone.'
                    : 'Your tickets can no longer be used and any unused '
                          'hours on them are given up, not refunded. This '
                          'cannot be undone.',
                style: TextStyle(height: 1.4, color: AppTheme.textDark),
              ),
              const SizedBox(height: 8),
              Text(
                'Your name, email and sign-in are removed. Payment and gate '
                'records are kept without your name.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: true,
                enabled: !_deleting,
                decoration: InputDecoration(
                  labelText: 'Your password',
                  filled: true,
                  fillColor: AppTheme.surfaceAlt,
                  errorText: _error,
                  errorMaxLines: 4,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
          child: const Text('Keep my account'),
        ),
        FilledButton(
          onPressed: _deleting ? null : _delete,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          child: Text(_deleting ? 'Deleting...' : 'Delete account'),
        ),
      ],
    );
  }
}
