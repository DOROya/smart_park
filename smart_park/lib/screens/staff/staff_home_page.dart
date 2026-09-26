import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/gate_scan_service.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_activity_details.dart';
import '../../widgets/sp_loading.dart';
import '../auth/sign_in_screen.dart';
import 'walk_in_panel.dart';

part 'staff_home_page_fragments.dart';

class StaffHomePage extends StatefulWidget {
  const StaffHomePage({super.key});

  @override
  State<StaffHomePage> createState() => _StaffHomePageState();
}

class _StaffHomePageState extends State<StaffHomePage>
    with SingleTickerProviderStateMixin, SpStreamCache<StaffHomePage> {
  final PermissionService _permissionService = const PermissionService();

  late Future<DocumentSnapshot<Map<String, dynamic>>> _userFuture;
  late TabController _historyTabController;

  int _selectedNavIndex = 0;
  String _historyFilter = 'all';
  DateTime _selectedHistoryDate = DateTime.now();

  String? _assignedFacilityId;
  String? _ownerId;

  /// Name from the owner-created staff record; falls back to the auth
  /// display name, which is set to the same name when the account is made.
  String _staffName = '';

  /// Set when the owner deactivates this account, even mid-shift.
  bool _deactivated = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _staffRecordSub;

  final GateScanService _gateService = GateScanService();
  late final MobileScannerController _scannerController;
  bool _isProcessingScan = false;
  GateScanResult? _lastScanResult;
  bool _markingOvertime = false;

  /// Staff-side gate direction. Entry/exit is chosen here in the app and is
  /// never taken from the scanned QR content.
  String _gateMode = 'entry';

  @override
  void initState() {
    super.initState();

    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    _userFuture = FirebaseFirestore.instance.collection('users').doc(uid).get();

    _historyTabController = TabController(length: 4, vsync: this);
    _historyTabController.addListener(() {
      if (_historyTabController.indexIsChanging) {
        return;
      }

      setState(() {
        _historyFilter = switch (_historyTabController.index) {
          0 => 'all',
          1 => 'entry',
          2 => 'exit',
          _ => 'active',
        };
      });
    });

    unawaited(_resolveAssignedFacility());
    _watchStaffRecord();
  }

  void _watchStaffRecord() {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _staffRecordSub = FirebaseFirestore.instance
        .collection('staff_accounts')
        .doc(uid)
        .snapshots()
        .listen(
          (DocumentSnapshot<Map<String, dynamic>> snap) {
            final Map<String, dynamic>? data = snap.data();
            final bool deactivated = data != null && !isStaffRecordActive(data);
            if (deactivated != _deactivated && mounted) {
              setState(() => _deactivated = deactivated);
              if (deactivated) unawaited(_scannerController.stop());
            }
          },
          // Missing or unreadable record: resolveAssignment already covers it.
          onError: (Object _) {},
        );
  }

  @override
  void dispose() {
    unawaited(_staffRecordSub?.cancel());
    _scannerController.dispose();
    _historyTabController.dispose();
    super.dispose();
  }

  Future<void> _resolveAssignedFacility() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final StaffAssignment assignment = await _gateService.resolveAssignment(
      uid: user.uid,
      email: user.email ?? '',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _deactivated = assignment.deactivated;
      _assignedFacilityId = assignment.facilityId;
      _ownerId = assignment.ownerId;
      _staffName = assignment.staffName.isNotEmpty
          ? assignment.staffName
          : (user.displayName ?? '').trim();
    });
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) {
      return;
    }
    unawaited(
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
        (Route<dynamic> route) => false,
      ),
    );
  }

  Future<void> _showChangePasswordDialog() {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) =>
          const _StaffChangePasswordDialog(),
    );
  }

  /// The signed-in staff member, or null when signed out.
  GateStaff? _currentStaff() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }
    return GateStaff(
      staffId: user.uid,
      email: user.email ?? '',
      facilityId: _assignedFacilityId,
      ownerId: _ownerId,
      name: _staffName,
    );
  }

  /// Shows [result]; null means the scan was ignored as a duplicate.
  void _presentGateResult(GateScanResult? result) {
    _isProcessingScan = false;
    if (result == null || !mounted) {
      return;
    }
    // Guards often look at the car, not the screen: one tap for allowed,
    // a heavy buzz for denied or error.
    if (result.isAllowed) {
      unawaited(HapticFeedback.mediumImpact());
    } else {
      unawaited(HapticFeedback.heavyImpact());
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 150),
          HapticFeedback.heavyImpact,
        ),
      );
    }
    setState(() {
      _lastScanResult = result;
    });
  }

  void _onBarcodeDetect(BarcodeCapture capture) {
    final String raw = capture.barcodes.isEmpty
        ? ''
        : (capture.barcodes.first.rawValue ?? '').trim();
    if (raw.isEmpty || _isProcessingScan) {
      return;
    }

    _isProcessingScan = true;
    unawaited(_handleScanPayload(raw));
  }

  Future<void> _handleScanPayload(String rawPayload) async {
    final GateStaff? staff = _currentStaff();
    if (staff == null) {
      _isProcessingScan = false;
      return;
    }
    _presentGateResult(
      await _gateService.handleScanPayload(
        staff: staff,
        gateMode: _gateMode,
        rawPayload: rawPayload,
      ),
    );
  }

  Future<void> _lookupByPlate(String rawPlate) async {
    final GateStaff? staff = _currentStaff();
    if (staff == null) {
      return;
    }
    _isProcessingScan = true;
    _presentGateResult(
      await _gateService.lookupByPlate(
        staff: staff,
        gateMode: _gateMode,
        rawPlate: rawPlate,
      ),
    );
  }

  /// Confirms the overtime cash on the exit just scanned.
  Future<void> _markLastOvertimeCollected() async {
    final GateScanResult? result = _lastScanResult;
    final String transactionId = result?.transactionId ?? '';
    if (result == null || transactionId.isEmpty || _markingOvertime) return;
    setState(() => _markingOvertime = true);
    final bool ok = await _markOvertimeCollected(
      transactionId,
      exitLogId: result.activityLogId,
    );
    if (!mounted) return;
    setState(() {
      _markingOvertime = false;
      // Only update the card if no newer scan replaced it meanwhile.
      if (ok && identical(_lastScanResult, result)) {
        _lastScanResult = result.markedCollected();
      }
    });
  }

  /// Confirms the overtime cash on an exit log opened from the scan lists.
  Future<void> _markLogOvertimeCollected(Map<String, dynamic> log) async {
    final String transactionId = ((log['transactionId'] as String?) ?? '')
        .trim();
    if (transactionId.isEmpty) return;
    if (!await _markOvertimeCollected(transactionId)) {
      throw StateError('Overtime cash was not saved.');
    }
  }

  Future<bool> _markOvertimeCollected(
    String transactionId, {
    String? exitLogId,
  }) async {
    final GateStaff? staff = _currentStaff();
    if (staff == null) return false;
    try {
      await _gateService.markOvertimeCollected(
        staff: staff,
        transactionId: transactionId,
        exitLogId: exitLogId,
      );
      unawaited(HapticFeedback.mediumImpact());
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(
                error,
                fallback: 'Could not save. Check your connection and retry.',
              ),
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _pickHistoryDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedHistoryDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _selectedHistoryDate = picked;
    });
  }

  bool _matchesHistoryFilter(Map<String, dynamic> data) {
    if (_historyFilter == 'all') {
      return true;
    }

    final String scanType = ((data['scanType'] as String?) ?? '').toLowerCase();
    final bool isActive = (data['isActive'] as bool?) ?? false;

    if (_historyFilter == 'entry') {
      return scanType == 'entry';
    }
    if (_historyFilter == 'exit') {
      return scanType == 'exit';
    }
    return isActive;
  }

  Widget _buildDeactivated() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_off_rounded,
                  size: 56,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  'Account deactivated',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your parking owner has deactivated this staff account, so '
                  'it can no longer scan at the gate. Ask them to reactivate '
                  'it if this is a mistake.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_deactivated) return _buildDeactivated();
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _userFuture,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
          ) {
            final Map<String, dynamic> userData =
                snapshot.data?.data() ?? <String, dynamic>{'role': 'Guard'};

            return Scaffold(
              appBar: AppBar(
                backgroundColor: AppTheme.surface,
                elevation: 0,
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
                actions: [
                  IconButton(
                    onPressed: () => ThemeController.instance.setMode(
                      AppTheme.isDark ? AppThemeMode.light : AppThemeMode.dark,
                    ),
                    icon: Icon(
                      AppTheme.isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                    ),
                    tooltip: AppTheme.isDark ? 'Light mode' : 'Dark mode',
                  ),
                  IconButton(
                    onPressed: _showChangePasswordDialog,
                    icon: const Icon(Icons.settings_rounded),
                    tooltip: 'Change Password',
                  ),
                  IconButton(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout_rounded),
                    tooltip: 'Sign Out',
                  ),
                ],
              ),
              body: _buildBody(userData),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _selectedNavIndex,
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
                onTap: (int index) {
                  setState(() {
                    _selectedNavIndex = index;
                  });
                },
                items: [
                  _navItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
                  _navItem(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'QR Scanning',
                    emphasized: true,
                  ),
                  _navItem(icon: Icons.history_rounded, label: 'History'),
                ],
              ),
            );
          },
    );
  }
}

