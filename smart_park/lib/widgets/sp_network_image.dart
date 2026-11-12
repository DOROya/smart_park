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
    this.placeholderColor,
    this.decodeWidth,
    this.previewDecodeWidth,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final IconData errorIcon;

  /// Background while loading; defaults to the theme's soft surface.
  final Color? placeholderColor;

  /// Logical width the photo is shown at. When set, the photo is decoded
  /// at that size (times the screen density) instead of at full camera
  /// resolution, which saves memory and decode time on list cards.
  final double? decodeWidth;

  /// The [decodeWidth] a thumbnail of the same photo was shown at. While
  /// the full photo decodes, that thumbnail (already in memory) is shown
  /// stretched, with a spinner, instead of an empty box.
  final double? previewDecodeWidth;

  @override
  Widget build(BuildContext context) {
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int? memCacheWidth = decodeWidth == null
        ? null
        : (decodeWidth! * dpr).round();
    return CachedNetworkImage(
      imageUrl: url,
      memCacheWidth: memCacheWidth,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, _) => previewDecodeWidth == null
          ? _Placeholder(width: width, height: height, color: placeholderColor)
          : Stack(
              alignment: Alignment.center,
              children: [
                CachedNetworkImage(
                  imageUrl: url,
                  memCacheWidth: (previewDecodeWidth! * dpr).round(),
                  width: width,
                  height: height,
                  fit: fit,
                  fadeInDuration: Duration.zero,
                  placeholder: (_, _) => _Placeholder(
                    width: width,
                    height: height,
                    color: placeholderColor,
                  ),
                ),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
      errorWidget: (_, _, _) => _Placeholder(
        width: width,
        height: height,
        icon: errorIcon,
        color: placeholderColor,
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.width, this.height, this.icon, this.color});

  final double? width;
  final double? height;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: color ?? AppTheme.surfaceAlt,
      alignment: Alignment.center,
      child: icon == null
          ? null
          : Icon(icon, color: AppTheme.textMuted, size: 28),
    );
  }
}
