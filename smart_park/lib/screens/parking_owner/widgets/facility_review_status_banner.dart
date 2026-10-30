import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../services/facility_status.dart' show joinReasons;
import '../../../theme/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../widgets/smartpark_ui.dart';

/// Shows the admin review state of a facility (`establishment_details.status`)
/// to its owner, including the admin's rejection reason when present.
class FacilityReviewStatusBanner extends StatelessWidget {
  const FacilityReviewStatusBanner({
    super.key,
    required this.status,
    this.rejectionReason,
    this.restrictionReasons = const <String>[],
    this.hint,
    this.appealedAt,
    this.onAskForReview,
  });

  final String? status;
  final String? rejectionReason;

  /// The predefined reasons an admin picked when suspending or deactivating.
  final List<String> restrictionReasons;

  /// Optional extra line, e.g. what saving the form will do.
  final String? hint;

  /// When the owner asked the admin to review a suspension or
  /// deactivation; null when no request is waiting.
  final DateTime? appealedAt;

  /// Offers "Ask for review" on a suspended or deactivated facility.
  final VoidCallback? onAskForReview;

  /// Statuses whose admin note (stored in `rejectionReason`) the owner sees.
  static bool _hasAdminNote(String status) =>
      status == 'rejected' || status == 'suspended' || status == 'deactivated';

  @override
  Widget build(BuildContext context) {
    final String normalized = (status ?? 'pending').toLowerCase();
    final String reason = rejectionReason?.trim() ?? '';
    // "Other" alone says nothing; the admin's note explains it.
    final String picked =
        normalized == 'suspended' || normalized == 'deactivated'
        ? joinReasons(restrictionReasons.where((String r) => r != 'Other'))
        : '';

    final (
      Color color,
      IconData icon,
      String title,
      String message,
    ) = switch (normalized) {
      'approved' => (
        AppTheme.success,
        Icons.verified_rounded,
        'Approved',
        'Your facility is verified and visible to drivers.',
      ),
      'rejected' => (
        AppTheme.danger,
        Icons.cancel_rounded,
        'Rejected',
        'Your facility was not approved. Update the details or documents '
            'and save to resubmit it for review.',
      ),
      'suspended' => (
        AppTheme.warning,
        Icons.pause_circle_rounded,
        'Suspended',
        'An admin has suspended your facility. It is hidden from drivers and '
            'cannot sell tickets until an admin reinstates it.',
      ),
      'deactivated' => (
        AppTheme.textMuted,
        Icons.block_rounded,
        'Deactivated',
        'An admin has deactivated your facility. It is no longer listed on '
            'SmartPark. Contact the SmartPark admin to reactivate it.',
      ),
      _ => (
        AppTheme.warning,
        Icons.hourglass_top_rounded,
        'Pending Review',
        'An admin is verifying your details and business documents. '
            'Your facility is hidden from drivers until approved.',
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (picked.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Reason: $picked',
                      style: TextStyle(
                        color: AppTheme.textDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if (_hasAdminNote(normalized) && reason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Admin note: $reason',
                    style: TextStyle(
                      color: AppTheme.textDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if ((normalized == 'suspended' ||
                        normalized == 'deactivated') &&
                    onAskForReview != null) ...[
                  const SizedBox(height: 10),
                  if (appealedAt != null)
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_send_rounded,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Review requested ${spFormatDate(appealedAt!)}. '
                            'Waiting for the SmartPark admin.',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: onAskForReview,
                      icon: const Icon(Icons.forum_outlined, size: 16),
                      label: const Text('Ask for review'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: color,
                        side: BorderSide(color: color.withValues(alpha: 0.5)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
                if (hint != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    hint!,
                    style: TextStyle(
                      color: AppTheme.textDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the owner of a suspended or deactivated facility ask the admin to
/// review it, with a short explanation (e.g. "permit renewed"). Stored on
/// `establishment_details` as `appealMessage` / `appealedAt`; the admin's
/// next status change clears it.
Future<void> showFacilityAppealDialog(
  BuildContext context, {
  required String establishmentId,
}) async {
  final TextEditingController message = TextEditingController();
  final bool? sent = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      bool sending = false;
      String? error;
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => AlertDialog(
          title: const Text('Ask for review'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tell the SmartPark admin what changed, for example a '
                  'renewed permit or a fixed issue. They will review your '
                  'facility and reinstate it if everything checks out.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: message,
                  enabled: !sending,
                  maxLines: 4,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Message to the admin',
                    filled: true,
                    fillColor: AppTheme.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending
                  ? null
                  : () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      if (message.text.trim().isEmpty) {
                        setState(() => error = 'Write a short message first.');
                        return;
                      }
                      setState(() {
                        sending = true;
                        error = null;
                      });
                      try {
                        await FirebaseFirestore.instance
                            .collection('establishment_details')
                            .doc(establishmentId)
                            .update(<String, dynamic>{
                              'appealMessage': message.text.trim(),
                              'appealedAt': FieldValue.serverTimestamp(),
                            });
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } catch (e) {
                        setState(() {
                          sending = false;
                          error = friendlyError(
                            e,
                            fallback: 'Could not send your request.',
                          );
                        });
                      }
                    },
              child: Text(sending ? 'Sending...' : 'Send request'),
            ),
          ],
        ),
      );
    },
  );
  message.dispose();
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Review request sent to the admin.')),
    );
  }
}
