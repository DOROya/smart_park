/// Saving exported files on the device, as opposed to sharing them.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

/// Album the app's images go into in the gallery.
const String kGalleryAlbum = 'SmartPark';

/// Where [saveFileToDevice] puts files on Android, as the user sees it.
const String kDownloadsFolderLabel = 'Downloads > SmartPark';

const MethodChannel _downloads = MethodChannel('smartpark/downloads');

/// Saves a PNG to the phone's gallery, in the SmartPark album. Throws
/// [StorageAccessDenied] if the user refuses photo access.
Future<void> saveImageToGallery(Uint8List png) async {
  if (!await Gal.hasAccess(toAlbum: true) &&
      !await Gal.requestAccess(toAlbum: true)) {
    throw const StorageAccessDenied();
  }
  await Gal.putImageBytes(png, album: kGalleryAlbum);
}

/// Saves [bytes] as [fileName] in the phone's Downloads/SmartPark folder
/// and returns true. iOS has no shared Downloads folder, so there it opens
/// the share sheet (which offers "Save to Files") and returns false.
/// Throws [StorageAccessDenied] if an older Android refuses storage access.
Future<bool> saveFileToDevice({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  if (!Platform.isAndroid) {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile.fromData(bytes, mimeType: mimeType, name: fileName),
        ],
        fileNameOverrides: <String>[fileName],
      ),
    );
    return false;
  }
  Future<void> save() => _downloads.invokeMethod<String>(
    'save',
    <String, Object>{'name': fileName, 'mime': mimeType, 'bytes': bytes},
  );
  try {
    await save();
  } on PlatformException catch (e) {
    // Android 9 and older need the storage permission to write Downloads.
    if (e.code != 'no_permission') rethrow;
    if (!(await Permission.storage.request()).isGranted) {
      throw const StorageAccessDenied();
    }
    await save();
  }
  return true;
}

/// The user refused the photo or storage access a save needs.
class StorageAccessDenied implements Exception {
  const StorageAccessDenied();

  @override
  String toString() => 'Storage access was denied.';
}
