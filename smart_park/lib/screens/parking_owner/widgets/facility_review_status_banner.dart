import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

/// Shows the admin review state of a facility (`establishment_details.status`)
/// to its owner, including the admin's rejection reason when present.
class FacilityReviewStatusBanner extends StatelessWidget {
  const FacilityReviewStatusBanner({
    super.key,
    required this.status,
    this.rejectionReason,
    this.hint,
  });

  final String? status;
  final String? rejectionReason;

  /// Optional extra line, e.g. what saving the form will do.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final String normalized = (status ?? 'pending').toLowerCase();
    final String reason = rejectionReason?.trim() ?? '';

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
                if (normalized == 'rejected' && reason.isNotEmpty) ...[
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
