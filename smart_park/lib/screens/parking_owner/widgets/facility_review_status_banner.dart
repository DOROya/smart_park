import 'package:flutter/material.dart';

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
        const Color(0xFF059669),
        Icons.verified_rounded,
        'Approved',
        'Your facility is verified and visible to drivers.',
      ),
      'rejected' => (
        const Color(0xFFDC2626),
        Icons.cancel_rounded,
        'Rejected',
        'Your facility was not approved. Update the details or documents '
            'and save to resubmit it for review.',
      ),
      _ => (
        const Color(0xFFD97706),
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
        borderRadius: BorderRadius.circular(12),
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
                  style: const TextStyle(
                    color: Color(0xFF596173),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (normalized == 'rejected' && reason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Admin note: $reason',
                    style: const TextStyle(
                      color: Color(0xFF2F3544),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (hint != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    hint!,
                    style: const TextStyle(
                      color: Color(0xFF2F3544),
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
