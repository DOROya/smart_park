import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum DriverSortOption { none, nearest, mostSlots }

class DriverEstablishmentService {
  const DriverEstablishmentService._();

  static const LatLng fallbackCenter = LatLng(14.5995, 120.9842);

  static LatLng? extractLatLng(Map<String, dynamic> data) {
    final dynamic locationValue = data['location'];
    final GeoPoint? geoPoint = locationValue is GeoPoint
      ? locationValue
      : null;
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

  static bool isOpenNow(Map<String, dynamic> establishment) {
    final String hours = ((establishment['operatingHours'] as String?) ?? '')
        .trim();
    if (hours.isEmpty) {
      return false;
    }

    final String lower = hours.toLowerCase();
    if (lower.contains('24') || lower.contains('open 24')) {
      return true;
    }

    final List<String> parts = hours.split('-');
    if (parts.length != 2) {
      return false;
    }

    final int? openMinutes = _parseTimeToMinutes(parts[0].trim());
    final int? closeMinutes = _parseTimeToMinutes(parts[1].trim());
    if (openMinutes == null || closeMinutes == null) {
      return false;
    }

    final DateTime now = DateTime.now();
    final int nowMinutes = now.hour * 60 + now.minute;

    if (openMinutes == closeMinutes) {
      return true;
    }

    if (openMinutes < closeMinutes) {
      return nowMinutes >= openMinutes && nowMinutes < closeMinutes;
    }

    return nowMinutes >= openMinutes || nowMinutes < closeMinutes;
  }

  static int? _parseTimeToMinutes(String raw) {
    final RegExp match = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*([AaPp][Mm])$');
    final Match? m = match.firstMatch(raw);
    if (m == null) {
      return null;
    }

    int hour = int.tryParse(m.group(1) ?? '') ?? -1;
    final int minute = int.tryParse(m.group(2) ?? '0') ?? 0;
    final String suffix = (m.group(3) ?? '').toUpperCase();

    if (hour < 1 || hour > 12 || minute < 0 || minute > 59) {
      return null;
    }

    hour = hour % 12;
    if (suffix == 'PM') {
      hour += 12;
    }

    return hour * 60 + minute;
  }

  static List<Map<String, dynamic>> filterAndSort({
    required List<Map<String, dynamic>> establishments,
    required String searchQuery,
    required bool openNowOnly,
    required DriverSortOption sortOption,
    required Position? currentPosition,
  }) {
    final String query = searchQuery.trim().toLowerCase();

    final List<Map<String, dynamic>> filtered =
        query.isEmpty
        ? List<Map<String, dynamic>>.from(establishments)
        : establishments.where((Map<String, dynamic> data) {
            final String name = ((data['name'] as String?) ?? '').toLowerCase();
            final String address = ((data['address'] as String?) ?? '')
                .toLowerCase();
            return name.contains(query) || address.contains(query);
          }).toList();

    final List<Map<String, dynamic>> displayed = filtered
        .where((Map<String, dynamic> establishment) {
          if (!openNowOnly) {
            return true;
          }
          return isOpenNow(establishment);
        })
        .toList();

    if (sortOption == DriverSortOption.nearest) {
      displayed.sort((
        Map<String, dynamic> a,
        Map<String, dynamic> b,
      ) {
        return distanceToUserMeters(
          establishment: a,
          currentPosition: currentPosition,
        ).compareTo(
          distanceToUserMeters(
            establishment: b,
            currentPosition: currentPosition,
          ),
        );
      });
    } else if (sortOption == DriverSortOption.mostSlots) {
      displayed.sort((
        Map<String, dynamic> a,
        Map<String, dynamic> b,
      ) {
        final int aSlots = ((a['availability'] as num?) ?? 0).toInt();
        final int bSlots = ((b['availability'] as num?) ?? 0).toInt();
        return bSlots.compareTo(aSlots);
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
