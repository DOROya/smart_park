import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../content/driver_help_content.dart';
import '../../theme/app_theme.dart';

/// Whether this phone has shown a driver the first-run guide.
class DriverGuide {
  const DriverGuide._();

  /// Bump the suffix to show a changed guide to everyone once more.
  static const String seenKey = 'driver_guide_seen_v1';

  static Future<bool> seen() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(seenKey) ?? false;
    } catch (_) {
      // Unreadable storage: don't keep showing the guide.
      return true;
    }
  }

  static Future<void> markSeen() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(seenKey, true);
    } catch (_) {
      // Shown again next time; harmless.
    }
  }

  /// The guide on screen now, so a second caller waits for it instead of
  /// opening another (on first sign-in the driver home can be built twice).
  static Future<void>? _showing;

  /// Shows the guide once per phone, the first time a driver signs in.
  /// Returns when it has been closed (at once if it was seen before).
  static Future<void> showIfFirstRun(BuildContext context) {
    return _showing ??= _showOnce(context).whenComplete(() => _showing = null);
  }

  static Future<void> _showOnce(BuildContext context) async {
    if (await seen() || !context.mounted) return;
    // Marked first: closing the app mid-guide doesn't bring it back.
    await markSeen();
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const DriverGuidePage(),
      ),
    );
  }
}

/// "How SmartPark works": four swipeable pages, from finding parking to
/// paying at the gate. Shown on first sign-in and from Help & FAQ.
class DriverGuidePage extends StatefulWidget {
  const DriverGuidePage({super.key});

  @override
  State<DriverGuidePage> createState() => _DriverGuidePageState();
}

class _DriverGuidePageState extends State<DriverGuidePage> {
  final PageController _pages = PageController();
  int _index = 0;

  bool get _last => _index == kDriverGuideSteps.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_last) {
      Navigator.of(context).pop();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    _last ? 'Close' : 'Skip',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: kDriverGuideSteps.length,
                onPageChanged: (int i) => setState(() => _index = i),
                itemBuilder: (BuildContext context, int i) =>
                    _GuideStepView(step: kDriverGuideSteps[i], number: i + 1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: <Widget>[
                  Semantics(
                    label: 'Step ${_index + 1} of ${kDriverGuideSteps.length}',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        for (int i = 0; i < kDriverGuideSteps.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _index ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _index
                                  ? AppTheme.accent
                                  : AppTheme.borderStrong,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: AppTheme.onAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                        ),
                      ),
                      child: Text(
                        _last ? 'Start parking' : 'Next',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideStepView extends StatelessWidget {
  const _GuideStepView({required this.step, required this.number});

  final DriverGuideStep step;
  final int number;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: AppTheme.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(step.icon, size: 56, color: AppTheme.textDark),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'STEP $number',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              color: AppTheme.accentText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.title,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.body,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          for (final String point in step.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: AppTheme.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      point,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AppTheme.textDark,
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
}
