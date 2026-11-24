library;

// ignore_for_file: file_names, invalid_use_of_protected_member

import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../models/facility_registration_data.dart';
import '../../services/activity_export.dart';
import '../../services/app_shortcuts.dart';
import '../../services/error_reporter.dart';
import '../../services/local_save.dart'
    show saveFileToDevice, kDownloadsFolderLabel;
import '../../services/facility_closure.dart' show hoursWithClosure;
import '../../services/operating_hours.dart';
import '../../services/parking_push.dart';
import '../../services/facility_status.dart'
    show ComplianceNotice, facilityRestrictionReasons;
import '../../services/gate_scan_service.dart'
    show
        isStaffRecordActive,
        kOvertimeCashDue,
        kOvertimeCollected,
        setOvertimeStatusAsOwner;
import '../../services/establishment_repository.dart';
import '../../services/driver_reports.dart' show driverReportsSummary;
import '../../services/parking_pricing.dart'
    show
        facilityGraceMinutes,
        formatGracePeriod,
        formatParkingHours,
        graceOptionLabel;
import '../../services/platform_fees.dart';
import '../../services/sales_report.dart';
import '../../services/sales_report_pdf.dart'
    show SalesReportAudience, formatSalesChange, salesChange, salesReportPeriod;
import '../../theme/app_theme.dart';
import '../../widgets/smartpark_logo.dart';
import '../../utils/friendly_error.dart';
import '../../utils/staff_credentials.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_vehicle_type.dart';
import '../../widgets/sp_audit_log.dart';
import '../../widgets/sp_announcements.dart';
import '../../widgets/sp_refunds_section.dart';
import '../../widgets/sp_activity_details.dart';
import '../../widgets/sp_activity_search.dart';
import '../../widgets/sp_driver_report.dart';
import '../../widgets/sp_export_sheet.dart' show showSpSaveResult;
import '../../widgets/sp_loading.dart';
import '../../widgets/sp_connection.dart';
import '../../widgets/sp_sales_report_card.dart';
import '../../widgets/sp_overtime.dart';
import '../../widgets/sp_profile_view.dart';
import '../auth/sign_in_screen.dart';
import 'widgets/owner_cash_handover_card.dart';
import 'widgets/owner_closure_card.dart';
import 'widgets/owner_daily_summary_card.dart';
import 'widgets/owner_duty_log_card.dart';
import 'widgets/owner_ratings_card.dart';
import 'widgets/owner_walk_in_cash_row.dart';
import 'widgets/facility_registration_dialog.dart';
import 'widgets/facility_review_status_banner.dart';
import '../staff/staff_home_page.dart';
import 'widgets/parking_trends_card.dart';

part 'parking_owner_home_fragments.dart';
part 'parking_owner_commissions.dart';
part 'parking_owner_gate_activity.dart';

/// The facility a supervisor runs for its owner (docs/supervisor-role.md).
class SupervisorScope {
  const SupervisorScope({
    required this.facilityId,
    required this.ownerId,
    required this.name,
  });

  final String facilityId;

  /// The facility's owner, who keeps prices, earnings and hiring.
  final String ownerId;
  final String name;
}

class ParkingOwnerHomePage extends StatefulWidget {
  const ParkingOwnerHomePage({
    super.key,
    this.role = 'parking owner',
    this.supervisor,
  });

  final String role;

  /// Set for a supervisor: the same screens, without the owner-only parts
  /// (Reports, facility editing, hiring). The security rules enforce it.
  final SupervisorScope? supervisor;

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

  /// The Add Staff form's choice: gate staff or a supervisor.
  bool _newStaffIsSupervisor = false;

  bool get _supervisor => widget.supervisor != null;

  AnnouncementWatcher? _announcements;

  /// "Open scanner" from the app icon, for a supervisor.
  void _onShortcut() {
    if (!mounted || pendingShortcut.value != kOpenScannerShortcut) return;
    // The scanner is already open on top: it switches to its own tab.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    pendingShortcut.value = null;
    _openGateScanner(scannerTab: true);
  }

  bool _railExtended = false;

  /// Staff uid the Activity tab is filtered to; set from the Staff tab.
  String? _activityStaffId;

