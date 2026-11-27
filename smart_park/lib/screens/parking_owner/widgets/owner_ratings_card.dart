import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/smartpark_ui.dart';
import '../../driver/widgets/rate_facility.dart';

/// Driver ratings of the owner's facility: the average drivers see, how
/// many, and the latest comments (without names).
class OwnerRatingsCard extends StatefulWidget {
  const OwnerRatingsCard({super.key, required this.facilityId});

  final String facilityId;

  @override
  State<OwnerRatingsCard> createState() => _OwnerRatingsCardState();
}

/// Average stars to one decimal and the count, from rating documents.
({double average, int count}) ratingAverage(
  Iterable<Map<String, dynamic>> ratings,
) {
  int sum = 0;
  int count = 0;
  for (final Map<String, dynamic> r in ratings) {
    final Object? s = r['stars'];
    if (s is int && s >= 1 && s <= 5) {
      sum += s;
      count++;
    }
  }
  return (
    average: count == 0 ? 0 : (sum / count * 10).round() / 10,
    count: count,
  );
}

class _OwnerRatingsCardState extends State<OwnerRatingsCard> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _ratings =
      FirebaseFirestore.instance
          .collection('facility_ratings')
          .where('establishmentId', isEqualTo: widget.facilityId)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _ratings,
      builder: (context, snapshot) {
        final List<Map<String, dynamic>> all =
            (snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .map((d) => d.data())
                .toList();
        // Older ratings were one per ticket: count each driver once.
        final List<Map<String, dynamic>> ratings = latestRatingPerDriver(all)
          ..sort(
            (a, b) => (spParseDateTime(b['updatedAt']) ?? DateTime(0))
                .compareTo(spParseDateTime(a['updatedAt']) ?? DateTime(0)),
          );
        final ({double average, int count}) avg = ratingAverage(ratings);
        final List<Map<String, dynamic>> comments = ratings
            .where((r) => ((r['comment'] as String?) ?? '').trim().isNotEmpty)
            .take(5)
            .toList();
        return SpSectionCard(
          icon: Icons.star_rounded,
          title: 'Driver Ratings',
          subtitle: avg.count == 0
              ? 'Drivers can rate your facility after they park.'
              : '${avg.average.toStringAsFixed(1)} out of 5 from '
                    '${avg.count} driver${avg.count == 1 ? '' : 's'}',
          child: avg.count == 0
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int stars = 5; stars >= 1; stars--)
                      _bar(
                        stars,
                        ratings.where((r) => r['stars'] == stars).length,
                        avg.count,
                      ),
                    if (comments.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      for (final Map<String, dynamic> r in comments)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${'★' * ((r['stars'] as num?) ?? 0).toInt()} '
                            '"${(r['comment'] as String).trim()}"'
                            '${spParseDateTime(r['updatedAt']) == null ? '' : ' · ${spFormatDate(spParseDateTime(r['updatedAt'])!)}'}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textDark,
                              height: 1.35,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _bar(int stars, int count, int total) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Text(
              '$stars★',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : count / total,
                minHeight: 8,
                backgroundColor: AppTheme.surfaceAlt,
                color: AppTheme.accent,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$count',
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
