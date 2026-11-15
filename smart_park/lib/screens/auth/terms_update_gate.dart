import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../content/terms_content.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_loading.dart';
import '../../widgets/sp_terms_view.dart';
import 'sign_in_screen.dart';

/// Whether a profile has accepted the terms as they are now.
bool hasAcceptedCurrentTerms(Map<String, dynamic>? user) =>
    ((user?['termsVersion'] as String?) ?? '').trim() == kTermsVersion;

/// Shows [child] only once the signed-in user has accepted the current
/// terms. Anyone who agreed to an older version (or, like staff, was never
/// asked) reads the new one and accepts it first, so a change to the terms
/// never binds someone who has not seen it.
class TermsUpdateGate extends StatefulWidget {
  const TermsUpdateGate({super.key, required this.role, required this.child});

  final String role;
  final Widget child;

  @override
  State<TermsUpdateGate> createState() => _TermsUpdateGateState();
}

class _TermsUpdateGateState extends State<TermsUpdateGate> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _profile;
  bool _agreed = false;
  bool _saving = false;
  // Stays true once accepted, so the app never flashes back to the terms.
  bool _accepted = false;

  DocumentReference<Map<String, dynamic>>? get _ref {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  @override
  void initState() {
    super.initState();
    _profile = _ref?.snapshots();
  }

  Future<void> _accept() async {
    final DocumentReference<Map<String, dynamic>>? ref = _ref;
    if (ref == null || _saving || !_agreed) return;
    setState(() => _saving = true);
    try {
      await ref.set(<String, dynamic>{
        'termsVersion': kTermsVersion,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) setState(() => _accepted = true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(error, fallback: 'Could not save. Try again.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    final NavigatorState navigator = Navigator.of(context);
    await FirebaseAuth.instance.signOut();
    await navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted || _profile == null || termsFor(widget.role).isEmpty) {
      return widget.child;
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profile,
      builder: (BuildContext context, snapshot) {
        if (snapshot.hasError) return widget.child;
        if (!snapshot.hasData) return const SpLoadingScreen();
        if (hasAcceptedCurrentTerms(snapshot.data!.data())) {
          return widget.child;
        }
        return _termsPage(
          firstTime: ((snapshot.data!.data()?['termsVersion'] as String?) ?? '')
              .isEmpty,
        );
      },
    );
  }

  Widget _termsPage({required bool firstTime}) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        surfaceTintColor: AppTheme.surface,
        automaticallyImplyLeading: false,
        title: Text(firstTime ? 'Terms and Conditions' : 'Updated Terms'),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : _signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    children: <Widget>[
                      Text(
                        firstTime
                            ? 'Please read and accept SmartPark\'s terms to '
                                  'continue.'
                            : 'SmartPark\'s terms have changed since you '
                                  'last agreed to them. Please read and '
                                  'accept the new version to continue.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SpTermsBody(role: widget.role),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(top: BorderSide(color: spCardBorder)),
                  ),
                  child: Column(
                    children: <Widget>[
                      CheckboxListTile(
                        value: _agreed,
                        onChanged: _saving
                            ? null
                            : (bool? v) => setState(() => _agreed = v ?? false),
                        activeColor: AppTheme.accentText,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'I have read and agree to the Terms and '
                          'Conditions and the Privacy Notice.',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SpPrimaryButton(
                        icon: Icons.check_rounded,
                        label: _saving ? 'Saving...' : 'Accept and Continue',
                        busy: _saving,
                        onPressed: _agreed ? _accept : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
