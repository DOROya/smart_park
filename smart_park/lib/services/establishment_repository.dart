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

  /// Creates or updates a facility. On update, the review status is left
  /// untouched unless [FacilityRegistrationData.requiresReview] says the edit
  /// must be re-verified, in which case the facility goes back to `pending`.
  /// [failedDocumentUploads] counts picked documents that did not reach
  /// Storage, so the caller can tell the owner instead of failing silently.
  Future<
    ({
      String establishmentId,
      bool submittedForReview,
      int failedDocumentUploads,
    })
  >
  saveFacility({
    required String ownerId,
    required Map<String, dynamic> ownerData,
    required FacilityRegistrationData formData,
    String? establishmentId,
    String? previousStatus,
  }) async {
    final bool isCreate = establishmentId == null;
    final bool resubmit =
        !isCreate && formData.requiresReview(previousStatus: previousStatus);
    final String savedId = establishmentId ?? _establishments.doc().id;

    final Map<String, dynamic> establishmentPayload = formData
        .toEstablishmentFirestore(
          ownerId: ownerId,
          ownerData: ownerData,
          establishmentId: savedId,
        );
    final Map<String, dynamic> detailsPayload = formData
        .toEstablishmentDetailsFirestore(establishmentId: savedId);

    if (!isCreate) {
      detailsPayload.remove('slots');
      if (resubmit) {
        detailsPayload['resubmittedAt'] = FieldValue.serverTimestamp();
      } else {
        detailsPayload
          ..remove('status')
          ..remove('rejectionReason')
          ..remove('reviewedAt')
          ..remove('reviewedBy');
      }
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
      batch.set(
        establishmentRef,
        establishmentPayload,
        SetOptions(merge: true),
      );
      batch.set(detailsRef, detailsPayload, SetOptions(merge: true));
    }

    batch.set(_userRef(ownerId), <String, dynamic>{
      'establishmentId': savedId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();

    if (formData.newPhotoFiles.isNotEmpty ||
        formData.keepPhotoUrls.isNotEmpty) {
      await _storageService.uploadFacilityImages(
        establishmentId: savedId,
        newImageFiles: formData.newPhotoFiles,
        keepPhotoUrls: formData.keepPhotoUrls,
      );
    }

    for (final String removedUrl in formData.removedPhotoUrls) {
      await _storageService.deleteFacilityImage(removedUrl);
    }

    int failedDocumentUploads = 0;
    if (formData.newDocumentFiles.isNotEmpty ||
        formData.keepDocumentUrls.isNotEmpty) {
      final List<String>? savedDocumentUrls = await _storageService
          .uploadBusinessDocuments(
            establishmentId: savedId,
            newDocumentFiles: formData.newDocumentFiles,
            keepDocumentUrls: formData.keepDocumentUrls,
          );
      final int expectedCount =
          (formData.keepDocumentUrls.length + formData.newDocumentFiles.length)
              .clamp(0, ParkingStorageService.maxBusinessDocuments);
      failedDocumentUploads = savedDocumentUrls == null
          ? formData.newDocumentFiles.length
          : expectedCount - savedDocumentUrls.length;
    }

    for (final String removedUrl in formData.removedDocumentUrls) {
      await _storageService.deleteFacilityImage(removedUrl);
    }

    return (
      establishmentId: savedId,
      submittedForReview: isCreate || resubmit,
      failedDocumentUploads: failedDocumentUploads,
    );
  }
}
