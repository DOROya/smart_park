import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/smartpark_ui.dart';
import 'terms_screen.dart';

class SelectRoleScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;
  final String password;

  const SelectRoleScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.password,
  });

  @override
  State<SelectRoleScreen> createState() => _SelectRoleScreenState();
}

class _SelectRoleScreenState extends State<SelectRoleScreen> {
  static const String _driverRole = 'Driver';
  static const String _parkingOwnerRole = 'Parking Owner';

  String? _selectedRole;

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _goToTermsScreen() {
    if (_selectedRole == null) {
      _showSnackBar('Please select a role before continuing.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TermsScreen(
          role: _selectedRole!,
          firstName: widget.firstName,
          lastName: widget.lastName,
          email: widget.email,
          password: widget.password,
        ),
      ),
    );
  }

  Widget _buildRoleCard(String role, IconData icon, List<String> descriptions) {
    final bool isSelected = _selectedRole == role;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isSelected ? AppTheme.accentSoft : AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          side: BorderSide(
            color: isSelected ? AppTheme.accent : spCardBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedRole = role;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.accent
                            : AppTheme.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                      ),
                      child: Icon(
                        icon,
                        color: isSelected
                            ? AppTheme.onAccent
                            : AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        role,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        key: ValueKey<bool>(isSelected),
                        color: isSelected
                            ? AppTheme.accentText
                            : AppTheme.borderStrong,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final String desc in descriptions)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: spEntryColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            desc,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
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

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthBadge(
            icon: Icons.how_to_reg_rounded,
            label: 'Step 2 of 3 · Your role',
          ),
          const SizedBox(height: 14),
          const AuthHeader(
            first: 'Select ',
            accent: 'Role.',
            subtitle: 'How will you use SmartPark?',
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warningSoft,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: spInsideColor,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Choose carefully. Your role cannot be changed later.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accentText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildRoleCard(_driverRole, Icons.directions_car_rounded, const [
            'Discover nearby parking establishments on the map',
            'Pay for parking directly within the app',
            'Receive a digital QR ticket upon confirmed payment',
            'Monitor active tickets and view parking history',
          ]),
          _buildRoleCard(_parkingOwnerRole, Icons.storefront_rounded, const [
            'Register and manage your parking establishment',
            'Configure rates, policies, and staff accounts',
            'Track vehicle activity and transaction records',
            'Monitor commission payables per transaction',
          ]),
          const SizedBox(height: 12),
          PrimaryAuthButton(
            text: 'Next',
            icon: Icons.arrow_forward_rounded,
            enabled: _selectedRole != null,
            onPressed: _goToTermsScreen,
          ),
        ],
      ),
    );
  }
}