  /// Staff record whose password is being reset, to show progress.
  String? _resettingStaffId;

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
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // Refund, dispute, permit, facility decision and staff flag notices
      // from the server.
      unawaited(
        ParkingPush.register(
          uid,
          onForeground: (String title, String body) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$title\n$body'),
                duration: const Duration(seconds: 8),
              ),
            );
          },
          // A decision or a staff flag: both are on the Facility tab.
          onOpen: (Map<String, dynamic> data) {
            if (!mounted) return;
            if (data['kind'] == 'announcement') {
              unawaited(_announcements?.check());
              return;
            }
            // The end-of-day summary: Staff when cash or a shift needs
            // action, else Reports.
            if (data['kind'] == 'owner_daily_summary') {
              setState(() => _selectedIndex = data['tab'] == 'staff' ? 1 : 3);
              return;
            }
            if (data['kind'] == 'owner_facility_status' ||
                data['kind'] == 'owner_staff_flag') {
              setState(() => _selectedIndex = 0);
            }
          },
        ),
      );
    }
    // Platform notices (a commission change goes to owners), never over
    // the gate scanner a supervisor opened.
    _announcements = AnnouncementWatcher(
      () => context,
      _supervisor ? 'supervisor' : 'Parking Owner',
      isCurrent: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _announcements?.start(),
    );
    if (_supervisor) {
      pendingShortcut.addListener(_onShortcut);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onShortcut());
    }
    // Owner-only housekeeping on records a supervisor can't write.
    if (!_supervisor) {
      unawaited(_migrateLegacyStaffDocs());
      unawaited(_migrateBusinessDocumentUrls());
    }
  }

  @override
  void dispose() {
    pendingShortcut.removeListener(_onShortcut);
    _announcements?.dispose();
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
    if (!await spConfirmSignOut(context)) return;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await ParkingPush.unregister(uid);
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
            'role': _newStaffIsSupervisor ? 'supervisor' : 'staff',
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
    String title = 'Staff account created',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
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

  /// Emergency reset for a staff member who lost their password or may have
  /// shared it: the resetStaffPassword function sets a new random password,
  /// signs out every device using the old one, and returns it once.
  Future<void> _resetStaffPassword(String staffDocId, String staffName) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Reset staff password?'),
          content: Text(
            '$staffName gets a new password and is signed out of every '
            'device. Their old password stops working right away. You will '
            'see the new password once, to give to them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              child: const Text('Reset Password'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _resettingStaffId = staffDocId);
    try {
      final HttpsCallableResult<dynamic> result =
          await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
              .httpsCallable('resetStaffPassword')
              .call<dynamic>(<String, dynamic>{'staffId': staffDocId});
      final Map<dynamic, dynamic> data = result.data is Map
          ? result.data as Map<dynamic, dynamic>
          : <dynamic, dynamic>{};
      final String password = (data['password'] as String?) ?? '';
      if (password.isEmpty) {
        throw StateError('No password came back from the reset.');
      }
      if (!mounted) return;
      await _showStaffCredentialsDialog(
        username: (data['username'] as String?) ?? '',
        password: password,
        title: 'Password reset',
      );
    } catch (error, stack) {
      reportError(error, stack, reason: 'Resetting staff password failed');
      _showSnackBar(
        friendlyError(error, fallback: 'Unable to reset this password.'),
      );
    } finally {
      if (mounted) setState(() => _resettingStaffId = null);
    }
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
  Widget build(BuildContext context) => SpBackToHomeTab(
    onHomeTab: _selectedIndex == 0,
    goHome: () => setState(() => _selectedIndex = 0),
    child: _buildScreen(context),
  );

  Widget _buildScreen(BuildContext context) {
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

        final SupervisorScope? supervisor = widget.supervisor;
        // A supervisor works on the owner's facility, under the owner's id.
        final Map<String, dynamic> ownerData = supervisor == null
            ? snapshot.data!.data()!
            : <String, dynamic>{
                // Staff profiles have no name fields; the staff record does.
                'firstName': supervisor.name.split(' ').first,
                'lastName': supervisor.name.split(' ').skip(1).join(' '),
                ...snapshot.data!.data()!,
                'establishmentId': supervisor.facilityId,
              };
        final String role = ((ownerData['role'] as String?) ?? widget.role)
            .toLowerCase();
        final String ownerId =
            supervisor?.ownerId ?? FirebaseAuth.instance.currentUser!.uid;

        _seedProfileControllers(ownerData);

        final bool isTablet = spIsTablet(context);
        final Widget body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SpConnectionBanner(),
            Expanded(
              child: SpPullToRefresh(
                child: _buildBody(
                  ownerId: ownerId,
                  ownerData: ownerData,
                  role: role,
                ),
              ),
            ),
          ],
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
                const SmartParkLogo(size: 28),
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
                    onSignOut: _signOut,
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

  List<(IconData, IconData, String)> get _navItems =>
      _supervisor ? _supervisorNavItems : _ownerNavItems;

  /// Same order as the owner's, with the gate scanner in place of Reports.
  static const List<(IconData, IconData, String)>
  _supervisorNavItems = <(IconData, IconData, String)>[
    (Icons.apartment_outlined, Icons.apartment_rounded, 'Facility'),
    (Icons.badge_outlined, Icons.badge_rounded, 'Staff'),
    (Icons.directions_car_outlined, Icons.directions_car_rounded, 'Activity'),
    (Icons.qr_code_scanner_outlined, Icons.qr_code_scanner_rounded, 'Scanner'),
    (Icons.person_outlined, Icons.person_rounded, 'Profile'),
  ];

  static const List<(IconData, IconData, String)> _ownerNavItems =
      <(IconData, IconData, String)>[
        (Icons.apartment_outlined, Icons.apartment_rounded, 'Facility'),
        (Icons.badge_outlined, Icons.badge_rounded, 'Staff'),
        (
          Icons.directions_car_outlined,
          Icons.directions_car_rounded,
          'Activity',
        ),
        (Icons.assessment_outlined, Icons.assessment_rounded, 'Reports'),
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
