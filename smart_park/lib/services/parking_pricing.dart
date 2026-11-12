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

/// PayMongo's smallest online payment, in pesos. Must match the check in
/// functions/src/checkout.js.
const double kMinOnlinePayment = 20;

/// The fewest units (succeeding hours, days, weeks or months) a plan needs
/// so its total reaches [kMinOnlinePayment], or null when the plan can't be
/// paid online at all (not offered, or still under the minimum at its
/// largest duration). `base` has no duration, so it's 1 or null.
///
/// A ₱10 two-hour motorcycle stay with ₱10 succeeding hours can't be paid
/// alone, but extended by 1 hour it is ₱20 for 3 hours.
int? minPackageDuration({required String plan, required VehicleRates rates}) {
  int? fewestUnits(double alreadyPaid, double perUnit) {
    if (perUnit <= 0) return null;
    // The tiny epsilon keeps float noise (2.0000000001) from adding a unit.
    final int needed = ((kMinOnlinePayment - alreadyPaid) / perUnit - 1e-9)
        .ceil();
    final int units = needed < 1 ? 1 : needed;
    return units <= (kMaxPackageDuration[plan] ?? 1) ? units : null;
  }

  return switch (plan) {
    'base' => rates.initial >= kMinOnlinePayment ? 1 : null,
    'extended' =>
      rates.initial > 0
          ? fewestUnits(rates.initial, rates.succeedingHour)
          : null,
    'daily' => fewestUnits(0, rates.succeedingDaily),
    'weekly' => fewestUnits(0, rates.weekly),
    'monthly' => fewestUnits(0, rates.monthly),
    _ => null,
  };
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

/// Hours a stay counts as: every started hour, by whole minutes (2h05m and
/// 2h15m are both 3 hours).
int stayHours(Duration elapsed) =>
    elapsed.inMinutes <= 0 ? 0 : (elapsed.inMinutes / 60).ceil();

/// Grace periods an owner can pick (`establishment_details
/// .gracePeriodMinutes`): minutes past the paid time a vehicle may still
/// leave without overtime.
const List<int> kGracePeriodOptions = <int>[0, 10, 15, 20, 25, 30];

/// For facilities whose owner hasn't picked one.
const int kDefaultGraceMinutes = 20;

/// The facility's grace period in minutes, from its `establishment_details`.
int facilityGraceMinutes(Map<String, dynamic>? details) {
  final Object? stored = details?['gracePeriodMinutes'];
  if (stored is! num) return kDefaultGraceMinutes;
  return stored.toInt().clamp(0, 60);
}

/// A grace period as an owner picks it: "20 minutes", or "None".
String graceOptionLabel(int minutes) =>
    minutes <= 0 ? 'None' : '$minutes minutes';

/// "20-minute grace period", or "no grace period".
String formatGracePeriod(int minutes) =>
    minutes <= 0 ? 'no grace period' : '$minutes-minute grace period';

/// Hours of a stay past the [paidHours] left on the ticket, billed as
/// overtime. Leaving within [graceMinutes] of the paid time is free; past
/// it, overtime counts from the end of the paid time, every started hour.
int overtimeHours(Duration elapsed, int paidHours, {int graceMinutes = 0}) {
  if (elapsed.inMinutes <= paidHours * 60 + graceMinutes) return 0;
  final int over = stayHours(elapsed) - paidHours;
  return over > 0 ? over : 0;
}

/// Whether a stay ran past its [paidHours] but left within the grace period.
bool withinGrace(Duration elapsed, int paidHours, {int graceMinutes = 0}) =>
    elapsed.inMinutes > paidHours * 60 &&
    overtimeHours(elapsed, paidHours, graceMinutes: graceMinutes) == 0;

/// Hours an exit takes off a ticket with [paidHours] left: the hours
/// stayed, at least the base stay, never more than what is left.
int hoursDeducted(Duration elapsed, int paidHours) {
  final int stayed = stayHours(elapsed);
  final int used = stayed < kBaseStayHours ? kBaseStayHours : stayed;
  return used < paidHours ? used : paidHours;
}

/// When overtime starts for a stay that began at [entryAt]: the first
/// minute past the [paidHours] left and the [graceMinutes] after them.
DateTime overtimeStartsAt(
  DateTime entryAt,
  int paidHours, {
  int graceMinutes = 0,
}) => entryAt.add(Duration(hours: paidHours, minutes: graceMinutes + 1));

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

/// Parking hours in words, always as hours so stays and tickets are easy to
/// compare and track (the capstone adviser's recommendation): 166 ->
/// "166 hours", 1 -> "1 hour", 1500 -> "1,500 hours".
String formatParkingHours(int hours) {
  final int h = hours < 0 ? 0 : hours;
  final String digits = '$h';
  final StringBuffer grouped = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '$grouped hour${h == 1 ? '' : 's'}';
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
