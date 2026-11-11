import 'package:flutter/material.dart';

import '../services/error_reporter.dart';
import '../services/local_save.dart'
    show StorageAccessDenied, kDownloadsFolderLabel;
import '../services/parking_receipt.dart' show ReceiptFormat;
import '../theme/app_theme.dart';
import 'sp_export_sheet.dart';

/// "Receipt" button: asks whether to save the receipt on the phone (image
/// to the gallery, PDF to files) or share it, then builds it, with a
/// spinner while it works.
class SpReceiptButton extends StatefulWidget {
  const SpReceiptButton({
    super.key,
    required this.onExport,
    this.outlined = false,
    this.label = 'Receipt',
  });

  /// Builds the receipt and saves ([save]) or shares it. [origin] is where
  /// the button is, for the iPad share popover. Returns false if nothing
  /// was saved on the device.
  final Future<bool> Function(ReceiptFormat format, bool save, Rect? origin)
  onExport;

  /// A full outlined button (payment screen) instead of a compact text
  /// button (ticket cards).
  final bool outlined;
  final String label;

  @override
  State<SpReceiptButton> createState() => _SpReceiptButtonState();
}

typedef _Choice = ({ReceiptFormat format, bool save});

class _SpReceiptButtonState extends State<SpReceiptButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    final _Choice? choice = await showSpExportSheet<_Choice>(
      context,
      title: 'Receipt',
      sections: const <SpExportSection<_Choice>>[
        SpExportSection<_Choice>('Save to phone', <SpExportOption<_Choice>>[
          SpExportOption<_Choice>(
            icon: Icons.photo_library_outlined,
            title: 'Image to Gallery',
            subtitle: 'Saved as a PNG in the SmartPark album',
            value: (format: ReceiptFormat.png, save: true),
          ),
          SpExportOption<_Choice>(
            icon: Icons.download_rounded,
            title: 'PDF to Files',
            subtitle: 'Saved in $kDownloadsFolderLabel',
            value: (format: ReceiptFormat.pdf, save: true),
          ),
        ]),
        SpExportSection<_Choice>('Share', <SpExportOption<_Choice>>[
          SpExportOption<_Choice>(
            icon: Icons.image_outlined,
            title: 'Share as image',
            subtitle: 'Send in a chat',
            value: (format: ReceiptFormat.png, save: false),
          ),
          SpExportOption<_Choice>(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Share as PDF',
            subtitle: 'Best for printing and email',
            value: (format: ReceiptFormat.pdf, save: false),
          ),
        ]),
      ],
    );
    if (choice == null || !mounted) return;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final Rect? origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      final bool done = await widget.onExport(
        choice.format,
        choice.save,
        origin,
      );
      if (done && choice.save && mounted) {
        showSpSaveResult(
          context,
          saved: choice.format == ReceiptFormat.png
              ? 'Receipt saved to your gallery.'
              : 'Receipt saved to $kDownloadsFolderLabel.',
        );
      }
    } catch (error, stack) {
      if (error is! StorageAccessDenied) {
        reportError(error, stack, reason: 'parking receipt');
      }
      if (mounted) {
        showSpSaveResult(
          context,
          saved: '',
          error: error,
          failed: 'Could not create the receipt. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
          onPressed: _busy ? null : _run,
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
      message: 'Save or share the receipt',
      child: TextButton.icon(
        onPressed: _busy ? null : _run,
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
