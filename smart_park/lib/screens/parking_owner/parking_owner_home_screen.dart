library;

// ignore_for_file: file_names, invalid_use_of_protected_member

import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../models/facility_registration_data.dart';
import '../../services/error_reporter.dart';
import '../../services/gate_scan_service.dart'
    show
        isStaffRecordActive,
        kOvertimeCashDue,
        kOvertimeCollected,
        setOvertimeStatusAsOwner;
import '../../services/establishment_repository.dart';
import '../../services/platform_fees.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/staff_credentials.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_activity_details.dart';
import '../../widgets/sp_loading.dart';
import '../../widgets/sp_overtime.dart';
import '../../widgets/sp_profile_view.dart';
import '../auth/sign_in_screen.dart';
import 'widgets/facility_registration_dialog.dart';
import 'widgets/facility_review_status_banner.dart';

part 'parking_owner_home_fragments.dart';
part 'parking_owner_commissions.dart';
part 'parking_owner_gate_activity.dart';

class ParkingOwnerHomePage extends StatefulWidget {
  const ParkingOwnerHomePage({super.key, this.role = 'parking owner'});

  final String role;

  @override
  State<ParkingOwnerHomePage> createState() => _ParkingOwnerHomePageState();
}

class _ParkingOwnerHomePageState extends State<ParkingOwnerHomePage>
    with SpStreamCache<ParkingOwnerHomePage> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _userFuture;
  final EstablishmentRepository _establishmentRepository =
      const EstablishmentRepository();

  int _selectedIndex = 0;
  bool _addingStaff = false;
  bool _railExtended = false;

  /// Staff uid the Activity tab is filtered to; set from the Staff tab.
  String? _activityStaffId;

  final GlobalKey<FormState> _staffFormKey = GlobalKey<FormState>();
  final TextEditingController _staffNameController = TextEditingController();

  final TextEditingController _profileFirstNameController =
      TextEditingController();
  final TextEditingController _profileLastNameController =
      TextEditingController();
  final TextEditingController _profileEmailController = TextEditingController();

  bool _profileSeeded = false;

  @override
  void initState() {
    super.initState();
    _userFuture = _fetchUserDocument();
    unawaited(_migrateLegacyStaffDocs());
    unawaited(_migrateBusinessDocumentUrls());
  }

  @override
  void dispose() {
    _staffNameController.dispose();
    _profileFirstNameController.dispose();
    _profileLastNameController.dispose();
    _profileEmailController.dispose();
    super.dispose();
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

  /// Staff records used to get random document ids. Security rules look a
  /// staff member up by `staff_accounts/{their uid}`, so move any old record
  /// to that id. Only the owner may write their staff records, so this runs
  /// here rather than on the staff member's device.
  Future<void> _migrateLegacyStaffDocs() async {
    final String? ownerId = FirebaseAuth.instance.currentUser?.uid;
    if (ownerId == null) return;
    try {
      final CollectionReference<Map<String, dynamic>> staff = FirebaseFirestore
          .instance
          .collection('staff_accounts');
      final QuerySnapshot<Map<String, dynamic>> snapshot = await staff
          .where('ownerId', isEqualTo: ownerId)
          .get();
      final WriteBatch batch = FirebaseFirestore.instance.batch();
      int moved = 0;
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        final String staffUid = ((doc.data()['userId'] as String?) ?? '')
            .trim();
        if (staffUid.isEmpty || staffUid == doc.id) continue;
        batch.set(staff.doc(staffUid), doc.data());
        batch.delete(doc.reference);
        moved++;
      }
      if (moved > 0) await batch.commit();
    } catch (error, stack) {
      reportError(error, stack, reason: 'Staff record migration failed');
    }
  }

  /// Business document URLs used to sit on `establishment_details`, which
  /// every driver can read. Move them to the owner/admin-only
  /// `establishment_private` doc.
  Future<void> _migrateBusinessDocumentUrls() async {
    final String? ownerId = FirebaseAuth.instance.currentUser?.uid;
    if (ownerId == null) return;
    final FirebaseFirestore db = FirebaseFirestore.instance;
    try {
      final QuerySnapshot<Map<String, dynamic>> owned = await db
          .collection('establishments')
          .where('ownerId', isEqualTo: ownerId)
          .get();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> est
          in owned.docs) {
        final DocumentReference<Map<String, dynamic>> detailsRef = db
            .collection('establishment_details')
            .doc(est.id);
        final Map<String, dynamic>? details = (await detailsRef.get()).data();
        if (details == null || !details.containsKey('businessDocumentUrls')) {
          continue;
        }
        final WriteBatch batch = db.batch();
        batch.set(
          db.collection('establishment_private').doc(est.id),
          <String, dynamic>{
            'establishmentID': est.id,
            'businessDocumentUrls': details['businessDocumentUrls'],
            'businessDocumentsUpdatedAt':
                details['businessDocumentsUpdatedAt'] ??
                FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        batch.update(detailsRef, <String, dynamic>{
          'businessDocumentUrls': FieldValue.delete(),
          'businessDocumentsUpdatedAt': FieldValue.delete(),
        });
        await batch.commit();
      }
    } catch (error, stack) {
      reportError(error, stack, reason: 'Document URL migration failed');
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _fetchUserDocument() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    final String? uid = currentUser?.uid;
    if (uid == null) {
      throw StateError('No logged-in user found.');
    }

    final String normalizedEmail = (currentUser?.email ?? '')
        .trim()
        .toLowerCase();
    final CollectionReference<Map<String, dynamic>> usersCollection =
        FirebaseFirestore.instance.collection('users');

    final DocumentSnapshot<Map<String, dynamic>> byUid = await usersCollection
        .doc(uid)
        .get();
    if (byUid.exists) {
      return byUid;
    }

    final QuerySnapshot<Map<String, dynamic>> byUserId = await usersCollection
        .where('userID', isEqualTo: uid)
        .limit(1)
        .get();
    if (byUserId.docs.isNotEmpty) {
      final Map<String, dynamic> data = byUserId.docs.first.data();
      await _backfillUserDocument(uid: uid, email: normalizedEmail, data: data);
      return usersCollection.doc(uid).get();
    }

    if (normalizedEmail.isNotEmpty) {
      final QuerySnapshot<Map<String, dynamic>> byEmail = await usersCollection
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) {
        final Map<String, dynamic> data = byEmail.docs.first.data();
        await _backfillUserDocument(
          uid: uid,
          email: normalizedEmail,
          data: data,
        );
        return usersCollection.doc(uid).get();
      }
    }

    return byUid;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
        (Route<dynamic> route) => false,
      ),
    );
  }

  void _seedProfileControllers(Map<String, dynamic> ownerData) {
    if (_profileSeeded) return;
    _profileSeeded = true;
    _profileFirstNameController.text =
        (ownerData['firstName'] as String?)?.trim() ?? '';
    _profileLastNameController.text =
        (ownerData['lastName'] as String?)?.trim() ?? '';
    _profileEmailController.text =
        (ownerData['email'] as String?)?.trim() ??
        (FirebaseAuth.instance.currentUser?.email ?? '');
  }

  String _generateRandomPassword({int length = 10}) {
    const String alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#';
    final Random random = Random.secure();
    return List<String>.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  /// Short random per-owner tag (e.g. "hx37e") so every owner's staff
  /// usernames live in their own namespace and never collide across owners.
  String _generateOwnerPrefix({int length = 5}) {
    const String alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
    final Random random = Random.secure();
    return List<String>.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  String _slugifyStaffName(String name) {
    final String cleaned = name.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    return cleaned.isEmpty ? 'staff' : cleaned;
  }

  Future<String> _ensureOwnerStaffPrefix(String ownerId) async {
    final DocumentReference<Map<String, dynamic>> ownerRef = FirebaseFirestore
        .instance
        .collection('users')
        .doc(ownerId);
    final DocumentSnapshot<Map<String, dynamic>> ownerSnap = await ownerRef
        .get();
    final String existing =
        (ownerSnap.data()?['staffUsernamePrefix'] as String?)?.trim() ?? '';
    if (existing.isNotEmpty) {
      return existing;
    }

    final String prefix = _generateOwnerPrefix();
    await ownerRef.set(<String, dynamic>{
      'staffUsernamePrefix': prefix,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return prefix;
  }

  Future<void> _addStaff({
    required String ownerId,
    required String facilityId,
  }) async {
    if (_addingStaff || !_staffFormKey.currentState!.validate()) return;
    setState(() => _addingStaff = true);

    // A staff member needs a real Firebase Auth sign-in, not just a
    // Firestore record. Creating it via `FirebaseAuth.instance` would sign
    // the owner out of their own session, so it's done on a throwaway
    // secondary Firebase App instance instead, torn down once we're done.
    FirebaseApp? staffCreationApp;

    try {
      if (facilityId.trim().isEmpty) {
        _showSnackBar('Register a facility first before adding staff.');
        return;
      }

      final String staffName = _staffNameController.text.trim();
      final String prefix = await _ensureOwnerStaffPrefix(ownerId);
      final String baseUsername = '${prefix}_${_slugifyStaffName(staffName)}';
      final String generatedPassword = _generateRandomPassword();

      staffCreationApp = await Firebase.initializeApp(
        name: 'staffCreation_${DateTime.now().microsecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final FirebaseAuth staffAuth = FirebaseAuth.instanceFor(
        app: staffCreationApp,
      );

      String username = baseUsername;
      UserCredential? credential;
      // Usernames are derived from the name and can collide (two "Juan"s
      // under the same owner); retry with a numeric suffix on collision
      // rather than failing the whole add-staff action.
      for (int attempt = 1; attempt <= 6 && credential == null; attempt++) {
        username = attempt == 1 ? baseUsername : '$baseUsername$attempt';
        try {
          credential = await staffAuth.createUserWithEmailAndPassword(
            email: staffUsernameToAuthEmail(username),
            password: generatedPassword,
          );
        } on FirebaseAuthException catch (error) {
          if (error.code != 'email-already-in-use' || attempt == 6) {
            rethrow;
          }
        }
      }

      final String? staffUid = credential?.user?.uid;
      if (staffUid == null) {
        throw StateError('Unable to create the staff sign-in account.');
      }
      await credential!.user!.updateDisplayName(staffName);

      // Keyed by the staff member's uid so security rules can find it.
      await FirebaseFirestore.instance
          .collection('staff_accounts')
          .doc(staffUid)
          .set({
            'userId': staffUid,
            'ownerId': ownerId,
            'facilityId': facilityId,
            'establishmentID': facilityId,
            'name': staffName,
            'username': username,
            'email': staffUsernameToAuthEmail(username),
            'role': 'staff',
            'isOnline': false,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      _staffNameController.clear();
      if (!mounted) return;
      await _showStaffCredentialsDialog(
        username: username,
        password: generatedPassword,
      );
    } on FirebaseAuthException catch (error) {
      _showSnackBar(
        error.code == 'email-already-in-use'
            ? 'That staff username is already taken. Try again.'
            : friendlyError(
                error,
                fallback: 'Unable to create the staff account.',
              ),
      );
    } finally {
      if (staffCreationApp != null) {
        await FirebaseAuth.instanceFor(app: staffCreationApp).signOut();
        await staffCreationApp.delete();
      }
      if (mounted) setState(() => _addingStaff = false);
    }
  }

  Future<void> _showStaffCredentialsDialog({
    required String username,
    required String password,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Staff account created'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Share these sign-in details with the staff member now. '
                'The password is shown only this once and is not stored '
                'anywhere.',
              ),
              const SizedBox(height: 16),
              SelectableText('Username: $username'),
              const SizedBox(height: 4),
              SelectableText('Temporary password: $password'),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(
                    text: 'Username: $username\nPassword: $password',
                  ),
                );
                _showSnackBar('Credentials copied to clipboard.');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  /// Deactivating keeps the staff record (so their past scans keep a name)
  /// but blocks them at the gate; the setStaffSignInState function also
  /// disables their sign-in. Reactivating undoes both.
  Future<void> _setStaffActive(
    String staffDocId,
    String staffName, {
    required bool active,
  }) async {
    if (!active) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Deactivate staff?'),
            content: Text(
              '$staffName will be signed out and can no longer scan at your '
              'gate. Scans they already recorded stay in Activity. You can '
              'reactivate them later from the Deactivated list.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                child: const Text('Deactivate'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        return;
      }
    }

    try {
      await FirebaseFirestore.instance
          .collection('staff_accounts')
          .doc(staffDocId)
          .update(<String, dynamic>{
            'active': active,
            'deactivatedAt': active
                ? FieldValue.delete()
                : FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _showSnackBar(
        active ? '$staffName reactivated.' : '$staffName deactivated.',
      );
    } catch (error, stack) {
      reportError(error, stack, reason: 'Changing staff active state failed');
      _showSnackBar(
        friendlyError(error, fallback: 'Unable to update this staff member.'),
      );
    }
  }

  Future<Map<String, dynamic>?> _loadFacilityData(
    String establishmentId,
  ) async {
    if (establishmentId.trim().isEmpty) {
      return null;
    }

    final DocumentReference<Map<String, dynamic>> establishmentRef =
        FirebaseFirestore.instance
            .collection('establishments')
            .doc(establishmentId);
    final DocumentReference<Map<String, dynamic>> detailsRef = FirebaseFirestore
        .instance
        .collection('establishment_details')
        .doc(establishmentId);

    final DocumentReference<Map<String, dynamic>> privateRef = FirebaseFirestore
        .instance
        .collection('establishment_private')
        .doc(establishmentId);

    final List<DocumentSnapshot<Map<String, dynamic>>> snapshots =
        await Future.wait(<Future<DocumentSnapshot<Map<String, dynamic>>>>[
          establishmentRef.get(),
          detailsRef.get(),
          privateRef.get(),
        ]);

    final Map<String, dynamic> establishmentData =
        snapshots[0].data() ?? <String, dynamic>{};
    final Map<String, dynamic> detailsData =
        snapshots[1].data() ?? <String, dynamic>{};
    final Map<String, dynamic> privateData =
        snapshots[2].data() ?? <String, dynamic>{};

    if (establishmentData.isEmpty && detailsData.isEmpty) {
      return null;
    }

    return <String, dynamic>{
      ...establishmentData,
      ...detailsData,
      ...privateData,
      'establishmentID': establishmentId,
    };
  }

  String _resolveFacilityId(Map<String, dynamic> ownerData) {
    return ((ownerData['establishmentId'] as String?) ??
            (ownerData['establishmentID'] as String?) ??
            (ownerData['facilityId'] as String?) ??
            '')
        .trim();
  }

  Future<void> _openFacilityDialog({
    required String ownerId,
    required Map<String, dynamic> ownerData,
  }) async {
    final NavigatorState navigator = Navigator.of(context);
    String establishmentId = _resolveFacilityId(ownerData);

    if (establishmentId.isEmpty) {
      final QuerySnapshot<Map<String, dynamic>> estQuery =
          await FirebaseFirestore.instance
              .collection('establishments')
              .where('ownerId', isEqualTo: ownerId)
              .limit(1)
              .get();
      if (estQuery.docs.isNotEmpty) {
        establishmentId = estQuery.docs.first.id;
      }
    }

    final Map<String, dynamic>? facilityData = await _loadFacilityData(
      establishmentId,
    );

    if (!mounted) {
      return;
    }

    String? savedEstablishmentId = facilityData == null
        ? null
        : establishmentId;
    Map<String, dynamic>? currentData = facilityData;

    Future<Map<String, dynamic>?> save(
      FacilityRegistrationData formData,
    ) async {
      final ({
        String establishmentId,
        bool submittedForReview,
        int failedDocumentUploads,
      })
      result;
      try {
        result = await _establishmentRepository.saveFacility(
          ownerId: ownerId,
          ownerData: ownerData,
          formData: formData,
          establishmentId: savedEstablishmentId,
          previousStatus: currentData?['status'] as String?,
        );
      } catch (error, stack) {
        reportError(error, stack, reason: 'Saving facility failed');
        _showSnackBar(
          friendlyError(error, fallback: 'Unable to save the facility.'),
        );
        return null;
      }

      final bool wasCreate = savedEstablishmentId == null;
      savedEstablishmentId = result.establishmentId;
      currentData = await _loadFacilityData(result.establishmentId);

      if (mounted) {
        setState(() {
          _userFuture = _fetchUserDocument();
        });
        _showSnackBar(
          result.failedDocumentUploads > 0
              ? '${result.failedDocumentUploads} business document(s) failed '
                    'to upload. Add them again and save.'
              : wasCreate
              ? 'Facility registered and submitted for admin review.'
              : result.submittedForReview
              ? 'Facility updated and resubmitted for admin review.'
              : 'Facility updated.',
        );
      }
      return currentData;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            FacilityRegistrationPage(facilityData: facilityData, onSave: save),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _userFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SpLoadingScreen();
        }
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(child: Text('Unable to load owner profile.')),
          );
        }

        final Map<String, dynamic> ownerData = snapshot.data!.data()!;
        final String role = ((ownerData['role'] as String?) ?? widget.role)
            .toLowerCase();
        final String ownerId = FirebaseAuth.instance.currentUser!.uid;

        _seedProfileControllers(ownerData);

        final bool isTablet = spIsTablet(context);
        final Widget body = _buildBody(
          ownerId: ownerId,
          ownerData: ownerData,
          role: role,
        );

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppTheme.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            leading: isTablet
                ? SpMenuToggleButton(
                    extended: _railExtended,
                    onPressed: () =>
                        setState(() => _railExtended = !_railExtended),
                  )
                : null,
            titleSpacing: isTablet ? 0 : null,
            actions: [_buildProfileAvatarButton(), const SizedBox(width: 12)],
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_parking_rounded, color: AppTheme.textDark),
                SizedBox(width: 8),
                Text(
                  'SmartPark',
                  style: TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          body: isTablet
              ? SpRailLayout(
                  rail: SpNavRail(
                    items: _navItems,
                    selectedIndex: _selectedIndex,
                    onSelected: (index) =>
                        setState(() => _selectedIndex = index),
                    extended: _railExtended,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: body,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: body,
                ),
          bottomNavigationBar: isTablet
              ? null
              : BottomNavigationBar(
                  currentIndex: _selectedIndex,
                  backgroundColor: AppTheme.surface,
                  elevation: 10,
                  selectedItemColor: AppTheme.textDark,
                  unselectedItemColor: AppTheme.textMuted,
                  showSelectedLabels: true,
                  showUnselectedLabels: true,
                  type: BottomNavigationBarType.fixed,
                  selectedLabelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  onTap: (index) => setState(() => _selectedIndex = index),
                  items: [
                    for (final (
                          IconData icon,
                          IconData activeIcon,
                          String label,
                        )
                        in _navItems)
                      BottomNavigationBarItem(
                        icon: Icon(icon),
                        activeIcon: Icon(activeIcon),
                        label: label,
                      ),
                  ],
                ),
        );
      },
    );
  }

  static const List<(IconData, IconData, String)> _navItems =
      <(IconData, IconData, String)>[
        (Icons.apartment_outlined, Icons.apartment_rounded, 'Facility'),
        (Icons.badge_outlined, Icons.badge_rounded, 'Staff'),
        (
          Icons.directions_car_outlined,
          Icons.directions_car_rounded,
          'Activity',
        ),
        (Icons.payments_outlined, Icons.payments_rounded, 'Finance'),
        (Icons.person_outlined, Icons.person_rounded, 'Profile'),
      ];

  /// App bar shortcut to the Profile tab, where the owner signs out.
  Widget _buildProfileAvatarButton() {
    final String name =
        '${_profileFirstNameController.text} ${_profileLastNameController.text}'
            .trim();
    return SpAccountAvatarButton(
      active: _selectedIndex == 4,
      onTap: () => setState(() => _selectedIndex = 4),
      child: Text(name.isEmpty ? 'P' : _initials(name)),
    );
  }
}
