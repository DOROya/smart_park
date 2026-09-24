/// A facility's daily opening hours.
///
/// Stored on `establishments` both as structured fields (`openTime`,
/// `closeTime` as "HH:mm", `open24Hours`) and as the display string in
/// `operatingHours` ("6:00 AM - 10:00 PM" / "Open 24 hours"), which older
/// screens and older records use. [parse] reads either.
class OperatingHours {
  const OperatingHours({
    this.openMinutes,
    this.closeMinutes,
    this.allDay = false,
  });

  const OperatingHours.allDay() : this(allDay: true);

  /// Minutes after midnight; null when unset.
  final int? openMinutes;
  final int? closeMinutes;
  final bool allDay;

  bool get isSet => allDay || (openMinutes != null && closeMinutes != null);

  /// Closing at or before opening means the facility is open overnight.
  bool get overnight =>
      !allDay &&
      isSet &&
      closeMinutes! <= openMinutes! &&
      closeMinutes != openMinutes;

  static OperatingHours parse(Map<String, dynamic> data) {
    if (data['open24Hours'] == true) return const OperatingHours.allDay();
    final int? open = _parse24h(data['openTime']);
    final int? close = _parse24h(data['closeTime']);
    if (open != null && close != null) {
      return OperatingHours(openMinutes: open, closeMinutes: close);
    }
    return parseText((data['operatingHours'] as String?) ?? '');
  }

  /// Reads the free-text form, e.g. "6:00 AM - 10:00 PM" or "Open 24 hours".
  static OperatingHours parseText(String text) {
    final String hours = text.trim();
    if (hours.isEmpty) return const OperatingHours();
    if (RegExp(
      r'24\s*(/\s*7|h|hr|hrs|hours)',
      caseSensitive: false,
    ).hasMatch(hours)) {
      return const OperatingHours.allDay();
    }
    final List<String> parts = hours.split(RegExp(r'\s*[-–]\s*'));
    if (parts.length != 2) return const OperatingHours();
    final int? open = _parse12h(parts[0]);
    final int? close = _parse12h(parts[1]);
    if (open == null || close == null) return const OperatingHours();
    return OperatingHours(openMinutes: open, closeMinutes: close);
  }

  /// "6:00 AM - 10:00 PM", "Open 24 hours", or '' when unset.
  String get label {
    if (allDay) return 'Open 24 hours';
    if (!isSet) return '';
    return '${format12h(openMinutes!)} - ${format12h(closeMinutes!)}';
  }

  bool isOpenAt(DateTime time) {
    if (allDay) return true;
    if (!isSet) return false;
    final int now = time.hour * 60 + time.minute;
    final int open = openMinutes!;
    final int close = closeMinutes!;
    if (open == close) return true;
    if (open < close) return now >= open && now < close;
    return now >= open || now < close;
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
    'operatingHours': label,
    'open24Hours': allDay,
    'openTime': allDay || openMinutes == null ? null : format24h(openMinutes!),
    'closeTime': allDay || closeMinutes == null
        ? null
        : format24h(closeMinutes!),
  };

  static String format12h(int minutes) {
    final int h24 = (minutes ~/ 60) % 24;
    final int m = minutes % 60;
    final int h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h24 < 12 ? 'AM' : 'PM'}';
  }

  static String format24h(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  static int? _parse24h(dynamic value) {
    if (value is! String) return null;
    final Match? m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (m == null) return null;
    final int h = int.parse(m.group(1)!);
    final int min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }

  static int? _parse12h(String raw) {
    final Match? m = RegExp(
      r'^(\d{1,2})(?::(\d{2}))?\s*([AaPp])\.?\s*[Mm]\.?$',
    ).firstMatch(raw.trim());
    if (m == null) return null;
    int hour = int.parse(m.group(1)!);
    final int minute = int.tryParse(m.group(2) ?? '0') ?? 0;
    if (hour < 1 || hour > 12 || minute > 59) return null;
    hour = hour % 12;
    if (m.group(3)!.toUpperCase() == 'P') hour += 12;
    return hour * 60 + minute;
  }
}
