import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/staff_credentials.dart';
import 'admin_home_page.dart';
import 'driver_home_page.dart';
import 'parking_owner_home_screen.dart';
import 'staff_home_page.dart';

class RoleBasedHomePage extends StatefulWidget {
  const RoleBasedHomePage({super.key});

  @override
  State<RoleBasedHomePage> createState() => _RoleBasedHomePageState();
}

class _RoleBasedHomePageState extends State<RoleBasedHomePage> {
  late Future<String> _roleFuture;

  static const List<String> _roleKeys = <String>['role', 'Role', 'userRole'];

  List<String> _emailCandidates(String rawEmail) {
    final String trimmed = rawEmail.trim();
    if (trimmed.isEmpty) {
      return const <String>[];
    }

    final Set<String> variants = <String>{trimmed, trimmed.toLowerCase()};
    return variants.toList();
  }

  @override
  void initState() {
    super.initState();
    _roleFuture = _resolveRole();
  }

  String? _extractRole(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }

    for (final String key in _roleKeys) {
      final Object? value = data[key];
      if (value is String) {
        final String role = value.trim();
        if (role.isNotEmpty) {
          return role;
        }
      }
    }

    return null;
  }

  Map<String, dynamic>? _pickBestUserData(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (snapshot.docs.isEmpty) {
      return null;
    }

    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final Map<String, dynamic> data = doc.data();
      if (_extractRole(data) != null) {
        return data;
      }
    }

    return snapshot.docs.first.data();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _readUserDocWithRetry({
    required CollectionReference<Map<String, dynamic>> usersCollection,
    required String uid,
    required User authenticatedUser,
    required bool hasRetriedAfterTokenRefresh,
  }) async {
    try {
      return await usersCollection.doc(uid).get();
    } on FirebaseException catch (error) {
      if (!hasRetriedAfterTokenRefresh && error.code == 'permission-denied') {
        await authenticatedUser.getIdToken(true);
        return _readUserDocWithRetry(
          usersCollection: usersCollection,
          uid: uid,
          authenticatedUser: authenticatedUser,
          hasRetriedAfterTokenRefresh: true,
        );
      }
      rethrow;
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _queryUsersWithRetry({
    required Query<Map<String, dynamic>> query,
    required User authenticatedUser,
    required bool hasRetriedAfterTokenRefresh,
  }) async {
    try {
      return await query.get();
    } on FirebaseException catch (error) {
      if (!hasRetriedAfterTokenRefresh && error.code == 'permission-denied') {
        await authenticatedUser.getIdToken(true);
        return _queryUsersWithRetry(
          query: query,
          authenticatedUser: authenticatedUser,
          hasRetriedAfterTokenRefresh: true,
        );
      }
      rethrow;
    }
  }

  Future<void> _backfillUserDocumentBestEffort({
    required String uid,
    required String email,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _backfillUserDocument(uid: uid, email: email, data: data);
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }
      // Continue routing even if backfill is denied; role can still be resolved.
    }
  }

  Future<Map<String, dynamic>?> _resolveLegacyUserData({
    required String uid,
    required List<String> emailCandidates,
    required User authenticatedUser,
    required bool hasRetriedAfterTokenRefresh,
  }) async {
    final CollectionReference<Map<String, dynamic>> usersCollection =
        FirebaseFirestore.instance.collection('users');

    final QuerySnapshot<Map<String, dynamic>> byUserId =
        await _queryUsersWithRetry(
          query: usersCollection.where('userID', isEqualTo: uid).limit(10),
          authenticatedUser: authenticatedUser,
          hasRetriedAfterTokenRefresh: hasRetriedAfterTokenRefresh,
        );
    final Map<String, dynamic>? bestByUserId = _pickBestUserData(byUserId);
    if (bestByUserId != null) {
      return bestByUserId;
    }

    final QuerySnapshot<Map<String, dynamic>> byUserIdLowercaseKey =
        await _queryUsersWithRetry(
          query: usersCollection.where('userId', isEqualTo: uid).limit(10),
          authenticatedUser: authenticatedUser,
          hasRetriedAfterTokenRefresh: hasRetriedAfterTokenRefresh,
        );
    final Map<String, dynamic>? bestByUserIdLowercaseKey = _pickBestUserData(
      byUserIdLowercaseKey,
    );
    if (bestByUserIdLowercaseKey != null) {
      return bestByUserIdLowercaseKey;
    }

    for (final String email in emailCandidates) {
      final QuerySnapshot<Map<String, dynamic>> byEmail =
          await _queryUsersWithRetry(
            query: usersCollection.where('email', isEqualTo: email).limit(10),
            authenticatedUser: authenticatedUser,
            hasRetriedAfterTokenRefresh: hasRetriedAfterTokenRefresh,
          );
      final Map<String, dynamic>? bestByEmail = _pickBestUserData(byEmail);
      if (bestByEmail != null) {
        return bestByEmail;
      }
    }

    return null;
  }

  Future<void> _backfillUserDocument({
    required String uid,
    required String email,
    required Map<String, dynamic> data,
  }) {
    final Map<String, dynamic> mergedData = <String, dynamic>{
      ...data,
      'userID': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (email.isNotEmpty) {
      mergedData['email'] = email;
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set(mergedData, SetOptions(merge: true));
  }

  Future<String> _resolveRole() async {
    return _resolveRoleInternal(hasRetriedAfterTokenRefresh: false);
  }

  Future<String> _resolveRoleInternal({
    required bool hasRetriedAfterTokenRefresh,
  }) async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    final String? uid = currentUser?.uid;
    if (uid == null) {
      throw StateError('No logged-in user found.');
    }
    final User authenticatedUser = currentUser!;

    // Staff sign in with a username, not a real inbox, so their
    // synthetic-domain account can never complete email verification.
    if (!authenticatedUser.emailVerified &&
        !isStaffAuthEmail(authenticatedUser.email)) {
      throw StateError('Email is not verified for this account.');
    }

    final String rawEmail = (authenticatedUser.email ?? '').trim();
    final List<String> emailCandidates = _emailCandidates(rawEmail);
    final CollectionReference<Map<String, dynamic>> usersCollection =
        FirebaseFirestore.instance.collection('users');

    final DocumentSnapshot<Map<String, dynamic>> userDoc =
        await _readUserDocWithRetry(
          usersCollection: usersCollection,
          uid: uid,
          authenticatedUser: authenticatedUser,
          hasRetriedAfterTokenRefresh: hasRetriedAfterTokenRefresh,
        );
    if (userDoc.exists) {
      final String? role = _extractRole(userDoc.data());
      if (role != null) {
        return role;
      }
    }

    final Map<String, dynamic>? legacyUserData = await _resolveLegacyUserData(
      uid: uid,
      emailCandidates: emailCandidates,
      authenticatedUser: authenticatedUser,
      hasRetriedAfterTokenRefresh: hasRetriedAfterTokenRefresh,
    );
    if (legacyUserData != null) {
      await _backfillUserDocumentBestEffort(
        uid: uid,
        email: rawEmail,
        data: legacyUserData,
      );
      final String? role = _extractRole(legacyUserData);
      if (role != null) {
        return role;
      }
    }

    for (final String email in emailCandidates) {
      final QuerySnapshot<Map<String, dynamic>> staffByEmail =
          await _queryUsersWithRetry(
            query: FirebaseFirestore.instance
                .collection('staff_accounts')
                .where('email', isEqualTo: email)
                .limit(1),
            authenticatedUser: authenticatedUser,
            hasRetriedAfterTokenRefresh: hasRetriedAfterTokenRefresh,
          );
      if (staffByEmail.docs.isNotEmpty) {
        await _backfillUserDocumentBestEffort(
          uid: uid,
          email: rawEmail,
          data: <String, dynamic>{'role': 'staff'},
        );
        return 'staff';
      }
    }

    throw StateError(
      'No role found. uid=$uid, email=${rawEmail.isEmpty ? '(empty)' : rawEmail}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _roleFuture,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          final String detail = snapshot.error?.toString() ?? 'Unknown error.';
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Unable to resolve your account role. Please sign in again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final String role = snapshot.data!;

        if (role == 'Driver') {
          return DriverHomePage(role: role);
        }

        if (role == 'admin') {
          return const AdminHomePage();
        }

        if (role == 'Parking Owner') {
          return ParkingOwnerHomePage(role: role);
        }

        if (role == 'staff') {
          return const StaffHomePage();
        }

        return const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Unknown account role. Please contact support.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}
