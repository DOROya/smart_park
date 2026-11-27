import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/error_reporter.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../widgets/smartpark_ui.dart';
import '../../../widgets/sp_dialog.dart';

/// After parking, a driver rates the facility 1-5 stars with an optional
/// comment: one rating per driver per facility
/// (`facility_ratings/{driverId}_{establishmentId}`), which they can change
/// from any of their used tickets there. The server keeps each facility's
/// average. Older ratings were saved per ticket; the newest one a driver
/// gave a facility is the one that counts and is shown.

const int kMaxRatingComment = 300;

/// A ticket the driver has parked on and left at least once.
bool canRateTicket(Map<String, dynamic> ticket) =>
    ticket['source'] != 'walk_in' &&
    ticket['exitAt'] != null &&
    ((ticket['establishmentId'] as String?) ?? '').isNotEmpty;

/// The id of [driverId]'s one rating of [establishmentId].
String facilityRatingId(String driverId, String establishmentId) =>
    '${driverId}_$establishmentId';

/// Each driver's newest rating among [ratings]: older ratings were saved
/// once per ticket, so a driver may have several of one facility.
List<Map<String, dynamic>> latestRatingPerDriver(
  Iterable<Map<String, dynamic>> ratings,
) {
  final Map<String, Map<String, dynamic>> byDriver =
      <String, Map<String, dynamic>>{};
  int anonymous = 0;
  DateTime at(Map<String, dynamic> r) =>
      spParseDateTime(r['updatedAt']) ??
      spParseDateTime(r['createdAt']) ??
      DateTime(0);
  for (final Map<String, dynamic> r in ratings) {
    final String driver = (r['driverId'] as String?) ?? '';
    final String key = driver.isEmpty ? '#${anonymous++}' : driver;
    final Map<String, dynamic>? kept = byDriver[key];
    if (kept == null || at(r).isAfter(at(kept))) byDriver[key] = r;
  }
  return byDriver.values.toList();
}

/// Saves the driver's rating of the facility: creates it, or changes stars
/// and comment keeping when it was first given. [ticketId] is a used ticket
/// of theirs there, which the security rules check.
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
          .doc(facilityRatingId(driverId, establishmentId));
  final Map<String, dynamic> fields = <String, dynamic>{
    'ticketId': ticketId,
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
  // Every rating this driver gave the facility: the current one, and any
  // older per-ticket ones from before ratings were one per facility.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _ratings =
      FirebaseFirestore.instance
          .collection('facility_ratings')
          .where(
            'driverId',
            isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
          )
          .where(
            'establishmentId',
            isEqualTo: widget.ticket['establishmentId'] as String,
          )
          .snapshots();

  Future<void> _rate(Map<String, dynamic>? current, bool exists) async {
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
        exists: exists,
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
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _ratings,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
            snapshot.data!.docs;
        final List<Map<String, dynamic>> latest = latestRatingPerDriver(
          docs.map((d) => d.data()),
        );
        final Map<String, dynamic>? current = latest.isEmpty
            ? null
            : latest.first;
        final String id = facilityRatingId(
          FirebaseAuth.instance.currentUser?.uid ?? '',
          widget.ticket['establishmentId'] as String,
        );
        final bool exists = docs.any((d) => d.id == id);
        final int stars = ((current?['stars'] as num?) ?? 0).toInt();
        if (stars == 0) {
          return Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _rate(null, false),
              icon: Icon(
                Icons.star_outline_rounded,
                size: 16,
                color: AppTheme.accentText,
              ),
              // Same look as Add hours and Change plate beside it.
              label: const Text(
                'Rate this facility',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentText,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
        }
        // Already rated: their stars, which they tap to change.
        return Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: 'Change your rating',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _rate(current, exists),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Your rating ',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    for (int i = 1; i <= 5; i++)
                      Icon(
                        i <= stars
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 18,
                        color: AppTheme.accent,
                      ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.edit_rounded,
                      size: 14,
                      color: AppTheme.accentText,
                    ),
                  ],
                ),
              ),
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
      scrollable: true,
      icon: const SpDialogIcon(Icons.star_rounded, tone: SpDialogTone.info),
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
