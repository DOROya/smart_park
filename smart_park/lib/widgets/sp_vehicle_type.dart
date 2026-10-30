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

String spVehicleTypeLabel(String key) => switch (key) {
  'car' => 'Car',
  'motorcycle' => 'Motorcycle',
  '' => 'Vehicle',
  _ => '${key[0].toUpperCase()}${key.substring(1)}',
};

IconData spVehicleTypeIcon(String key) => key == 'motorcycle'
    ? Icons.two_wheeler_rounded
    : Icons.directions_car_rounded;

/// Fill and text colors, one pair per type. Fixed (not theme) colors so a
/// motorcycle looks the same on every gate phone, and neither is the green
/// or red of an allowed or denied scan.
(Color, Color) spVehicleTypeColors(String key) => switch (key) {
  'motorcycle' => (AppTheme.accent, AppTheme.onAccent),
  'car' => (const Color(0xFF2563EB), Colors.white),
  _ => (AppTheme.textDark, AppTheme.onInk),
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
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
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
          Icon(spVehicleTypeIcon(key), color: text, size: large ? 34 : 18),
          SizedBox(width: large ? 10 : 6),
          Flexible(
            child: Text(
              spVehicleTypeLabel(key).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: text,
                fontSize: large ? 24 : 13,
                fontWeight: FontWeight.w900,
                letterSpacing: large ? 1.2 : 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
