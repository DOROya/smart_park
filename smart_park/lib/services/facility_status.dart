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
  'Invalid business permit',
  'Incomplete or false documents',
  'Safety or security concerns',
  'Rates differ from the listing',
  'Repeated driver complaints',
  'Facility not operating',
  'SmartPark policy violation',
  'Requested by the owner',
  'Other',
];

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
