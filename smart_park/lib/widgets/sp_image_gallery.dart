import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sp_network_image.dart';

/// Opens [urls] full screen at [initialIndex], with back and next buttons
/// (and swipes, and the arrow keys) to move between them without closing.
Future<void> showSpImageGallery(
  BuildContext context,
  List<String> urls, {
  int initialIndex = 0,
  double? thumbnailWidth,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => SpImageGallery(
      urls: urls,
      initialIndex: initialIndex,
      thumbnailWidth: thumbnailWidth,
    ),
  );
}

class SpImageGallery extends StatefulWidget {
  const SpImageGallery({
    super.key,
    required this.urls,
    this.initialIndex = 0,
    this.thumbnailWidth,
  });

  final List<String> urls;
  final int initialIndex;

  /// The decode width the opening thumbnails used, so they can stand in
  /// while each full photo loads.
  final double? thumbnailWidth;

  @override
  State<SpImageGallery> createState() => _SpImageGalleryState();
}

class _SpImageGalleryState extends State<SpImageGallery> {
  late final PageController _pageController;
  late int _index;

  /// While a photo is zoomed in, swiping pans it instead of changing photos.
  bool _zoomed = false;

  int get _count => widget.urls.length;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _count - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= _count) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _navButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 28,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.black26,
        disabledForegroundColor: Colors.white30,
      ),
      icon: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasMany = _count > 1;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _goTo(_index - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _goTo(_index + 1),
      },
      child: Focus(
        autofocus: true,
        child: Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: _count,
                onPageChanged: (int i) => setState(() {
                  _index = i;
                  _zoomed = false;
                }),
                itemBuilder: (BuildContext context, int i) {
                  return _ZoomablePhoto(
                    url: widget.urls[i],
                    thumbnailWidth: widget.thumbnailWidth,
                    onZoomChanged: (bool zoomed) {
                      if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                    },
                  );
                },
              ),
              if (hasMany) ...[
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _navButton(
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Back',
                      onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _navButton(
                      icon: Icons.chevron_right_rounded,
                      tooltip: 'Next',
                      onPressed: _index < _count - 1
                          ? () => _goTo(_index + 1)
                          : null,
                    ),
                  ),
                ),
              ],
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      if (hasMany)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${_index + 1} / $_count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const Spacer(),
                      _navButton(
                        icon: Icons.close_rounded,
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    required this.url,
    required this.onZoomChanged,
    this.thumbnailWidth,
  });

  final String url;
  final double? thumbnailWidth;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final TransformationController _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _transform,
      maxScale: 5,
      onInteractionEnd: (_) =>
          widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01),
      // Owners' photos can be 6-7 MB camera originals; decoding them at
      // twice the screen width (room to zoom) instead of full size is what
      // makes them appear in a moment rather than several seconds. Both the
      // thumbnail preview and the full photo fill the screen, so the swap
      // between them doesn't jump in size.
      child: SpNetworkImage(
        widget.url,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        placeholderColor: Colors.black,
        decodeWidth: MediaQuery.sizeOf(context).shortestSide * 2,
        previewDecodeWidth: widget.thumbnailWidth,
      ),
    );
  }
}
