import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Gently pulses its child's opacity; wraps skeleton shapes so a loading
/// list reads as "content is coming" instead of an empty spinner.
class SpPulse extends StatefulWidget {
  const SpPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SpPulse> createState() => _SpPulseState();
}

class _SpPulseState extends State<SpPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.45,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// A grey placeholder block.
class SpSkeletonBox extends StatelessWidget {
  const SpSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = AppTheme.radiusSmall,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.border,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Placeholder rows shaped like the app's list cards (icon, title, subtitle).
class SpSkeletonList extends StatelessWidget {
  const SpSkeletonList({super.key, this.count = 3, this.padding});

  final int count;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: SpPulse(
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < count; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    border: Border.all(color: AppTheme.border),
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  ),
                  child: Row(
                    children: [
                      const SpSkeletonBox(
                        width: 40,
                        height: 40,
                        radius: AppTheme.radius,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FractionallySizedBox(
                              widthFactor: i.isEven ? 0.7 : 0.55,
                              child: const SpSkeletonBox(height: 12),
                            ),
                            const SizedBox(height: 8),
                            FractionallySizedBox(
                              widthFactor: i.isEven ? 0.45 : 0.6,
                              child: const SpSkeletonBox(height: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen loader with the SmartPark mark, used while the app works
/// out who is signed in, instead of a bare spinner on a blank page.
class SpLoadingScreen extends StatelessWidget {
  const SpLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Semantics(
          label: 'Loading SmartPark',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SpPulse(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
                  ),
                  child: Icon(
                    Icons.local_parking_rounded,
                    size: 38,
                    color: AppTheme.onAccent,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'SmartPark',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
