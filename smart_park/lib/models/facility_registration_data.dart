import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/operating_hours.dart';
import '../services/parking_pricing.dart' show kDefaultGraceMinutes;

class FacilityRegistrationData {
  FacilityRegistrationData({
    required this.name,
    required this.address,
    required this.hours,
    required this.policies,
    required this.rates,
    required this.slots,
    required this.location,
    this.gracePeriodMinutes = kDefaultGraceMinutes,
    this.keepPhotoUrls = const <String>[],
    this.newPhotoFiles = const <File>[],
    this.removedPhotoUrls = const <String>[],
    this.keepDocumentUrls = const <String>[],
    this.newDocumentFiles = const <File>[],
    this.removedDocumentUrls = const <String>[],
    this.permitExpiresAt,
    this.previousPermitExpiresAt,
    this.contactNumber = '',
  });

  final String name;
  final String address;
  final OperatingHours hours;
  final String policies;

  /// Shown to drivers so they can call the facility; '' for none. Stored
  /// normalized (see facility_contact.dart).
  final String contactNumber;
  final Map<String, dynamic> rates;
  final Map<String, int> slots;
  final LatLng location;

  /// Minutes past the paid time a vehicle may leave without overtime.
  final int gracePeriodMinutes;
  final List<String> keepPhotoUrls;
  final List<File> newPhotoFiles;
  final List<String> removedPhotoUrls;
  final List<String> keepDocumentUrls;
  final List<File> newDocumentFiles;
  final List<String> removedDocumentUrls;

  /// The day the business permit among the documents lapses. Kept with the
  /// private documents (`establishment_private.permitExpiresAt`) so the
  /// admin sees it and the owner is reminded before it passes.
  final DateTime? permitExpiresAt;

  /// The expiry date saved before this edit; null for a new facility or
  /// one that never set it.
  final DateTime? previousPermitExpiresAt;

  /// A new expiry date counts as a document change: pushing it out stops
  /// the expiry reminders, so an admin checks it against the permit.
  bool get permitDateChanged {
    final DateTime? now = permitExpiresAt;
    final DateTime? was = previousPermitExpiresAt;
    if (now == null) return false;
    return was == null ||
        now.year != was.year ||
        now.month != was.month ||
        now.day != was.day;
  }

  bool get documentsChanged =>
      newDocumentFiles.isNotEmpty ||
      removedDocumentUrls.isNotEmpty ||
      permitDateChanged;

  /// Whether saving this edit must send the facility back to admin review:
  /// only when a rejected facility is resubmitted. An approved facility
  /// that changes its documents (e.g. a renewed permit) stays open; the
  /// admin is asked to check the new documents instead
  /// ([flagsDocumentCheck]) and suspends it if they're bad. Suspended and
  /// deactivated facilities keep their status: only an admin lifts those.
  bool requiresReview({required String? previousStatus}) =>
      (previousStatus ?? 'pending').toLowerCase() == 'rejected';

  /// Whether saving this edit asks an admin to check the documents again
  /// without taking the facility offline: they changed on a facility that
  /// was already reviewed (approved, suspended or deactivated). A suspended
  /// owner's new documents show up for the admin this way, to reinstate.
  bool flagsDocumentCheck({required String? previousStatus}) {
    final String status = (previousStatus ?? 'pending').toLowerCase();
    return documentsChanged &&
        (status == 'approved' ||
            status == 'suspended' ||
            status == 'deactivated');
  }

  int get availability =>
      slots.values.fold<int>(0, (int total, int item) => total + item);

  String _formatRateVal(dynamic val) {
    if (val is Map) {
      final String initial = (val['initial'] ?? val['hourly'] ?? '-')
          .toString();
      final String succHour = (val['succeedingHour'] ?? '').toString();
      final String succDaily = (val['succeedingDaily'] ?? val['daily'] ?? '')
          .toString();
      final String weekly = (val['weekly'] ?? '').toString();
      final String monthly = (val['monthly'] ?? '').toString();
      String text = initial;
      if (succHour.isNotEmpty) text += ' (+$succHour/hr)';
      if (succDaily.isNotEmpty) text += ' ($succDaily/day)';
      if (weekly.isNotEmpty) text += ' ($weekly/week)';
      if (monthly.isNotEmpty) text += ' ($monthly/month)';
      return text;
    }
    return (val ?? '-').toString();
  }

  String get rateSummary {
    return <String>[
      'Car: ${_formatRateVal(rates['car'])}',
      'Motorcycle: ${_formatRateVal(rates['motorcycle'])}',
      // A custom type, e.g. "Truck: ...".
      for (final String key in rates.keys)
        if (key != 'car' && key != 'motorcycle')
          '${key[0].toUpperCase()}${key.substring(1).replaceAll('_', ' ')}: '
              '${_formatRateVal(rates[key])}',
    ].join(', ');
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
      'contactNumber': contactNumber,
      'location': GeoPoint(location.latitude, location.longitude),
      'latitude': location.latitude,
      'longitude': location.longitude,
      ...hours.toFirestore(),
      'availability': availability,
    };
  }

  Map<String, dynamic> toEstablishmentDetailsFirestore({
    required String establishmentId,
  }) {
    // Car and motorcycle always, plus any custom type (e.g. truck).
    final Map<String, dynamic> normalizedSlots = <String, dynamic>{
      'car': slots['car'] ?? 0,
      'motorcycle': slots['motorcycle'] ?? 0,
      for (final MapEntry<String, int> e in slots.entries)
        if (e.key != 'car' && e.key != 'motorcycle') e.key: e.value,
    };

    return <String, dynamic>{
      'establishmentID': establishmentId,
      'rates': rates,
      'ratesByType': rates,
      'pricing': rateSummary,
      'slots': <String, dynamic>{'car': 0, 'motorcycle': 0},
      'slotCounts': normalizedSlots,
      'policies': policies,
      'gracePeriodMinutes': gracePeriodMinutes,
      'status': 'pending',
      'rejectionReason': null,
      'reviewedAt': null,
      'reviewedBy': null,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
