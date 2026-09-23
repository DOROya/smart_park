import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FacilityRegistrationData {
  FacilityRegistrationData({
    required this.name,
    required this.address,
    required this.operatingHours,
    required this.policies,
    required this.rates,
    required this.slots,
    required this.location,
    this.keepPhotoUrls = const <String>[],
    this.newPhotoFiles = const <File>[],
    this.removedPhotoUrls = const <String>[],
  });

  final String name;
  final String address;
  final String operatingHours;
  final String policies;
  final Map<String, dynamic> rates;
  final Map<String, int> slots;
  final LatLng location;
  final List<String> keepPhotoUrls;
  final List<File> newPhotoFiles;
  final List<String> removedPhotoUrls;

  int get availability =>
      slots.values.fold<int>(0, (int total, int item) => total + item);

  String _formatRateVal(dynamic val) {
    if (val is Map) {
      final String initial = (val['initial'] ?? val['hourly'] ?? '-').toString();
      final String succHour = (val['succeedingHour'] ?? '').toString();
      final String succDaily = (val['succeedingDaily'] ?? val['daily'] ?? '').toString();
      String text = initial;
      if (succHour.isNotEmpty) text += ' (+$succHour/hr)';
      if (succDaily.isNotEmpty) text += ' ($succDaily/day)';
      return text;
    }
    return (val ?? '-').toString();
  }

  String get rateSummary {
    return 'Car: ${_formatRateVal(rates['car'])}, '
        'Motorcycle: ${_formatRateVal(rates['motorcycle'])}';
  }

  Map<String, dynamic> toEstablishmentFirestore({
    required String ownerId,
    required Map<String, dynamic> ownerData,
    required String establishmentId,
  }) {
    return <String, dynamic>{
      'establishmentID': establishmentId,
      'ownerId': ownerId,
      'ownerFirstName': (ownerData['firstName'] as String?) ?? '',
      'ownerLastName': (ownerData['lastName'] as String?) ?? '',
      'ownerEmail': (ownerData['email'] as String?) ?? '',
      'name': name,
      'address': address,
      'location': GeoPoint(location.latitude, location.longitude),
      'latitude': location.latitude,
      'longitude': location.longitude,
      'operatingHours': operatingHours,
      'availability': availability,
    };
  }

  Map<String, dynamic> toEstablishmentDetailsFirestore({
    required String establishmentId,
  }) {
    final Map<String, dynamic> normalizedSlots = <String, dynamic>{
      'car': slots['car'] ?? 0,
      'motorcycle': slots['motorcycle'] ?? 0,
    };

    return <String, dynamic>{
      'establishmentID': establishmentId,
      'rates': rates,
      'ratesByType': rates,
      'pricing': rateSummary,
      'slots': <String, dynamic>{
        'car': 0,
        'motorcycle': 0,
      },
      'slotCounts': normalizedSlots,
      'policies': policies,
      'status': 'pending',
      'rejectionReason': null,
      'reviewedAt': null,
      'reviewedBy': null,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
