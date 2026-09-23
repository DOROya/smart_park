import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/facility_registration_data.dart';
import 'parking_storage_service.dart';

class EstablishmentRepository {
  const EstablishmentRepository({
    ParkingStorageService storageService = const ParkingStorageService(),
  }) : _storageService = storageService;

  final ParkingStorageService _storageService;

  CollectionReference<Map<String, dynamic>> get _establishments =>
      FirebaseFirestore.instance.collection('establishments');
  CollectionReference<Map<String, dynamic>> get _establishmentDetails =>
      FirebaseFirestore.instance.collection('establishment_details');

  DocumentReference<Map<String, dynamic>> _userRef(String ownerId) =>
      FirebaseFirestore.instance.collection('users').doc(ownerId);

  Future<String> saveFacility({
    required String ownerId,
    required Map<String, dynamic> ownerData,
    required FacilityRegistrationData formData,
    String? establishmentId,
  }) async {
    final bool isCreate = establishmentId == null;
    final String savedId =
        establishmentId ?? _establishments.doc().id;

    final Map<String, dynamic> establishmentPayload =
        formData.toEstablishmentFirestore(
      ownerId: ownerId,
      ownerData: ownerData,
      establishmentId: savedId,
    );
    final Map<String, dynamic> detailsPayload =
        formData.toEstablishmentDetailsFirestore(establishmentId: savedId);

    if (!isCreate) {
      detailsPayload
        ..remove('slots')
        ..remove('status')
        ..remove('rejectionReason')
        ..remove('reviewedAt')
        ..remove('reviewedBy');
    }

    final WriteBatch batch = FirebaseFirestore.instance.batch();

    final DocumentReference<Map<String, dynamic>> establishmentRef =
        _establishments.doc(savedId);
    final DocumentReference<Map<String, dynamic>> detailsRef =
        _establishmentDetails.doc(savedId);

    if (isCreate) {
      batch.set(establishmentRef, <String, dynamic>{
        ...establishmentPayload,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(detailsRef, <String, dynamic>{
        ...detailsPayload,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      batch.set(establishmentRef, establishmentPayload, SetOptions(merge: true));
      batch.set(detailsRef, detailsPayload, SetOptions(merge: true));
    }

    batch.set(_userRef(ownerId), <String, dynamic>{
      'establishmentId': savedId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();

    if (formData.newPhotoFiles.isNotEmpty || formData.keepPhotoUrls.isNotEmpty) {
      await _storageService.uploadFacilityImages(
        establishmentId: savedId,
        newImageFiles: formData.newPhotoFiles,
        keepPhotoUrls: formData.keepPhotoUrls,
      );
    }

    for (final String removedUrl in formData.removedPhotoUrls) {
      await _storageService.deleteFacilityImage(removedUrl);
    }

    return savedId;
  }
}
