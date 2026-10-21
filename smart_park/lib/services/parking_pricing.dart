import 'dart:convert';

/// Package pricing and overtime rules shared by the driver's package picker
/// and the staff gate. The checkout Cloud Function (functions/src/pricing.js)
/// prices packages the same way; keep the two in step.

/// Hours included in every base stay, and the fewest hours a visit takes
/// off a ticket.
const int kBaseStayHours = 2;

/// Hours one week and one month of a long-term package cover. A month is
/// counted as 30 days so every month buys the same amount of parking.
const int kHoursPerWeek = 24 * 7;
const int kHoursPerMonth = 24 * 30;

/// Largest duration each package allows; plans not listed take no duration.
/// Must match `MAX_DURATION` in functions/src/pricing.js.
const Map<String, int> kMaxPackageDuration = <String, int>{
  'extended': 12,
  'daily': 7,
  'weekly': 4,
  'monthly': 3,
};

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
    this.weekly = 0,
    this.monthly = 0,
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
      weekly: parseAmount(
        rateMap['weekly'] ??
            rateMap['succeedingWeekly'] ??
            rateMap['succeeding_weekly'],
      ),
      monthly: parseAmount(
        rateMap['monthly'] ??
            rateMap['succeedingMonthly'] ??
            rateMap['succeeding_monthly'],
      ),
    );
  }

  final double initial;
  final double succeedingHour;
  final double succeedingDaily;

  /// Long-term rates; 0 when the owner doesn't offer them.
  final double weekly;
  final double monthly;

  bool get offersBase => initial > 0;
  bool get offersExtended => initial > 0 && succeedingHour > 0;
  bool get offersDaily => succeedingDaily > 0;
  bool get offersWeekly => weekly > 0;
  bool get offersMonthly => monthly > 0;
}

/// Price of a package: `base` is one fixed stay, `extended` adds
/// [duration] succeeding hours, and `daily`, `weekly` and `monthly` are
/// [duration] days, weeks or months.
double packageTotal({
  required String plan,
  required double initialAmount,
  double succeedingHourAmount = 0,
  double dailyAmount = 0,
  double weeklyAmount = 0,
  double monthlyAmount = 0,
  required int duration,
}) {
  switch (plan) {
    case 'base':
      return initialAmount;
    case 'extended':
      return initialAmount + (succeedingHourAmount * duration);
    case 'daily':
      return dailyAmount * duration;
    case 'weekly':
      return weeklyAmount * duration;
    case 'monthly':
      return monthlyAmount * duration;
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
    'weekly' => kHoursPerWeek * count,
    'monthly' => kHoursPerMonth * count,
    _ => kBaseStayHours,
  };
}

/// Hours a stay counts as: every started hour, by whole minutes, with no
/// grace (2h05m and 2h15m are both 3 hours).
int stayHours(Duration elapsed) =>
    elapsed.inMinutes <= 0 ? 0 : (elapsed.inMinutes / 60).ceil();

/// Hours of a stay past the [paidHours] left on the ticket, billed as
/// overtime.
int overtimeHours(Duration elapsed, int paidHours) {
  final int over = stayHours(elapsed) - paidHours;
  return over > 0 ? over : 0;
}

/// Hours an exit takes off a ticket with [paidHours] left: the hours
/// stayed, at least the base stay, never more than what is left.
int hoursDeducted(Duration elapsed, int paidHours) {
  final int stayed = stayHours(elapsed);
  final int used = stayed < kBaseStayHours ? kBaseStayHours : stayed;
  return used < paidHours ? used : paidHours;
}

/// When overtime starts for a stay that began at [entryAt]: the first
/// minute past the [paidHours] left.
DateTime overtimeStartsAt(DateTime entryAt, int paidHours) =>
    entryAt.add(Duration(hours: paidHours, minutes: 1));

/// Hours a ticket can still be parked on. Tickets are reusable until their
/// hours run out; each exit stores what is left in `remainingHours`. Tickets
/// checked out before that field existed count as used up.
int ticketHoursLeft(Map<String, dynamic> ticket) {
  final dynamic stored = ticket['remainingHours'];
  if (stored is num) return stored.toInt() < 0 ? 0 : stored.toInt();
  final String entry = ((ticket['entryStatus'] as String?) ?? '').toLowerCase();
  if (entry == 'checked_out' || entry == 'exited') return 0;
  return includedStayHours(
    plan: ((ticket['plan'] as String?) ?? 'base').trim().toLowerCase(),
    duration: ticketDuration(ticket),
  );
}

/// Parking hours in words, split into days once there is at least one:
/// 166 -> "6 days, 22 hours", 48 -> "2 days", 5 -> "5 hours".
String formatParkingHours(int hours) {
  if (hours <= 0) return '0 hours';
  final int days = hours ~/ 24;
  final int rest = hours % 24;
  final String dayText = '$days day${days == 1 ? '' : 's'}';
  final String hourText = '$rest hour${rest == 1 ? '' : 's'}';
  if (days == 0) return hourText;
  return rest == 0 ? dayText : '$dayText, $hourText';
}

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
