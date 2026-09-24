import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/app_version_guard.dart';
import 'screens/role_based_home_page.dart';
import 'screens/verify_email_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme/app_theme.dart';
import 'utils/staff_credentials.dart';

class SmartParkApp extends StatelessWidget {
  const SmartParkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Park',
      theme: AppTheme.lightTheme,
      home: const InternetGate(),
    );
  }
}

class InternetGate extends StatefulWidget {
  const InternetGate({super.key});

  @override
  State<InternetGate> createState() => _InternetGateState();
}

class _InternetGateState extends State<InternetGate> {
  late Future<bool> _internetCheckFuture;

  @override
  void initState() {
    super.initState();
    _internetCheckFuture = _hasInternetConnection();
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final List<InternetAddress> result = await InternetAddress.lookup(
        'example.com',
      );
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  void _retry() {
    setState(() {
      _internetCheckFuture = _hasInternetConnection();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _internetCheckFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final bool hasInternet = snapshot.data ?? false;
        if (!hasInternet) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'SmartPark requires an internet connection to function.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E2026),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Please connect to the internet and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF8E929C),
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _retry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return const VersionGate();
      },
    );
  }
}

class VersionGate extends StatefulWidget {
  const VersionGate({super.key});

  @override
  State<VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends State<VersionGate> {
  late Future<AppVersionCheckResult> _versionCheckFuture;
  bool _continueDespiteOutdated = false;

  @override
  void initState() {
    super.initState();
    _versionCheckFuture = AppVersionGuard.check();
  }

  void _recheck() {
    setState(() {
      _continueDespiteOutdated = false;
      _versionCheckFuture = AppVersionGuard.check();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) {
      return const AuthGate();
    }

    return FutureBuilder<AppVersionCheckResult>(
      future: _versionCheckFuture,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<AppVersionCheckResult> snapshot,
          ) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Unable to verify installed app version.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E2026),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (_) => const AuthGate(),
                              ),
                            );
                          },
                          child: const Text('Continue Anyway'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _recheck,
                          child: const Text('Retry Check'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final AppVersionCheckResult result = snapshot.data!;
            if (!result.enabled ||
                !result.isOutdated ||
                _continueDespiteOutdated) {
              return const AuthGate();
            }

            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Outdated App Build Detected',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E2026),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        result.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF8E929C),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Installed: ${result.currentVersion}\nExpected at least: ${result.requiredVersion}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _recheck,
                        child: const Text('Recheck Version'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _continueDespiteOutdated = true;
                          });
                        },
                        child: const Text('Continue Anyway'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<User?> _initialUserFuture;

  @override
  void initState() {
    super.initState();
    _initialUserFuture = FirebaseAuth.instance.authStateChanges().first;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: _initialUserFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final User? user = snapshot.data;
        // Staff sign in with a username, not a real inbox, so their
        // synthetic-domain account can never complete email verification -
        // skip that requirement for them specifically.
        final bool isStaffAccount = isStaffAuthEmail(user?.email);
        if (user != null && (user.emailVerified || isStaffAccount)) {
          return const RoleBasedHomePage();
        }

        if (user != null && !user.emailVerified && !isStaffAccount) {
          return const VerifyEmailScreen();
        }

        return const WelcomeScreen();
      },
    );
  }
}

class AppTypography {
  static TextTheme buildTextTheme() {
    return GoogleFonts.poppinsTextTheme();
  }
}
