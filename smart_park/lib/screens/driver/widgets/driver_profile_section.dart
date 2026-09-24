import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/smartpark_ui.dart';

class DriverProfileSection extends StatelessWidget {
  const DriverProfileSection({
    super.key,
    required this.profileFirstNameController,
    required this.profileLastNameController,
    required this.profileEmailController,
    required this.newPasswordController,
    required this.confirmPasswordController,
    required this.savingProfile,
    required this.updatingPassword,
    required this.onSaveProfile,
    required this.onChangePassword,
    required this.onSignOut,
  });

  final TextEditingController profileFirstNameController;
  final TextEditingController profileLastNameController;
  final TextEditingController profileEmailController;
  final TextEditingController newPasswordController;
  final TextEditingController confirmPasswordController;
  final bool savingProfile;
  final bool updatingPassword;
  final VoidCallback onSaveProfile;
  final VoidCallback onChangePassword;
  final VoidCallback onSignOut;

  String _initials(String name) {
    final List<String> parts = name
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final String fullName =
        '${profileFirstNameController.text.trim()} ${profileLastNameController.text.trim()}'
            .trim();
    final String displayName = fullName.isEmpty ? 'Driver' : fullName;
    final String email = profileEmailController.text.trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const SpPageHeader(
          title: 'Profile',
          subtitle: 'Your personal details and account security.',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFFFFEAA8), Color(0xFFF7C846)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0x40FFFFFF),
                child: Text(
                  _initials(displayName),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2532),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2532),
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF3D4658),
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
                      child: const Text(
                        'Driver',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3D4658),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SpSectionCard(
          icon: Icons.manage_accounts_rounded,
          title: 'Personal Information',
          subtitle: 'Keep your details accurate for account verification.',
          child: Column(
            children: [
              TextField(
                controller: profileFirstNameController,
                decoration: _fieldDecoration(
                  label: 'First Name',
                  icon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: profileLastNameController,
                decoration: _fieldDecoration(
                  label: 'Last Name',
                  icon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: profileEmailController,
                readOnly: true,
                decoration: _fieldDecoration(
                  label: 'Email Address',
                  icon: Icons.lock_outline_rounded,
                  helper: 'Email cannot be changed from this screen.',
                ),
              ),
              const SizedBox(height: 14),
              SpPrimaryButton(
                icon: Icons.save_rounded,
                label: savingProfile ? 'Saving Profile...' : 'Save Changes',
                busy: savingProfile,
                onPressed: onSaveProfile,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SpSectionCard(
          icon: Icons.shield_outlined,
          title: 'Security',
          subtitle: 'Use a password with at least 6 characters.',
          child: Column(
            children: [
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: _fieldDecoration(
                  label: 'New Password',
                  icon: Icons.lock_outline_rounded,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: _fieldDecoration(
                  label: 'Confirm Password',
                  icon: Icons.verified_user_outlined,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: updatingPassword ? null : onChangePassword,
                  icon: updatingPassword
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.password_rounded),
                  label: Text(
                    updatingPassword
                        ? 'Updating Password...'
                        : 'Update Password',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F2532),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text(
              'Sign Out',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: const Color(0xFFAF2E2E),
              side: const BorderSide(color: Color(0xFFF0C9C9)),
              backgroundColor: const Color(0xFFFFF6F6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
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
      fillColor: const Color(0xFFF8F9FC),
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE4E7EF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE4E7EF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.accent, width: 1.4),
      ),
      labelStyle: const TextStyle(
        color: Color(0xFF737A88),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      helperStyle: const TextStyle(color: Color(0xFF737A88), fontSize: 11),
    );
  }
}
