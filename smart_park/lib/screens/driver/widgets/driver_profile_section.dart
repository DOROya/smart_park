import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

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

  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _surfaceSoft = Color(0xFFF8F9FC);
  static const Color _textStrong = Color(0xFF1E2330);
  static const Color _textSubtle = Color(0xFF737A88);
  static const Color _stroke = Color(0xFFE4E7EF);

  @override
  Widget build(BuildContext context) {
    final String fullName =
        '${profileFirstNameController.text.trim()} ${profileLastNameController.text.trim()}'
            .trim();
    final String displayName = fullName.isEmpty ? 'Driver Account' : fullName;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        const Text(
          'Profile',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: _textStrong,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Manage your personal details and account security.',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _textSubtle,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFFFFEAA8), Color(0xFFF7C846)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0x35FFFFFF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 30,
                  color: Color(0xFF313645),
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
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C2230),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profileEmailController.text.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF4C5362),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Personal Information',
          subtitle: 'Keep your details accurate for account verification.',
          child: Column(
            children: [
              TextField(
                controller: profileFirstNameController,
                decoration: _fieldDecoration(label: 'First Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: profileLastNameController,
                decoration: _fieldDecoration(label: 'Last Name'),
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
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: savingProfile ? null : onSaveProfile,
                  icon: savingProfile
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(savingProfile ? 'Saving Profile...' : 'Save Changes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: const Color(0xFF22252C),
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
        _SectionCard(
          title: 'Security',
          subtitle: 'Use a strong password with at least 8 characters.',
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
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F2430),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign Out'),
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
            ],
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
      fillColor: _surfaceSoft,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.accent, width: 1.4),
      ),
      labelStyle: const TextStyle(
        color: _textSubtle,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      helperStyle: const TextStyle(
        color: _textSubtle,
        fontSize: 11,
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DriverProfileSection._surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DriverProfileSection._stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DriverProfileSection._textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: DriverProfileSection._textSubtle,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
