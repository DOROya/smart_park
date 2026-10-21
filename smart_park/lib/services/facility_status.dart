/// A facility's admin review state, stored as `establishment_details.status`:
/// pending, approved, rejected, suspended or deactivated.
String facilityStatus(Map<String, dynamic>? details) =>
    ((details?['status'] as String?) ?? 'pending').trim().toLowerCase();

/// Reasons an admin picks from when suspending or deactivating a facility,
/// stored as `establishment_details.restrictionReason`. Unlike the admin's
/// free-text note (`rejectionReason`), which only the owner sees, the picked
/// reason is also shown to drivers holding tickets for the facility.
const List<String> kRestrictionReasons = <String>[
  'Expired or invalid business permit',
  'Incomplete or falsified documents',
  'Safety or security concerns',
  'Rates charged differ from the listing',
  'Repeated driver complaints',
  'Facility closed or not operating',
  'Violation of SmartPark policies',
  'Requested by the owner',
  'Other',
];

/// The reason an admin picked for pulling the facility; null when none was
/// recorded (or the facility isn't pulled).
String? facilityRestrictionReason(Map<String, dynamic>? details) {
  if (!isFacilityRestricted(details)) return null;
  final String reason = ((details?['restrictionReason'] as String?) ?? '')
      .trim();
  return reason.isEmpty ? null : reason;
}

/// Suspended and deactivated facilities were pulled by an admin: they sell no
/// tickets and their gates admit no one, so tickets they issued can't be used
/// to enter until the facility is reinstated.
bool isFacilityRestricted(Map<String, dynamic>? details) {
  final String status = facilityStatus(details);
  return status == 'suspended' || status == 'deactivated';
}
