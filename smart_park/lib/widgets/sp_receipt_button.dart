import 'package:flutter/material.dart';

import '../services/error_reporter.dart';
import '../services/parking_receipt.dart' show ReceiptFormat;
import '../theme/app_theme.dart';

/// "Receipt" button: asks PDF or image (PNG), then builds and shares the
/// receipt, with a spinner while it works. [onShare] also gets where the
/// button is, for the iPad share popover.
class SpReceiptButton extends StatefulWidget {
  const SpReceiptButton({
    super.key,
    required this.onShare,
    this.outlined = false,
    this.label = 'Receipt',
  });

  final Future<void> Function(ReceiptFormat format, Rect? origin) onShare;

  /// A full outlined button (payment screen) instead of a compact text
  /// button (ticket cards).
  final bool outlined;
  final String label;

  @override
  State<SpReceiptButton> createState() => _SpReceiptButtonState();
}

class _SpReceiptButtonState extends State<SpReceiptButton> {
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    final ReceiptFormat? format = await _pickFormat();
    if (format == null || !mounted) return;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final Rect? origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      await widget.onShare(format, origin);
    } catch (error, stack) {
      reportError(error, stack, reason: 'parking receipt');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not create the receipt. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ReceiptFormat?> _pickFormat() => showModalBottomSheet<ReceiptFormat>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    backgroundColor: AppTheme.surface,
    builder: (BuildContext context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Save receipt as',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF'),
            subtitle: const Text('Best for printing and email'),
            onTap: () => Navigator.of(context).pop(ReceiptFormat.pdf),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Image (PNG)'),
            subtitle: const Text('Save to your gallery or send in a chat'),
            onTap: () => Navigator.of(context).pop(ReceiptFormat.png),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final Widget icon = _busy
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.textMuted,
            ),
          )
        : const Icon(Icons.receipt_long_rounded, size: 16);
    final Widget label = Text(
      widget.label,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
    if (widget.outlined) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : _share,
          icon: icon,
          label: label,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textDark,
            side: BorderSide(color: AppTheme.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: 'Save or share a receipt (PDF)',
      child: TextButton.icon(
        onPressed: _busy ? null : _share,
        icon: icon,
        label: label,
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.accentText,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
