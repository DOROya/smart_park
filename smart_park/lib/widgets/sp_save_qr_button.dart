import 'package:flutter/material.dart';

import '../services/error_reporter.dart';
import '../services/local_save.dart' show StorageAccessDenied;
import '../services/parking_receipt.dart' show ParkingReceipt;
import '../services/qr_ticket_image.dart';
import '../theme/app_theme.dart';
import 'sp_export_sheet.dart' show showSpSaveResult;

/// Saves the ticket's QR (with the facility, plate and package) as an
/// image in the gallery, so the driver can show it at the gate without
/// opening the app.
class SpSaveQrButton extends StatefulWidget {
  const SpSaveQrButton({
    super.key,
    required this.ticket,
    required this.qrData,
    this.prominent = false,
  });

  final ParkingReceipt ticket;
  final String qrData;

  /// A full-width filled button (payment screen) instead of a compact text
  /// button (ticket cards).
  final bool prominent;

  @override
  State<SpSaveQrButton> createState() => _SpSaveQrButtonState();
}

class _SpSaveQrButtonState extends State<SpSaveQrButton> {
  bool _busy = false;

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await saveQrTicketToGallery(widget.ticket, widget.qrData);
      if (mounted) {
        showSpSaveResult(context, saved: 'QR ticket saved to your gallery.');
      }
    } catch (error, stack) {
      if (error is! StorageAccessDenied) {
        reportError(error, stack, reason: 'save QR ticket');
      }
      if (mounted) {
        showSpSaveResult(
          context,
          saved: '',
          error: error,
          failed: 'Could not save the QR ticket. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget icon(Color color) => _busy
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        : const Icon(Icons.qr_code_2_rounded, size: 18);
    if (widget.prominent) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: icon(AppTheme.onAccent),
          label: const Text(
            'Save QR to Gallery',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: AppTheme.onAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: 'Save the QR ticket as an image in your gallery',
      child: TextButton.icon(
        onPressed: _busy ? null : _save,
        icon: icon(AppTheme.textMuted),
        label: const Text(
          'Save QR',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.accentText,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
