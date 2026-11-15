import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A ticket is bought for one vehicle type and may be shared, but only for
/// that type, so the type is shown wherever the ticket is: on the driver's
/// QR, at purchase, and on the gate result where staff check it by eye.

/// "car" or "motorcycle" for a ticket's `vehicleType`. Tickets without one
/// count as cars, as the exit scan bills them.
String spVehicleTypeKey(Object? raw) {
  final String type = raw is String ? raw.trim().toLowerCase() : '';
  return type.isEmpty ? 'car' : type;
}

/// The two types every facility has; an owner may add one more (a truck,
/// say), stored under its own key in `slotCounts` and `ratesByType`.
const List<String> kStandardVehicleKeys = <String>['car', 'motorcycle'];

/// "Truck" -> "truck", "Mini Bus" -> "mini_bus": the key a custom vehicle
/// type is stored under.
String spCustomVehicleKey(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), '_')
    .replaceAll(RegExp(r'[^a-z0-9_]'), '');

/// "car" -> "Car", "mini_bus" -> "Mini Bus".
String spVehicleTypeLabel(String key) => switch (key) {
  'car' => 'Car',
  'motorcycle' => 'Motorcycle',
  '' => 'Vehicle',
  _ =>
    key
        .split('_')
        .where((String w) => w.isNotEmpty)
        .map((String w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' '),
};

/// Car and motorcycle icons; for a custom type, an icon guessed from its
/// name (a truck, bus, van, bicycle...), else a neutral one.
IconData spVehicleTypeIcon(String key) {
  if (key == 'car') return Icons.directions_car_rounded;
  if (key == 'motorcycle' || key == 'motor') return Icons.two_wheeler_rounded;
  bool has(List<String> words) => words.any(key.contains);
  if (has(<String>['truck', 'lorry', 'cargo'])) {
    return Icons.local_shipping_rounded;
  }
  if (has(<String>['bus', 'jeep', 'coaster'])) {
    return Icons.directions_bus_rounded;
  }
  if (has(<String>['van', 'shuttle'])) return Icons.airport_shuttle_rounded;
  if (has(<String>['ebike', 'e_bike', 'scooter'])) {
    return Icons.electric_bike_rounded;
  }
  if (has(<String>['bicycle', 'bike'])) return Icons.pedal_bike_rounded;
  if (has(<String>['tricycle', 'trike'])) {
    return Icons.electric_rickshaw_rounded;
  }
  return Icons.commute_rounded;
}

/// Vehicle types a facility takes: car and motorcycle, then any custom type
/// the owner added (one with slots).
List<String> spFacilityVehicleKeys(Object? slotCounts) => <String>[
  ...kStandardVehicleKeys,
  if (slotCounts is Map)
    for (final MapEntry<dynamic, dynamic> e in slotCounts.entries)
      if (e.key is String &&
          !kStandardVehicleKeys.contains(e.key) &&
          e.key != 'motor' &&
          (e.value is num) &&
          (e.value as num) > 0)
        e.key as String,
];

/// Slots of the custom types only, e.g. {truck: 2}.
Map<String, int> spOtherVehicleSlots(Object? slotCounts) => <String, int>{
  for (final String key in spFacilityVehicleKeys(slotCounts))
    if (!kStandardVehicleKeys.contains(key))
      key: (((slotCounts as Map)[key] as num?) ?? 0).toInt(),
};

/// Fill and text colors, one pair per type. Fixed (not theme) colors so a
/// motorcycle looks the same on every gate phone, and neither is the green
/// or red of an allowed or denied scan.
(Color, Color) spVehicleTypeColors(String key) => switch (key) {
  'motorcycle' => (AppTheme.accent, AppTheme.onAccent),
  'car' => (const Color(0xFF2563EB), Colors.white),
  '' => (AppTheme.textDark, AppTheme.onInk),
  _ => (const Color(0xFF7C3AED), Colors.white),
};

/// The sharing rule as drivers read it at purchase and on the ticket, for a
/// vehicle label such as "Motorcycle".
String spTicketSharingRule(String vehicleLabel) =>
    'This ticket is for a ${vehicleLabel.toUpperCase()}. It can be shared, '
    'but only for the same vehicle type. The account that bought it is '
    'responsible for its use.';

/// The vehicle type as a solid block: icon and upper-case label.
class SpVehicleTypeBadge extends StatelessWidget {
  const SpVehicleTypeBadge({
    super.key,
    required this.vehicleType,
    this.large = false,
  });

  /// A ticket's `vehicleType`, as stored.
  final Object? vehicleType;

  /// The gate result's size, readable at arm's length.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final String key = spVehicleTypeKey(vehicleType);
    final (Color fill, Color text) = spVehicleTypeColors(key);
    return Container(
      padding: large
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(
          large ? AppTheme.radius : AppTheme.radiusSmall,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spVehicleTypeIcon(key), color: text, size: large ? 30 : 18),
          SizedBox(width: large ? 8 : 6),
          // Shrinks rather than cut off: a half-read type is no use.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                spVehicleTypeLabel(key).toUpperCase(),
                maxLines: 1,
                style: TextStyle(
                  color: text,
                  fontSize: large ? 22 : 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
