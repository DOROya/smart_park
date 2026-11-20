import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/error_reporter.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/friendly_error.dart';

/// After parking, a driver rates the facility 1-5 stars with an optional
/// comment: one rating per ticket (`facility_ratings/{ticketId}`), which
/// they can change. The server keeps each facility's average.

const int kMaxRatingComment = 300;

/// A ticket the driver has parked on and left at least once.
bool canRateTicket(Map<String, dynamic> ticket) =>
    ticket['source'] != 'walk_in' &&
    ticket['exitAt'] != null &&
    ((ticket['establishmentId'] as String?) ?? '').isNotEmpty;

/// Saves a rating: creates it, or changes stars and comment keeping when
/// it was first given.
Future<void> saveFacilityRating({
  required String ticketId,
  required String establishmentId,
  required String driverId,
  required int stars,
  String comment = '',
  required bool exists,
  FirebaseFirestore? firestore,
}) {
  if (stars < 1 || stars > 5) throw ArgumentError.value(stars, 'stars');
  final DocumentReference<Map<String, dynamic>> ref =
      (firestore ?? FirebaseFirestore.instance)
          .collection('facility_ratings')
          .doc(ticketId);
  final Map<String, dynamic> fields = <String, dynamic>{
    'stars': stars,
    'comment': comment.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
  return exists
      ? ref.update(fields)
      : ref.set(<String, dynamic>{
          ...fields,
          'establishmentId': establishmentId,
          'driverId': driverId,
          'createdAt': FieldValue.serverTimestamp(),
        });
}

/// "Rate Lot A" on a used ticket, or the stars given, with Edit.
class RateFacilityRow extends StatefulWidget {
  const RateFacilityRow({
    super.key,
    required this.ticketId,
    required this.ticket,
  });

  final String ticketId;
  final Map<String, dynamic> ticket;

  @override
  State<RateFacilityRow> createState() => _RateFacilityRowState();
}

class _RateFacilityRowState extends State<RateFacilityRow> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _rating =
      FirebaseFirestore.instance
          .collection('facility_ratings')
          .doc(widget.ticketId)
          .snapshots();

  Future<void> _rate(Map<String, dynamic>? current) async {
    final String facility =
        ((widget.ticket['establishmentName'] as String?) ?? '').trim();
    final ({int stars, String comment})? picked =
        await showDialog<({int stars, String comment})>(
          context: context,
          builder: (_) => _RatingDialog(
            facility: facility.isEmpty ? 'this facility' : facility,
            stars: ((current?['stars'] as num?) ?? 0).toInt(),
            comment: (current?['comment'] as String?) ?? '',
          ),
        );
    if (picked == null || !mounted) return;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await saveFacilityRating(
        ticketId: widget.ticketId,
        establishmentId: widget.ticket['establishmentId'] as String,
        driverId: uid,
        stars: picked.stars,
        comment: picked.comment,
        exists: current != null,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Thanks for rating.')));
      }
    } catch (error, stack) {
      reportError(error, stack, reason: 'Facility rating');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(error, fallback: 'Could not save. Try again.'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _rating,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final Map<String, dynamic>? current = snapshot.data!.data();
        final int stars = ((current?['stars'] as num?) ?? 0).toInt();
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _rate(current),
            icon: Icon(
              stars > 0 ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 16,
              color: AppTheme.accentText,
            ),
            // Same look as Add hours and Change plate beside it.
            label: Text(
              stars > 0 ? 'You rated it $stars/5 · Edit' : 'Rate this facility',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.accentText,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
        );
      },
    );
  }
}

class _RatingDialog extends StatefulWidget {
  const _RatingDialog({
    required this.facility,
    required this.stars,
    required this.comment,
  });

  final String facility;
  final int stars;
  final String comment;

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  late int _stars = widget.stars;
  late final TextEditingController _comment = TextEditingController(
    text: widget.comment,
  );

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('How was ${widget.facility}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (int i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i star${i == 1 ? '' : 's'}',
                  onPressed: () => setState(() => _stars = i),
                  icon: Icon(
                    i <= _stars
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 34,
                    color: AppTheme.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _comment,
            maxLength: kMaxRatingComment,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
              hintText: 'Easy to find? Staff helpful? Safe?',
              border: OutlineInputBorder(),
            ),
          ),
          Text(
            'The facility\'s owner sees your stars and comment, not your '
            'name.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _stars == 0
              ? null
              : () => Navigator.of(
                  context,
                ).pop((stars: _stars, comment: _comment.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
