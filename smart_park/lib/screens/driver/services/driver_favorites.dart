import 'package:cloud_firestore/cloud_firestore.dart';

/// Facilities a driver saved (the heart on a facility), kept on their own
/// profile as `users/{uid}.favoriteEstablishmentIds`, so they follow the
/// driver to a new phone. The rules already let a user edit their own
/// profile (everything but the role).
class DriverFavorites {
  const DriverFavorites._();

  static const String field = 'favoriteEstablishmentIds';

  /// The saved facility ids on a profile.
  static Set<String> fromProfile(Map<String, dynamic>? profile) {
    final Object? raw = profile?[field];
    if (raw is! List) return <String>{};
    return raw.whereType<String>().where((String id) => id.isNotEmpty).toSet();
  }

  static DocumentReference<Map<String, dynamic>> _profile(
    String uid, {
    FirebaseFirestore? firestore,
  }) => (firestore ?? FirebaseFirestore.instance).collection('users').doc(uid);

  /// The driver's saved facilities, live.
  static Stream<Set<String>> watch(String uid, {FirebaseFirestore? firestore}) {
    return _profile(uid, firestore: firestore).snapshots().map(
      (DocumentSnapshot<Map<String, dynamic>> snap) => fromProfile(snap.data()),
    );
  }

  /// Saves or un-saves [establishmentId] for [uid].
  static Future<void> setSaved(
    String uid,
    String establishmentId, {
    required bool saved,
    FirebaseFirestore? firestore,
  }) {
    return _profile(uid, firestore: firestore).set(<String, dynamic>{
      field: saved
          ? FieldValue.arrayUnion(<String>[establishmentId])
          : FieldValue.arrayRemove(<String>[establishmentId]),
    }, SetOptions(merge: true));
  }
}

/// The facilities a driver parked at most recently, newest first, from
/// their [tickets] (each ticket's latest entry, exit or purchase time).
/// Walk-in records and tickets without a facility are skipped.
List<String> recentFacilityIds(
  Iterable<Map<String, dynamic>> tickets, {
  int limit = 5,
}) {
  DateTime? at(Object? value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : null;

  final Map<String, DateTime> latest = <String, DateTime>{};
  for (final Map<String, dynamic> ticket in tickets) {
    if (ticket['source'] == 'walk_in') continue;
    final String id = ((ticket['establishmentId'] as String?) ?? '').trim();
    if (id.isEmpty) continue;
    final List<DateTime> times = <DateTime?>[
      at(ticket['exitAt']),
      at(ticket['entryAt']),
      at(ticket['createdAt']),
    ].whereType<DateTime>().toList();
    if (times.isEmpty) continue;
    final DateTime when = times.reduce(
      (DateTime a, DateTime b) => a.isAfter(b) ? a : b,
    );
    final DateTime? seen = latest[id];
    if (seen == null || when.isAfter(seen)) latest[id] = when;
  }
  final List<String> ids = latest.keys.toList()
    ..sort((String a, String b) => latest[b]!.compareTo(latest[a]!));
  return ids.take(limit).toList();
}
