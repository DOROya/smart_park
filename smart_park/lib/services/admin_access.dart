import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// An account's access, as the admin Users tab shows it.
/// The first super admin, who set SmartPark up. Other super admins can't
/// demote them or remove their access (functions/src/admin_roles.js).
const String kFoundingSuperAdminUid = 'GWBK5QsdMNMHdPDjiPgrd7g3u3C2';

enum AccessLevel { superAdmin, admin, supervisor, staff, owner, driver, other }

/// Reads `users/{uid}`: admins by `adminLevel` (admins from before levels
/// existed are normal admins), everyone else by role.
AccessLevel accessLevelOf(Map<String, dynamic>? user) {
  final String role =
      ((user?['role'] ?? user?['Role'] ?? user?['userRole'] ?? '') as Object)
          .toString()
          .trim()
          .toLowerCase();
  return switch (role) {
    'admin' =>
      user?['adminLevel'] == 'super'
          ? AccessLevel.superAdmin
          : AccessLevel.admin,
    'supervisor' => AccessLevel.supervisor,
    'staff' => AccessLevel.staff,
    'parking owner' => AccessLevel.owner,
    'driver' => AccessLevel.driver,
    _ => AccessLevel.other,
  };
}

String accessLevelLabel(AccessLevel level) => switch (level) {
  AccessLevel.superAdmin => 'Super admin',
  AccessLevel.admin => 'Admin',
  AccessLevel.supervisor => 'Supervisor',
  AccessLevel.staff => 'Gate staff',
  AccessLevel.owner => 'Owner',
  AccessLevel.driver => 'Driver',
  AccessLevel.other => 'Other',
};

bool isAdminLevel(AccessLevel level) =>
    level == AccessLevel.superAdmin || level == AccessLevel.admin;

/// What a super admin is shown before promoting someone.
class AdminCandidate {
  const AdminCandidate({
    required this.role,
    required this.emailVerified,
    required this.activeTickets,
    required this.unusedPasses,
  });

  final String role;
  final bool emailVerified;
  final int activeTickets;
  final int unusedPasses;

  bool get canPromote => role == 'Driver' && emailVerified;
}

/// The super admin's access changes (functions/src/admin_roles.js). Each
/// change asks for the caller's password first: the server refuses a
/// sign-in older than five minutes.
class AdminAccessService {
  AdminAccessService({FirebaseFunctions? functions, FirebaseAuth? auth})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  Future<AdminCandidate> candidate(String uid) async {
    final Object? data =
        (await _functions.httpsCallable('getAdminCandidate').call(
          <String, dynamic>{'uid': uid},
        )).data;
    final Map<Object?, Object?> m = data is Map ? data : <Object?, Object?>{};
    return AdminCandidate(
      role: (m['role'] as String?) ?? '',
      emailVerified: m['emailVerified'] == true,
      activeTickets: (m['activeTickets'] as num?)?.toInt() ?? 0,
      unusedPasses: (m['unusedPasses'] as num?)?.toInt() ?? 0,
    );
  }

  /// Signs in again with [password], so the next call's token is fresh.
  Future<void> reauthenticate(String password) async {
    final User? user = _auth.currentUser;
    final String email = (user?.email ?? '').trim();
    if (user == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'requires-recent-login',
        message: 'Please sign in again.',
      );
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
    await user.getIdToken(true);
  }

  Future<void> promote(String uid, {required bool superAdmin}) =>
      _functions.httpsCallable('promoteToAdmin').call(<String, dynamic>{
        'uid': uid,
        'level': superAdmin ? 'super' : 'admin',
      });

  Future<void> setLevel(String uid, {required bool superAdmin}) =>
      _functions.httpsCallable('setAdminLevel').call(<String, dynamic>{
        'uid': uid,
        'level': superAdmin ? 'super' : 'admin',
      });

  Future<void> remove(String uid) => _functions
      .httpsCallable('removeAdminAccess')
      .call(<String, dynamic>{'uid': uid});
}
