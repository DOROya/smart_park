import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/smartpark_ui.dart' show spParseDateTime;

/// A platform notice (`announcements/{id}`, written by the server), e.g. a
/// commission change. Shown once as a pop-up when the app opens and kept
/// under Profile › Announcements.
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    this.createdAt,
    this.effectiveAt,
    this.oldRate,
    this.newRate,
  });

  factory Announcement.fromMap(String id, Map<String, dynamic> m) =>
      Announcement(
        id: id,
        title: ((m['title'] as String?) ?? '').trim(),
        body: ((m['body'] as String?) ?? '').trim(),
        kind: ((m['kind'] as String?) ?? 'general').trim(),
        createdAt: spParseDateTime(m['createdAt']),
        effectiveAt: spParseDateTime(m['effectiveAt']),
        oldRate: (m['oldRate'] as num?)?.toDouble(),
        newRate: (m['newRate'] as num?)?.toDouble(),
      );

  final String id;
  final String title;
  final String body;

  /// "commission_change" or "general".
  final String kind;
  final DateTime? createdAt;
  final DateTime? effectiveAt;
  final double? oldRate;
  final double? newRate;

  bool get isCommissionChange => kind == 'commission_change';
}

/// The audience an account's role reads, as the rules match it.
String audienceForRole(String role) => switch (role.trim().toLowerCase()) {
  'parking owner' => 'owners',
  'driver' => 'drivers',
  'staff' || 'supervisor' => 'staff',
  _ => '',
};

/// The announcements to pop up, oldest first: never seen, or a commission
/// change not acknowledged before it takes effect.
List<Announcement> announcementsToShow(
  Iterable<Announcement> all,
  Map<String, Map<String, dynamic>> reads, {
  DateTime? now,
}) {
  final DateTime at = now ?? DateTime.now();
  final List<Announcement> out = all.where((Announcement a) {
    final Map<String, dynamic>? read = reads[a.id];
    if (read == null) return true;
    if (!a.isCommissionChange || read['acknowledged'] == true) return false;
    final DateTime? effective = a.effectiveAt;
    return effective != null && at.isBefore(effective);
  }).toList();
  final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);
  out.sort(
    (Announcement a, Announcement b) =>
        (a.createdAt ?? epoch).compareTo(b.createdAt ?? epoch),
  );
  return out;
}

class AnnouncementService {
  AnnouncementService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Every announcement for [role]'s audience and for everyone, newest
  /// first. Two queries, since the rules match one audience at a time.
  Future<List<Announcement>> forRole(String role) async {
    final String audience = audienceForRole(role);
    final List<QuerySnapshot<Map<String, dynamic>>> snaps = await Future.wait(
      <Future<QuerySnapshot<Map<String, dynamic>>>>[
        for (final String a in <String>[
          'all',
          if (audience.isNotEmpty) audience,
        ])
          _db.collection('announcements').where('audience', isEqualTo: a).get(),
      ],
    );
    final List<Announcement> out = <Announcement>[
      for (final QuerySnapshot<Map<String, dynamic>> s in snaps)
        for (final QueryDocumentSnapshot<Map<String, dynamic>> d in s.docs)
          Announcement.fromMap(d.id, d.data()),
    ];
    final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);
    out.sort(
      (Announcement a, Announcement b) =>
          (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch),
    );
    return out;
  }

  CollectionReference<Map<String, dynamic>> _reads(String uid) =>
      _db.collection('users').doc(uid).collection('announcement_reads');

  Future<Map<String, Map<String, dynamic>>> reads(String uid) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _reads(uid).get();
    return <String, Map<String, dynamic>>{
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs)
        d.id: d.data(),
    };
  }

  Future<void> markSeen(String uid, String announcementId) =>
      _reads(uid).doc(announcementId).set(<String, dynamic>{
        'announcementId': announcementId,
        'seenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> acknowledge(String uid, String announcementId) =>
      _reads(uid).doc(announcementId).set(<String, dynamic>{
        'announcementId': announcementId,
        'seenAt': FieldValue.serverTimestamp(),
        'acknowledgedAt': FieldValue.serverTimestamp(),
        'acknowledged': true,
      }, SetOptions(merge: true));

  /// Admin: how many accounts acknowledged [announcementId].
  Future<int> acknowledgedCount(String announcementId) async {
    final AggregateQuerySnapshot snap = await _db
        .collectionGroup('announcement_reads')
        .where('announcementId', isEqualTo: announcementId)
        .where('acknowledged', isEqualTo: true)
        .count()
        .get();
    return snap.count ?? 0;
  }
}