/// Lets a signed-in staff member change their own password. Firebase
/// requires a recent sign-in before `updatePassword`, so the current
/// password is re-collected here and used to reauthenticate first.
class _StaffChangePasswordDialog extends StatefulWidget {
  const _StaffChangePasswordDialog();

  @override
  State<_StaffChangePasswordDialog> createState() =>
      _StaffChangePasswordDialogState();
}

class _StaffChangePasswordDialogState
    extends State<_StaffChangePasswordDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateNewPassword(String? value) {
    final String password = value ?? '';
    if (password.length < 8) {
      return 'At least 8 characters.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Include an uppercase letter.';
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Include a number.';
    }
    return null;
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    required bool obscured,
    required VoidCallback onToggleObscure,
  }) {
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      borderSide: BorderSide(color: AppTheme.border),
    );
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppTheme.surfaceAlt,
      prefixIcon: Icon(icon, color: AppTheme.textMuted, size: 20),
      suffixIcon: IconButton(
        icon: Icon(
          obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          color: AppTheme.textMuted,
          size: 20,
        ),
        onPressed: onToggleObscure,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: AppTheme.danger),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'New passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('No signed-in staff account found.');
      }

      await user.updatePassword(_newPasswordController.text);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));
    } on FirebaseAuthException catch (error) {
      setState(() {
        _errorMessage = error.code == 'requires-recent-login'
            ? 'For security, please sign out and sign back in, then try again.'
            : friendlyError(error, fallback: 'Unable to update password.');
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  ),
                  child: Icon(
                    Icons.lock_reset_rounded,
                    color: AppTheme.accentText,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Change Password',
                  style: TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set a new password for your staff account.',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerSoft,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      border: Border.all(color: AppTheme.dangerBorder),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: AppTheme.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscureNew,
                  decoration: _fieldDecoration(
                    label: 'New Password',
                    icon: Icons.lock_outline_rounded,
                    obscured: _obscureNew,
                    onToggleObscure: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                  validator: _validateNewPassword,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  decoration: _fieldDecoration(
                    label: 'Confirm New Password',
                    icon: Icons.lock_outline_rounded,
                    obscured: _obscureConfirm,
                    onToggleObscure: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (value) =>
                      (value == null || value.isEmpty) ? 'Required.' : null,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    'Password should be at least 8 characters with one uppercase letter and one number.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textDark,
                          side: BorderSide(color: AppTheme.border),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radius,
                            ),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: AppTheme.onAccent,
                          minimumSize: const Size.fromHeight(46),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radius,
                            ),
                          ),
                        ),
                        child: _submitting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.onAccent,
                                ),
                              )
                            : const Text(
                                'Update',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
