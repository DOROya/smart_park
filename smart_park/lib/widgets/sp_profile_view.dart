import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/friendly_error.dart';
import 'smartpark_ui.dart';

/// Profile tab shared by drivers and parking owners: identity card,
/// editable name, and a password change hidden behind a button.
///
/// The name controllers belong to the parent so its app bar and greeting
/// can reflect edits; saving and password changes are handled here.
class SpProfileView extends StatefulWidget {
  const SpProfileView({
    super.key,
    required this.roleLabel,
    required this.firstNameController,
    required this.lastNameController,
    required this.email,
    required this.onSignOut,
    this.padding = EdgeInsets.zero,
    this.wide = false,
  });

  final String roleLabel;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final String email;
  final VoidCallback onSignOut;
  final EdgeInsetsGeometry padding;

  /// Tablet layout: identity and sign-out on the left, forms on the right.
  final bool wide;

  @override
  State<SpProfileView> createState() => _SpProfileViewState();
}

class _SpProfileViewState extends State<SpProfileView> {
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _savingProfile = false;
  bool _changingPassword = false;
  bool _passwordFormOpen = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _displayName {
    final String name =
        '${widget.firstNameController.text.trim()} '
                '${widget.lastNameController.text.trim()}'
            .trim();
    return name.isEmpty ? widget.roleLabel : name;
  }

