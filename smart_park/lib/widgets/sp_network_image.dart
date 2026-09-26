import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A network photo that is cached on the device, shows a soft placeholder
/// while loading, and falls back to [errorIcon] if it can't be fetched.
class SpNetworkImage extends StatelessWidget {
  const SpNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorIcon = Icons.broken_image_rounded,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final IconData errorIcon;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, _) => _Placeholder(width: width, height: height),
      errorWidget: (_, _, _) =>
          _Placeholder(width: width, height: height, icon: errorIcon),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.width, this.height, this.icon});

  final double? width;
  final double? height;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: AppTheme.surfaceAlt,
      alignment: Alignment.center,
      child: icon == null
          ? null
          : Icon(icon, color: AppTheme.textMuted, size: 28),
    );
  }
}
