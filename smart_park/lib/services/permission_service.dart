import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_theme.dart';

class PermissionService {
  const PermissionService();

  Future<bool> ensureDriverLocationPermission(BuildContext context) async {
    return _requestWithDialogs(
      context: context,
      permission: Permission.locationWhenInUse,
      featureName: 'Location Access',
      deniedMessage:
          'SmartPark needs your location to discover nearby parking spots.',
      permanentDeniedMessage:
          'Location access is blocked. Please enable it from app settings to continue GPS discovery.',
    );
  }

  Future<bool> ensureDriverStoragePermission(BuildContext context) async {
    // Android uses storage/media permissions, while iOS uses Photos for save actions.
    final Permission permission = Platform.isIOS
        ? Permission.photosAddOnly
        : Permission.storage;

    return _requestWithDialogs(
      context: context,
      permission: permission,
      featureName: 'Save Ticket',
      deniedMessage:
          'SmartPark needs storage access to save generated QR tickets on your device.',
      permanentDeniedMessage:
          'Storage access is blocked. Please enable it from app settings to save QR tickets.',
    );
  }

  Future<bool> ensureCameraPermissionForQr(BuildContext context) async {
    return _requestWithDialogs(
      context: context,
      permission: Permission.camera,
      featureName: 'QR Scanner',
      deniedMessage:
          'Camera access is needed to scan and validate parking QR tickets.',
      permanentDeniedMessage:
          'Camera access is blocked. Please enable it from app settings to use QR scanning.',
    );
  }

  Future<bool> _requestWithDialogs({
    required BuildContext context,
    required Permission permission,
    required String featureName,
    required String deniedMessage,
    required String permanentDeniedMessage,
  }) async {
    PermissionStatus status = await permission.status;
    if (status.isGranted || status.isLimited) {
      return true;
    }

    status = await permission.request();
    if (status.isGranted || status.isLimited) {
      return true;
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      if (!context.mounted) {
        return false;
      }

      final bool openSettings = await _showStyledDialog(
        context: context,
        title: '$featureName Permission Required',
        message: permanentDeniedMessage,
        primaryLabel: 'Open Settings',
        secondaryLabel: 'Cancel',
      );

      if (openSettings) {
        await openAppSettings();
      }
      return false;
    }

    if (!context.mounted) {
      return false;
    }

    final bool retry = await _showStyledDialog(
      context: context,
      title: '$featureName Permission Needed',
      message: deniedMessage,
      primaryLabel: 'Try Again',
      secondaryLabel: 'Not Now',
    );

    if (!retry) {
      return false;
    }

    final PermissionStatus retriedStatus = await permission.request();
    return retriedStatus.isGranted || retriedStatus.isLimited;
  }

  Future<bool> _showStyledDialog({
    required BuildContext context,
    required String title,
    required String message,
    required String primaryLabel,
    required String secondaryLabel,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                secondaryLabel,
                style: const TextStyle(color: Color(0xFF6E7483)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: const Color(0xFF22252C),
              ),
              child: Text(primaryLabel),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }
}
