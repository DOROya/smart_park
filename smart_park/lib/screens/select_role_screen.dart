import 'package:flutter/material.dart';

import '../widgets/auth_widgets.dart';
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

  Widget _buildRoleCard(String role, List<String> descriptions) {
    final bool isSelected = _selectedRole == role;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() {
            _selectedRole = role;
          });
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFF3E0) : Colors.white,
            border: Border.all(
              color: isSelected ? Colors.orange : Colors.grey.shade300,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                role,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.orange : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              ...descriptions.map(
                (desc) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    "• $desc",
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),
              ),
            ],
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
          const SizedBox(height: 18),
          const AuthHeader(
            first: 'Select ',
            accent: 'Role.',
            subtitle:
                '⚠️ Please select carefully. Your role cannot be changed later.',
          ),
          const SizedBox(height: 26),
          _buildRoleCard(_driverRole, [
            "Discover nearby parking establishments on the map",
            "Pay for parking directly within the app",
            "Receive a digital QR ticket upon confirmed payment",
            "Monitor active tickets and view parking history",
          ]),
          _buildRoleCard(_parkingOwnerRole, [
            "Register and manage your parking establishment",
            "Configure rates, policies, and staff accounts",
            "Track vehicle activity and transaction records",
            "Monitor commission payables per transaction",
          ]),
          const SizedBox(height: 28),
          PrimaryAuthButton(text: 'Next', onPressed: _goToTermsScreen),
        ],
      ),
    );
  }
}
