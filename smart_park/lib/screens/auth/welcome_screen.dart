import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/auth_widgets.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _openLogin(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
    );
  }

  void _openSignUp(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthBadge(
            icon: Icons.local_parking_rounded,
            label: 'Smart parking starts here',
          ),
          const SizedBox(height: 14),
          const AuthHeader(
            first: 'Welcome ',
            accent: 'to SmartPark.',
            subtitle: 'Find, pay for, and manage parking in one app.',
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppTheme.accentLight, AppTheme.accentWarm],
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WelcomePoint(
                  icon: Icons.map_rounded,
                  title: 'Drivers',
                  text: 'Find nearby parking and get a QR ticket in seconds.',
                ),
                SizedBox(height: 14),
                _WelcomePoint(
                  icon: Icons.storefront_rounded,
                  title: 'Parking owners',
                  text: 'Run your facility and track earnings in one place.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryAuthButton(
            text: 'Login',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => _openLogin(context),
          ),
          const SizedBox(height: 12),
          SecondaryAuthButton(
            text: 'Create an Account',
            onPressed: () => _openSignUp(context),
          ),
        ],
      ),
    );
  }
}

class _WelcomePoint extends StatelessWidget {
  const _WelcomePoint({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0x55FFFFFF),
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Icon(icon, size: 20, color: AppTheme.textDark),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