  static String _initials(String name) {
    final List<String> parts = name
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _saveProfile() async {
    if (_savingProfile) return;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showSnackBar('No logged-in user found.');
      return;
    }
    final String firstName = widget.firstNameController.text.trim();
    final String lastName = widget.lastNameController.text.trim();
    if (firstName.isEmpty || lastName.isEmpty) {
      _showSnackBar('Please enter your first and last name.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _savingProfile = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(<String, dynamic>{
            'firstName': firstName,
            'lastName': lastName,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _showSnackBar('Profile updated.');
    } on FirebaseException catch (error) {
      _showSnackBar(
        friendlyError(error, fallback: 'Unable to save your profile.'),
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  void _closePasswordForm() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    FocusScope.of(context).unfocus();
    setState(() => _passwordFormOpen = false);
  }

  Future<void> _changePassword() async {
    if (_changingPassword) return;
    final User? user = FirebaseAuth.instance.currentUser;
    final String? email = user?.email;
    if (user == null || email == null) {
      _showSnackBar('No logged-in user found.');
      return;
    }

    final String currentPassword = _currentPasswordController.text;
    final String newPassword = _newPasswordController.text.trim();
    if (currentPassword.isEmpty) {
      _showSnackBar('Enter your current password.');
      return;
    }
    if (newPassword.length < 6) {
      _showSnackBar('New password must be at least 6 characters.');
      return;
    }
    if (newPassword != _confirmPasswordController.text.trim()) {
      _showSnackBar('New passwords do not match.');
      return;
    }
    if (newPassword == currentPassword) {
      _showSnackBar('Choose a password different from your current one.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _changingPassword = true);
    try {
      // Confirming the current password also satisfies Firebase's
      // recent-login requirement, so no sign-out is needed.
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
      await user.updatePassword(newPassword);
      if (!mounted) return;
      _closePasswordForm();
      _showSnackBar('Password changed successfully.');
    } on FirebaseAuthException catch (error) {
      switch (error.code) {
        case 'wrong-password':
        case 'invalid-credential':
          _showSnackBar('Your current password is incorrect.');
        case 'weak-password':
          _showSnackBar('That password is too weak. Try a longer one.');
        case 'too-many-requests':
          _showSnackBar('Too many attempts. Please wait a few minutes.');
        default:
          _showSnackBar(
            friendlyError(error, fallback: 'Unable to change your password.'),
          );
      }
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Widget header = SpPageHeader(
      title: 'Profile',
      subtitle: 'Your personal details and account security.',
    );

    if (widget.wide) {
      return ListView(
        padding: widget.padding,
        children: [
          header,
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _identityCard(),
                    const SizedBox(height: 12),
                    _signOutButton(),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _personalInfoCard(),
                    const SizedBox(height: 12),
                    _securityCard(),
                    const SizedBox(height: 12),
                    const SpAppearanceCard(),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    return ListView(
      padding: widget.padding,
      children: [
        header,
        const SizedBox(height: 16),
        _identityCard(),
        const SizedBox(height: 12),
        _personalInfoCard(),
        const SizedBox(height: 12),
        _securityCard(),
        const SizedBox(height: 12),
        const SpAppearanceCard(),
        const SizedBox(height: 12),
        _signOutButton(),
      ],
    );
  }

  Widget _identityCard() {
    final String name = _displayName;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppTheme.accentLight, AppTheme.accentWarm],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0x40FFFFFF),
            child: Text(
              _initials(name),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                if (widget.email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x40FFFFFF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.roleLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _personalInfoCard() {
    return SpSectionCard(
      icon: Icons.manage_accounts_rounded,
      title: 'Personal Information',
      subtitle: 'Keep your name accurate for bookings and receipts.',
      child: Column(
        children: [
          TextField(
            controller: widget.firstNameController,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: _fieldDecoration(
              label: 'First Name',
              icon: Icons.person_outline_rounded,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: widget.lastNameController,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: _fieldDecoration(
              label: 'Last Name',
              icon: Icons.person_outline_rounded,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey<String>(widget.email),
            initialValue: widget.email,
            readOnly: true,
            enableInteractiveSelection: false,
            decoration: _fieldDecoration(
              label: 'Email Address',
              icon: Icons.lock_outline_rounded,
              helper: 'Your sign-in email cannot be changed.',
            ),
          ),
          const SizedBox(height: 14),
          SpPrimaryButton(
            icon: Icons.save_rounded,
            label: _savingProfile ? 'Saving...' : 'Save Changes',
            busy: _savingProfile,
            onPressed: _saveProfile,
          ),
        ],
      ),
    );
  }

  Widget _securityCard() {
    return SpSectionCard(
      icon: Icons.shield_outlined,
      title: 'Security',
      subtitle: _passwordFormOpen
          ? 'Confirm your current password, then choose a new one.'
          : 'Change the password you use to sign in.',
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: _passwordFormOpen ? _passwordForm() : _changePasswordButton(),
      ),
    );
  }

  Widget _changePasswordButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _passwordFormOpen = true),
        icon: const Icon(Icons.password_rounded),
        label: const Text(
          'Change Password',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          foregroundColor: AppTheme.textDark,
          side: BorderSide(color: AppTheme.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
        ),
      ),
    );
  }

  Widget _passwordForm() {
    return Column(
      children: [
        TextField(
          controller: _currentPasswordController,
          obscureText: true,
          autofocus: true,
          decoration: _fieldDecoration(
            label: 'Current Password',
            icon: Icons.lock_outline_rounded,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _newPasswordController,
          obscureText: true,
          decoration: _fieldDecoration(
            label: 'New Password',
            icon: Icons.lock_reset_rounded,
            helper: 'At least 6 characters.',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _confirmPasswordController,
          obscureText: true,
          decoration: _fieldDecoration(
            label: 'Confirm New Password',
            icon: Icons.verified_user_outlined,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _changingPassword ? null : _changePassword,
            icon: _changingPassword
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.password_rounded),
            label: Text(
              _changingPassword ? 'Updating...' : 'Update Password',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.textDark,
              foregroundColor: AppTheme.onInk,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radius),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _changingPassword ? null : _closePasswordForm,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: AppTheme.textDark,
              side: BorderSide(color: AppTheme.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radius),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _signOutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: widget.onSignOut,
        icon: const Icon(Icons.logout_rounded),
        label: const Text(
          'Sign Out',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          foregroundColor: AppTheme.danger,
          side: BorderSide(color: AppTheme.dangerBorder),
          backgroundColor: AppTheme.dangerSoft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    IconData? icon,
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      filled: true,
      fillColor: AppTheme.surfaceAlt,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        borderSide: BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        borderSide: BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        borderSide: const BorderSide(color: AppTheme.accent, width: 1.4),
      ),
      labelStyle: TextStyle(
        color: AppTheme.textMuted,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      helperStyle: TextStyle(color: AppTheme.textMuted, fontSize: 11),
    );
  }
}

/// Light / dark / follow-the-phone picker.
class SpAppearanceCard extends StatelessWidget {
  const SpAppearanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeController controller = ThemeController.instance;
    return SpSectionCard(
      icon: Icons.palette_outlined,
      title: 'Appearance',
      subtitle: 'Choose a light or dark look, or match your phone.',
      child: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, _) => SpSegmentedControl<AppThemeMode>(
          options: const <(AppThemeMode, String)>[
            (AppThemeMode.light, 'Light'),
            (AppThemeMode.dark, 'Dark'),
            (AppThemeMode.system, 'System'),
          ],
          selected: controller.mode,
          onChanged: controller.setMode,
        ),
      ),
    );
  }
}
