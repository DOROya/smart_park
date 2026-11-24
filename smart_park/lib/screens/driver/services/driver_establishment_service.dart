import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/facility_closure.dart';
import '../../../services/operating_hours.dart';

/// How the driver's parking list is ordered. [none] is nearest first when
/// the driver's location is known.
enum DriverSortOption {
  none('Nearest', Icons.near_me_rounded),
  nearest('Nearest', Icons.near_me_rounded),
  cheapest('Cheapest', Icons.payments_outlined),
  topRated('Top rated', Icons.star_outline_rounded),
  mostSlots('Most slots', Icons.local_parking_rounded);

  const DriverSortOption(this.label, this.icon);

  final String label;
  final IconData icon;
}

class DriverEstablishmentService {
  const DriverEstablishmentService._();

  /// Lowest base rate (the first hours) across the facility's vehicle types,
  /// or null if it has none on record.
  static double? startingPrice(Map<String, dynamic> data) {
    final Object? rawRates = data['rates'] ?? data['ratesByType'];
    final Map<dynamic, dynamic> rates = rawRates is Map
        ? rawRates
        : <dynamic, dynamic>{};
    double? lowest;
    for (final dynamic value in rates.values) {
      final dynamic raw = value is Map
          ? (value['initial'] ?? value['hourly'])
          : value;
      final double? price = double.tryParse('${raw ?? ''}'.trim());
      if (price != null && price > 0 && (lowest == null || price < lowest)) {
        lowest = price;
      }
    }
    if (lowest != null) return lowest;
    final Match? match = RegExp(
      r'\d+(?:\.\d+)?',
    ).firstMatch((data['pricing'] as String?) ?? '');
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  /// Total slots across vehicle types, from `slotCounts` (kept up to date by
  /// the owner), else the count given at registration.
  static int capacity(Map<String, dynamic> data) {
    final Object? counts = data['slotCounts'];
    if (counts is Map) {
      int total = 0;
      for (final MapEntry<dynamic, dynamic> e in counts.entries) {
        if (e.key == 'motor') continue; // legacy duplicate of motorcycle
        if (e.value is num && (e.value as num) > 0) {
          total += (e.value as num).toInt();
        }
      }
      if (total > 0) return total;
    }
    return ((data['availability'] as num?) ?? 0).toInt();
  }

  /// Whether the facility has slots for [vehicleType] ("car", "motorcycle",
  /// or a custom type key).
  static bool takesVehicle(Map<String, dynamic> data, String vehicleType) {
    final Object? counts = data['slotCounts'];
    if (counts is! Map) return false;
    final Object? slots =
        counts[vehicleType] ??
        (vehicleType == 'motorcycle' ? counts['motor'] : null);
    return slots is num && slots > 0;
  }

  /// A Google Maps route from the driver's location to the facility, or
  /// null when it has neither a pin nor an address.
  static Uri? directionsUri(Map<String, dynamic> data) {
    final LatLng? point = extractLatLng(data);
    final String address = ((data['address'] as String?) ?? '').trim();
    final String destination = point != null
        ? '${point.latitude},${point.longitude}'
        : Uri.encodeComponent(address);
    if (destination.isEmpty) return null;
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$destination&travelmode=driving',
    );
  }

  /// Opens [directionsUri] in Google Maps (or the browser). Returns false
  /// when there is no location or nothing could open it.
  static Future<bool> openDirections(Map<String, dynamic> data) async {
    final Uri? uri = directionsUri(data);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static const LatLng fallbackCenter = LatLng(14.5995, 120.9842);

  static LatLng? extractLatLng(Map<String, dynamic> data) {
    final dynamic locationValue = data['location'];
    final GeoPoint? geoPoint = locationValue is GeoPoint ? locationValue : null;
    final Map<String, dynamic>? locationMap = locationValue is Map
        ? locationValue.map<String, dynamic>(
            (dynamic key, dynamic value) => MapEntry(key.toString(), value),
          )
        : null;
    final num? latitudeValue = data['latitude'] as num?;
    final num? longitudeValue = data['longitude'] as num?;

    final double? latitude =
        geoPoint?.latitude ??
        (locationMap?['latitude'] as num?)?.toDouble() ??
        latitudeValue?.toDouble();
    final double? longitude =
        geoPoint?.longitude ??
        (locationMap?['longitude'] as num?)?.toDouble() ??
        longitudeValue?.toDouble();
    if (latitude == null || longitude == null) {
      return null;
    }
    return LatLng(latitude, longitude);
  }

  static double distanceToUserMeters({
    required Map<String, dynamic> establishment,
    required Position? currentPosition,
  }) {
    final LatLng? point = extractLatLng(establishment);
    if (point == null || currentPosition == null) {
      return double.infinity;
    }

    return Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      point.latitude,
      point.longitude,
    );
  }

  /// Open by its hours and not closed temporarily (the merged data carries
  /// the details' `closedUntil`).
  static bool isOpenNow(Map<String, dynamic> establishment) => hoursWithClosure(
    OperatingHours.parse(establishment),
    establishment,
  ).isOpenAt(DateTime.now());

