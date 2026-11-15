import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// A facility's admin review state, stored as `establishment_details.status`:
/// pending, approved, rejected, suspended or deactivated.
String facilityStatus(Map<String, dynamic>? details) =>
    ((details?['status'] as String?) ?? 'pending').trim().toLowerCase();

/// Reasons an admin picks from (one or more) when suspending or deactivating
/// a facility, stored as `establishment_details.restrictionReasons`, with
/// `restrictionReason` holding them joined for screens that show one line.
/// Unlike the admin's free-text note (`rejectionReason`), which only the
/// owner sees, the picked reasons are also shown to drivers holding tickets
/// for the facility.
const List<String> kRestrictionReasons = <String>[
  // The permit was already bad when SmartPark approved it (SmartPark covers
  // the refunds), as opposed to one that lapsed afterwards (the owner does).
  'Invalid business permit',
  kPermitExpiredReason,
  'Incomplete or false documents',
  'Safety or security concerns',
  'Rates differ from the listing',
  'Repeated driver complaints',
  'Facility not operating',
  'SmartPark policy violation',
  'Requested by the owner',
  'Other',
];

/// A permit that was valid when approved and has since lapsed.
const String kPermitExpiredReason = 'Business permit expired';

/// Reasons serious enough to pull a facility at once. Any other reason can
/// be fixed, so the owner first gets [kComplianceNoticeDays] days' notice.
const List<String> kImmediateRestrictionReasons = <String>[
  'Invalid business permit',
  'Incomplete or false documents',
  'Safety or security concerns',
  'Facility not operating',
  'Requested by the owner',
];

/// Days an owner has to fix what a notice names before a suspension.
const int kComplianceNoticeDays = 7;

/// Whether suspending for [reasons] needs a notice first: none of them is
/// one SmartPark may act on at once.
bool needsNoticeFirst(List<String> reasons) =>
    reasons.isNotEmpty && !reasons.any(kImmediateRestrictionReasons.contains);

/// A written notice to fix something before a suspension, kept on
/// `establishment_details.complianceNotice` while it stands.
class ComplianceNotice {
  const ComplianceNotice({
    required this.reasons,
    required this.message,
    required this.issuedAt,
    required this.dueAt,
  });

  /// The notice on a facility's details; null when there is none.
  static ComplianceNotice? of(Map<String, dynamic>? details) {
    final Object? raw = details?['complianceNotice'];
    if (raw is! Map) return null;
    DateTime? date(Object? v) =>
        v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
    final DateTime? issuedAt = date(raw['issuedAt']);
    final DateTime? dueAt = date(raw['dueAt']);
    if (issuedAt == null || dueAt == null) return null;
    final Object? reasons = raw['reasons'];
    return ComplianceNotice(
      reasons: reasons is List
          ? reasons.whereType<String>().toList()
          : const <String>[],
      message: ((raw['message'] as String?) ?? '').trim(),
      issuedAt: issuedAt,
      dueAt: dueAt,
    );
  }

  final List<String> reasons;
  final String message;
  final DateTime issuedAt;
  final DateTime dueAt;

  /// The time to fix it has run out, so the facility may be suspended.
  bool lapsedAt(DateTime now) => !now.isBefore(dueAt);
}

/// How several picked reasons read on one line.
String joinReasons(Iterable<String> reasons) => reasons.join(', ');

/// The reasons an admin picked for pulling the facility; empty when none
/// were recorded (or the facility isn't pulled). Facilities pulled before
/// several reasons could be picked have the one `restrictionReason`.
List<String> facilityRestrictionReasons(Map<String, dynamic>? details) {
  if (!isFacilityRestricted(details)) return const <String>[];
  final Object? list = details?['restrictionReasons'];
  if (list is List && list.isNotEmpty) {
    return <String>[
      for (final Object? reason in list)
        if (reason is String && reason.trim().isNotEmpty) reason.trim(),
    ];
  }
  final String reason = ((details?['restrictionReason'] as String?) ?? '')
      .trim();
  return reason.isEmpty ? const <String>[] : <String>[reason];
}

/// [facilityRestrictionReasons] on one line; null when there are none.
String? facilityRestrictionReason(Map<String, dynamic>? details) {
  final List<String> reasons = facilityRestrictionReasons(details);
  return reasons.isEmpty ? null : joinReasons(reasons);
}

/// Suspended and deactivated facilities were pulled by an admin: they sell no
/// tickets and their gates admit no one, so tickets they issued can't be used
/// to enter until the facility is reinstated.
bool isFacilityRestricted(Map<String, dynamic>? details) {
  final String status = facilityStatus(details);
  return status == 'suspended' || status == 'deactivated';
}
