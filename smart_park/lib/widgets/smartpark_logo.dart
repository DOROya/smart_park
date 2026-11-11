import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// SmartPark brand mark: a dark map pin with a "P" cut out of its head on a
/// yellow rounded tile. Matches the Android launcher icon.
class SmartParkLogo extends StatelessWidget {
  const SmartParkLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SmartParkLogoPainter()),
    );
  }
}

class _SmartParkLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(w * 0.24)),
      Paint()..color = AppTheme.accent,
    );

    // Pin geometry, in the same proportions as the launcher icon.
    final double u = w * 0.78;
    final double top = (w - u) / 2;
    final double cx = w / 2;
    final double r = u * 0.30;
    final double cy = top + u * 0.38;
    final double tipY = top + u * 0.90;

    final double theta = math.acos(r / (tipY - cy));
    final double start = math.pi / 2 - theta;
    final Path pin = Path()
      ..moveTo(cx, tipY)
      ..lineTo(cx + r * math.cos(start), cy + r * math.sin(start))
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        start,
        -(2 * math.pi - 2 * theta),
        false,
      )
      ..close();
    canvas.drawPath(pin, Paint()..color = AppTheme.onAccent);

    final TextPainter p = TextPainter(
      text: TextSpan(
        text: 'P',
        style: TextStyle(
          color: AppTheme.accent,
          fontSize: r * 1.3,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(
      canvas,
      Offset(cx - p.width / 2 + r * 0.04, cy - p.height / 2 + r * 0.04),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
