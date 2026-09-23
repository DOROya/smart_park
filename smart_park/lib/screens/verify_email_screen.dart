import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

  bool _sendingVerification = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendVerificationEmail();
    });
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

  Future<void> _sendVerificationEmail() async {
    if (_sendingVerification) {
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

    _sendingVerification = true;
    try {
      await user.sendEmailVerification();
      if (!mounted) {
        return;
      }
      _showSnackBar('Verification email sent. Check your inbox.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.message ?? 'Unable to send verification email.');
    } finally {
      _sendingVerification = false;
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(onPressed: _signOut, child: const Text('Sign Out')),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Please verify your email before continuing.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E2026),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.password == null
                    ? 'We sent a verification link to your inbox. Open it and then come back here.'
                    : 'We created your account and sent a verification link to your inbox. Open it and then come back here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF8E929C),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: _sendVerificationEmail,
                child: const Text('Resend verification email'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _checkVerification,
                child: const Text('I Verified My Email'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
