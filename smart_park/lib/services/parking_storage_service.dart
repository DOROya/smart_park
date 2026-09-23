import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ParkingStorageService {
  const ParkingStorageService();

  static const int maxPhotosPerEstablishment = 3;

  /// Uploads a facility photo to Storage and links it to the establishment doc.
  /// Returns the download URL on success, or null if the upload/update failed.
  Future<String?> uploadFacilityImage({
    required String establishmentId,
    required File imageFile,
  }) async {
    try {
      final Reference storageRef = FirebaseStorage.instance
          .ref()
          .child('establishments/$establishmentId.jpg');

      final UploadTask uploadTask = storageRef.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('establishments')
          .doc(establishmentId)
          .update(<String, dynamic>{'photoUrl': downloadUrl});

      print('ParkingStorageService: Uploaded and linked photoUrl for $establishmentId');
      return downloadUrl;
    } on FirebaseException catch (error) {
      print('ParkingStorageService: Firebase error (${error.code}): ${error.message}');
      return null;
    } catch (error) {
      print('ParkingStorageService: Unexpected error during upload: $error');
      return null;
    }
  }

  /// Uploads any [newImageFiles], combines them with [keepPhotoUrls] (capped
  /// to [maxPhotosPerEstablishment]), and writes the final list to
  /// `establishments/{establishmentId}.photoUrls` without touching other fields.
  /// Returns the final photo URL list, or null if the Firestore update failed.
  Future<List<String>?> uploadFacilityImages({
    required String establishmentId,
    required List<File> newImageFiles,
    List<String> keepPhotoUrls = const <String>[],
  }) async {
    final List<String> uploadedUrls = <String>[];

    for (int i = 0; i < newImageFiles.length; i++) {
      try {
        final int timestamp = DateTime.now().millisecondsSinceEpoch;
        final Reference storageRef = FirebaseStorage.instance.ref().child(
          'establishments/$establishmentId/photo_${timestamp}_$i.jpg',
        );

        final UploadTask uploadTask = storageRef.putFile(
          newImageFiles[i],
          SettableMetadata(contentType: 'image/jpeg'),
        );

        final TaskSnapshot snapshot = await uploadTask;
        final String downloadUrl = await snapshot.ref.getDownloadURL();
        uploadedUrls.add(downloadUrl);
      } on FirebaseException catch (error) {
        print('ParkingStorageService: Firebase error uploading photo $i (${error.code}): ${error.message}');
      } catch (error) {
        print('ParkingStorageService: Unexpected error uploading photo $i: $error');
      }
    }

    final List<String> finalUrls = <String>[
      ...keepPhotoUrls,
      ...uploadedUrls,
    ].take(maxPhotosPerEstablishment).toList();

    try {
      final Map<String, dynamic> updateData = <String, dynamic>{
        'photoUrls': finalUrls,
      };

      await FirebaseFirestore.instance
          .collection('establishments')
          .doc(establishmentId)
          .set(updateData, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('establishment_details')
          .doc(establishmentId)
          .set(updateData, SetOptions(merge: true))
          .catchError((_) {});

      print(
        'ParkingStorageService: Updated photoUrls (${finalUrls.length}) for $establishmentId',
      );
      return finalUrls;
    } on FirebaseException catch (error) {
      print(
        'ParkingStorageService: Firebase error updating photoUrls (${error.code}): ${error.message}',
      );
      return null;
    } catch (error) {
      print('ParkingStorageService: Unexpected error updating photoUrls: $error');
      return null;
    }
  }

  /// Lists and returns download URLs for any facility photos stored in Storage under
  /// `establishments/{establishmentId}/`.
  Future<List<String>> fetchStoragePhotoUrls(String establishmentId) async {
    try {
      final ListResult result = await FirebaseStorage.instance
          .ref('establishments/$establishmentId')
          .listAll();

      if (result.items.isEmpty) {
        return <String>[];
      }

      final List<String> urls = <String>[];
      for (final Reference ref in result.items) {
        final String url = await ref.getDownloadURL();
        urls.add(url);
      }
      return urls;
    } catch (error) {
      print('ParkingStorageService: Error listing storage photoUrls: $error');
      return <String>[];
    }
  }

  /// Best-effort delete of a photo from Storage by its download URL.
  /// Failures are logged only, since a missing/expired ref should not block saves.
  Future<void> deleteFacilityImage(String photoUrl) async {
    try {
      await FirebaseStorage.instance.refFromURL(photoUrl).delete();
      print('ParkingStorageService: Deleted photo at $photoUrl');
    } on FirebaseException catch (error) {
      print('ParkingStorageService: Firebase error deleting photo (${error.code}): ${error.message}');
    } catch (error) {
      print('ParkingStorageService: Unexpected error deleting photo: $error');
    }
  }
}
