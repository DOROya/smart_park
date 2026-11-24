import 'saved_payment.dart' show normalizePhMobile, localPhMobile;

/// Longest contact number stored (the rules allow the same).
const int kMaxContactNumberLength = 20;

/// A facility's contact number as stored: a Philippine mobile as
/// "+639171234567", a landline as typed (digits, spaces, dashes and
/// brackets, e.g. "(02) 8123 4567"),
/// '' for none, or null when it is neither.
String? normalizeFacilityContact(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) return '';
  final String? mobile = normalizePhMobile(text);
  if (mobile != null) return mobile;
  final String landline = text.replaceAll(RegExp(r'\s+'), ' ');
  final int digits = landline.replaceAll(RegExp(r'[^0-9]'), '').length;
  if (!RegExp(r'^[0-9 \-()]+$').hasMatch(landline) ||
      digits < 7 ||
      landline.length > kMaxContactNumberLength) {
    return null;
  }
  return landline;
}

/// How a stored number is shown: "0917 123 4567" for a mobile, a landline
/// as saved.
String displayFacilityContact(String stored) {
  final String local = localPhMobile(stored);
  return local.isNotEmpty ? local : stored.trim();
}

/// What a `tel:` link dials.
String dialableFacilityContact(String stored) =>
    stored.replaceAll(RegExp(r'[^0-9+]'), '');
