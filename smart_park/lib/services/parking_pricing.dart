import 'dart:convert';

/// Package pricing and overtime rules shared by the driver's package picker
/// and the staff gate. The checkout Cloud Function (functions/src/pricing.js)
/// prices packages the same way; keep the two in step.

/// Hours included in every base stay.
const int kBaseStayHours = 2;

/// Minutes past the included time before overtime starts.
const Duration kOvertimeGrace = Duration(minutes: 5);

/// Reads a money value: numbers as-is, else the first number in a string
/// ("PHP 12.50/hr" -> 12.5). Anything else is 0.
double parseAmount(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is! String) return 0;
  final Match? match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(value);
  return double.tryParse(match?.group(1) ?? '') ?? 0;
}

/// The rates one vehicle type offers, read the way the app has always read
/// `ratesByType[vehicle]` (a map of rates, or a single flat rate).
class VehicleRates {
  const VehicleRates({
    required this.initial,
    required this.succeedingHour,
    required this.succeedingDaily,
  });

  factory VehicleRates.from(dynamic vehicleRate) {
    final Map<String, dynamic> rateMap = vehicleRate is Map
        ? vehicleRate.map<String, dynamic>(
            (dynamic k, dynamic v) => MapEntry(k.toString(), v),
          )
        : <String, dynamic>{};
    return VehicleRates(
      initial: parseAmount(
        rateMap['initial'] ??
            rateMap['hourly'] ??
            rateMap['rates'] ??
            (vehicleRate is Map ? null : vehicleRate),
      ),
      succeedingHour: parseAmount(
        rateMap['succeedingHour'] ?? rateMap['succeeding_hour'],
      ),
      succeedingDaily: parseAmount(
        rateMap['succeedingDaily'] ??
            rateMap['succeeding_daily'] ??
            rateMap['daily'],
      ),
    );
  }

  final double initial;
  final double succeedingHour;
  final double succeedingDaily;

  bool get offersBase => initial > 0;
  bool get offersExtended => initial > 0 && succeedingHour > 0;
  bool get offersDaily => succeedingDaily > 0;
}

/// Price of a package: `base` is one fixed stay, `extended` adds
/// [duration] succeeding hours, `daily` is [duration] days.
double packageTotal({
  required String plan,
  required double initialAmount,
  double succeedingHourAmount = 0,
  double dailyAmount = 0,
  required int duration,
}) {
  switch (plan) {
    case 'base':
      return initialAmount;
    case 'extended':
      return initialAmount + (succeedingHourAmount * duration);
    case 'daily':
      return dailyAmount * duration;
    default:
      return initialAmount > 0 ? initialAmount : dailyAmount * duration;
  }
}

/// Hours of parking a ticket already paid for.
int includedStayHours({required String plan, required int duration}) {
  final int count = duration < 1 ? 1 : duration;
  return switch (plan) {
    'extended' => kBaseStayHours + count,
    'daily' => 24 * count,
    _ => kBaseStayHours,
  };
}

/// Whole overtime hours (rounded up) past [includedHours] plus the grace
/// period.
int overtimeHours(Duration elapsed, int includedHours) {
  final Duration billable =
      elapsed - Duration(hours: includedHours) - kOvertimeGrace;
  if (billable.inSeconds <= 0) return 0;
  return (billable.inSeconds / 3600).ceil();
}

/// When overtime starts for a stay that began at [entryAt]: the paid hours
/// plus the grace period.
DateTime overtimeStartsAt(DateTime entryAt, int includedHours) =>
    entryAt.add(Duration(hours: includedHours) + kOvertimeGrace);

/// A ticket's package duration. Newer tickets store it on the document;
/// older ones only carried it inside the QR payload.
int ticketDuration(Map<String, dynamic> ticket) {
  final dynamic direct = ticket['duration'];
  if (direct is num) return direct.toInt();
  final dynamic qr = ticket['qrCode'];
  if (qr is String && qr.isNotEmpty) {
    try {
      final dynamic decoded = jsonDecode(qr);
      if (decoded is Map && decoded['duration'] is num) {
        return (decoded['duration'] as num).toInt();
      }
    } on FormatException {
      // Not JSON; fall through.
    }
  }
  return 1;
}

double? _parseMoney(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), ''));
  }
  return null;
}

/// Hourly overtime rate for [vehicleType]: the succeeding-hour rate, else
/// the hourly/initial rate, else a flat rate. Null when none is set.
double? resolveOvertimeRate(Map<String, dynamic>? rates, String vehicleType) {
  if (rates == null) return null;
  final dynamic vehicle =
      rates[vehicleType] ?? rates[vehicleType.toLowerCase()];
  if (vehicle is Map) {
    final Map<String, dynamic> vehicleRates = vehicle.map<String, dynamic>(
      (dynamic key, dynamic item) =>
          MapEntry<String, dynamic>(key.toString(), item),
    );
    return _parseMoney(vehicleRates['succeedingHour']) ??
        _parseMoney(vehicleRates['succeeding_hour']) ??
        _parseMoney(vehicleRates['hourly']) ??
        _parseMoney(vehicleRates['initial']);
  }
  return _parseMoney(vehicle);
}
