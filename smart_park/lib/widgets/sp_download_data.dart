import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/error_reporter.dart';
import '../services/local_save.dart';
import '../utils/friendly_error.dart';
import 'smartpark_ui.dart';
import 'sp_export_sheet.dart';

/// File name of a data export made on [date], e.g.
/// `smartpark-my-data-2026-11-22.json`.
String spDataExportFileName(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'smartpark-my-data-${date.year}-${two(date.month)}-${two(date.day)}'
      '.json';
}

/// The server's export, as the indented JSON saved to the phone.
Uint8List spDataExportBytes(Object? export) {
  return Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(export)),
  );
}

/// Profile card that saves a copy of the personal data SmartPark keeps about
/// the signed-in user (their right of access under the Data Privacy Act),
/// as a JSON file in Downloads. Built by the exportMyData Cloud Function.
class SpDownloadDataCard extends StatefulWidget {
  const SpDownloadDataCard({super.key});

  @override
  State<SpDownloadDataCard> createState() => _SpDownloadDataCardState();
}

class _SpDownloadDataCardState extends State<SpDownloadDataCard> {
  bool _working = false;

  Future<void> _download() async {
    setState(() => _working = true);
    try {
      final HttpsCallableResult<dynamic> result =
          await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
              .httpsCallable(
                'exportMyData',
                options: HttpsCallableOptions(
                  timeout: const Duration(seconds: 120),
                ),
              )
              .call<dynamic>();
      final String name = spDataExportFileName(DateTime.now());
      final bool saved = await saveFileToDevice(
        bytes: spDataExportBytes(result.data),
        fileName: name,
        mimeType: 'application/json',
      );
      if (saved && mounted) {
        showSpSaveResult(
          context,
          saved: 'Saved $name to $kDownloadsFolderLabel.',
        );
      }
    } on FirebaseFunctionsException catch (error, stack) {
      if (error.code != 'resource-exhausted') {
        reportError(error, stack, reason: 'data export');
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                error.code == 'resource-exhausted'
                    ? (error.message ?? 'Try again in a minute.')
                    : friendlyError(
                        error,
                        fallback: 'Could not get your data. Please try again.',
                      ),
              ),
            ),
          );
      }
    } catch (error, stack) {
      if (error is! StorageAccessDenied) {
        reportError(error, stack, reason: 'data export');
      }
      if (mounted) {
        showSpSaveResult(
          context,
          saved: '',
          error: error,
          failed: 'Could not save your data. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SpSectionCard(
      icon: Icons.download_for_offline_outlined,
      title: 'Your Data',
      subtitle:
          'Save a copy of the personal data SmartPark keeps about you: '
          'your profile, tickets, payments and reports, as one file.',
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _working ? null : _download,
          icon: _working
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_rounded, size: 18),
          label: Text(
            _working ? 'Preparing your data...' : 'Download My Data',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
        ),
      ),
    );
  }
}