  /// "Closed until Nov 25, 3:00 PM" while closed temporarily, else null.
  static String? closedUntilLabel(Map<String, dynamic> establishment) {
    final TemporaryClosure? closure = TemporaryClosure.of(establishment);
    if (closure == null || !closure.isActiveAt(DateTime.now())) return null;
    return 'Closed until ${temporaryClosureUntilLabel(closure)}';
  }

  /// The list the driver sees. [vehicleType] keeps only facilities with
  /// slots for it; [onlyIds] (the driver's saved facilities) keeps only
  /// those. Ties in a sort fall back to the nearest first.
  static List<Map<String, dynamic>> filterAndSort({
    required List<Map<String, dynamic>> establishments,
    required String searchQuery,
    required bool openNowOnly,
    required DriverSortOption sortOption,
    required Position? currentPosition,
    String? vehicleType,
    Set<String>? onlyIds,
  }) {
    final String query = searchQuery.trim().toLowerCase();

    final List<Map<String, dynamic>> filtered = query.isEmpty
        ? List<Map<String, dynamic>>.from(establishments)
        : establishments.where((Map<String, dynamic> data) {
            final String name = ((data['name'] as String?) ?? '').toLowerCase();
            final String address = ((data['address'] as String?) ?? '')
                .toLowerCase();
            return name.contains(query) || address.contains(query);
          }).toList();

    final List<Map<String, dynamic>> displayed = filtered.where((
      Map<String, dynamic> establishment,
    ) {
      if (openNowOnly && !isOpenNow(establishment)) return false;
      if (vehicleType != null && !takesVehicle(establishment, vehicleType)) {
        return false;
      }
      if (onlyIds != null &&
          !onlyIds.contains(establishment['establishmentID'])) {
        return false;
      }
      return true;
    }).toList();

    int nearer(Map<String, dynamic> a, Map<String, dynamic> b) =>
        distanceToUserMeters(
          establishment: a,
          currentPosition: currentPosition,
        ).compareTo(
          distanceToUserMeters(
            establishment: b,
            currentPosition: currentPosition,
          ),
        );

    switch (sortOption) {
      case DriverSortOption.none:
        // Nearest first is applied by the caller when location is known.
        break;
      case DriverSortOption.nearest:
        displayed.sort(nearer);
      case DriverSortOption.cheapest:
        // Facilities without a rate on record go last.
        displayed.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
          final double pa = startingPrice(a) ?? double.infinity;
          final double pb = startingPrice(b) ?? double.infinity;
          final int byPrice = pa.compareTo(pb);
          return byPrice != 0 ? byPrice : nearer(a, b);
        });
      case DriverSortOption.topRated:
        // Unrated facilities go last; more ratings win a tie.
        displayed.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
          final double ra = ((a['rating'] as num?) ?? 0).toDouble();
          final double rb = ((b['rating'] as num?) ?? 0).toDouble();
          final int byRating = rb.compareTo(ra);
          if (byRating != 0) return byRating;
          final int ca = ((a['ratingCount'] as num?) ?? 0).toInt();
          final int cb = ((b['ratingCount'] as num?) ?? 0).toInt();
          final int byCount = cb.compareTo(ca);
          return byCount != 0 ? byCount : nearer(a, b);
        });
      case DriverSortOption.mostSlots:
        displayed.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
          final int bySlots = capacity(b).compareTo(capacity(a));
          return bySlots != 0 ? bySlots : nearer(a, b);
        });
    }

    return displayed;
  }

  static Set<Marker> buildMarkers({
    required List<Map<String, dynamic>> establishments,
    required void Function(String establishmentId) onTap,
  }) {
    return establishments
        .map((Map<String, dynamic> data) {
          final LatLng? location = extractLatLng(data);
          final String establishmentId =
              (data['establishmentID'] as String?) ?? '';
          if (location == null) {
            return null;
          }
          if (establishmentId.isEmpty) {
            return null;
          }

          return Marker(
            markerId: MarkerId(establishmentId),
            position: location,
            infoWindow: InfoWindow(
              title: (data['name'] as String?) ?? 'Parking Establishment',
              snippet: (data['address'] as String?) ?? 'Address not available',
            ),
            onTap: () => onTap(establishmentId),
          );
        })
        .whereType<Marker>()
        .toSet();
  }

  static Set<Circle> buildUserLocationCircle(Position? currentPosition) {
    if (currentPosition == null) {
      return <Circle>{};
    }

    return <Circle>{
      Circle(
        circleId: const CircleId('user_location_radius'),
        center: LatLng(currentPosition.latitude, currentPosition.longitude),
        radius: currentPosition.accuracy < 30 ? 30 : currentPosition.accuracy,
        strokeWidth: 2,
        strokeColor: const Color(0xFF1E88E5),
        fillColor: const Color(0x441E88E5),
      ),
    };
  }
}
