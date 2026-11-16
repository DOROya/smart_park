import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../content/terms_content.dart' show kParkingOwnerRole;
import '../screens/auth/sign_in_screen.dart';
import '../services/parking_pricing.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'smartpark_ui.dart';

/// The paid parking a driver gives up by deleting their account: the hours
/// still unused across their [tickets], and how many tickets hold them.
({int hours, int tickets}) spUnusedTicketHours(
  Iterable<Map<String, dynamic>> tickets,
) {
  int hours = 0;
  int count = 0;
  for (final Map<String, dynamic> ticket in tickets) {
    if (((ticket['status'] as String?) ?? '').toLowerCase() != 'paid') continue;
    if (ticket['source'] == 'walk_in') continue;
    final int left = ticketHoursLeft(ticket);
    if (left <= 0) continue;
    hours += left;
    count++;
  }
  return (hours: hours, tickets: count);
}

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

  /// What a driver still has on their tickets; null while it is being
  /// counted, or when it could not be.
  ({int hours, int tickets})? _unused;
  bool _counting = false;

  /// The driver ticked that they are giving those hours up.
  bool _acceptedLoss = false;

  bool get _owner => widget.roleLabel == kParkingOwnerRole;

  bool get _losesHours => (_unused?.hours ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    if (!_owner) unawaited(_countUnusedHours());
  }

  Future<void> _countUnusedHours() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _counting = true);
    ({int hours, int tickets})? unused;
    try {
      final QuerySnapshot<Map<String, dynamic>> tickets =
          await FirebaseFirestore.instance
              .collection('transactions')
              .where('driverId', isEqualTo: uid)
              .get();
      unused = spUnusedTicketHours(
        tickets.docs.map(
          (QueryDocumentSnapshot<Map<String, dynamic>> d) => d.data(),
        ),
      );
    } catch (_) {
      // The general warning below still says hours are given up.
    }
    if (!mounted) return;
    setState(() {
      _counting = false;
      _unused = unused;
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final User? user = FirebaseAuth.instance.currentUser;
    final String? email = user?.email;
    if (user == null || email == null) return;
    if (_losesHours && !_acceptedLoss) {
      setState(
        () => _error = 'Tick the box above to give up your unused hours.',
      );
      return;
    }
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
              if (_losesHours) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                  decoration: BoxDecoration(
                    color: AppTheme.warningSoft,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppTheme.accent),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'You still have ${formatParkingHours(_unused!.hours)} '
                        'of paid parking on ${_unused!.tickets} ticket'
                        '${_unused!.tickets == 1 ? '' : 's'}.',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Deleting your account gives them up with no refund. '
                        'Use them first if you want them.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      CheckboxListTile(
                        value: _acceptedLoss,
                        onChanged: _deleting
                            ? null
                            : (bool? value) => setState(() {
                                _acceptedLoss = value ?? false;
                                _error = null;
                              }),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          'I give up these '
                          '${formatParkingHours(_unused!.hours)}.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
          // Not before the driver has seen what they would lose.
          onPressed: _deleting || _counting ? null : _delete,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          child: Text(
            _deleting
                ? 'Deleting...'
                : _counting
                ? 'Checking your tickets...'
                : 'Delete account',
          ),
        ),
      ],
    );
  }
}
