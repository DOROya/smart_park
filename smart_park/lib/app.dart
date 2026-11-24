import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:async';

import 'screens/auth/role_based_home_page.dart';
import 'screens/driver/saved_ticket_page.dart';
import 'services/app_shortcuts.dart';
import 'services/last_ticket_store.dart';
import 'screens/auth/verify_email_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'services/app_version_guard.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'utils/friendly_error.dart';
import 'utils/staff_credentials.dart';
import 'widgets/sp_loading.dart';

class SmartParkApp extends StatefulWidget {
  const SmartParkApp({super.key});

  @override
  State<SmartParkApp> createState() => _SmartParkAppState();
}

class _SmartParkAppState extends State<SmartParkApp> {
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
    AppShortcuts.init();
    // Signed out: no shortcut, and no ticket left saved on the phone.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user == null) {
        unawaited(AppShortcuts.clear());
        unawaited(LastTicketStore.clear());
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    ThemeController.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  /// Screens read colours from AppTheme directly rather than through
  /// Theme.of, so a palette switch has to rebuild every element (keeping
  /// their state) instead of only Theme dependents.
  void _onThemeChanged() {
    setState(() {});
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SmartPark',
      theme: AppTheme.theme,
      // The phone's font size still applies, up to 1.3x: beyond that the
      // fixed-size cards, chips and tab labels run out of room.
      builder: (BuildContext context, Widget? child) =>
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: kMaxTextScale,
            child: child!,
          ),
      home: const InternetGate(),
    );
  }
}

/// Largest text scale the app follows from the phone's font-size setting.
const double kMaxTextScale = 1.3;

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
          return const SpLoadingScreen();
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
                    Text(
                      'SmartPark requires an internet connection to function.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Please connect to the internet and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _retry,
                      child: const Text('Retry'),
                    ),
                    // The ticket QR needs no signal: the copy saved on
                    // this phone, for a basement with no data.
                    const _SavedTicketButton(),
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
              return const SpLoadingScreen();
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Unable to verify installed app version.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          friendlyError(
                            snapshot.error ?? 'unknown',
                            fallback: 'Check your connection and try again.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textMuted),
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
                      Text(
                        'Outdated App Build Detected',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        result.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Installed: ${result.currentVersion}\nExpected at least: ${result.requiredVersion}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textDark,
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
          return const SpLoadingScreen();
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

/// On the no-internet screen: opens the driver's last active ticket, saved
/// on this phone. Opens it by itself when the app was started from "Show
/// my ticket".
class _SavedTicketButton extends StatefulWidget {
  const _SavedTicketButton();

  @override
  State<_SavedTicketButton> createState() => _SavedTicketButtonState();
}

class _SavedTicketButtonState extends State<_SavedTicketButton> {
  SavedTicket? _saved;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final SavedTicket? saved = await LastTicketStore.load();
    if (!mounted || saved == null) return;
    setState(() => _saved = saved);
    if (pendingShortcut.value == kShowTicketShortcut) {
      pendingShortcut.value = null;
      _open();
    }
  }

  void _open() {
    final SavedTicket? saved = _saved;
    if (saved == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SavedTicketPage(ticket: saved, offline: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_saved == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton.icon(
        onPressed: _open,
        icon: const Icon(Icons.qr_code_2_rounded),
        label: const Text('Show my saved ticket'),
      ),
    );
  }
}
