import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../services/plate_reader.dart';
import '../theme/app_theme.dart';
import '../services/ticket_plate.dart' show normalizePlate;
import 'smartpark_ui.dart';

/// Reads a plate from a still photo, on the phone, with no internet.
/// Returns the text lines it found (empty when the photo was cancelled).
typedef PlateTextReader = Future<List<String>?> Function();

/// Takes a photo with the camera and runs ML Kit text recognition on it.
Future<List<String>?> readPlateTextFromCamera() async {
  final XFile? photo = await ImagePicker().pickImage(
    source: ImageSource.camera,
    preferredCameraDevice: CameraDevice.rear,
    maxWidth: 1600,
    imageQuality: 85,
  );
  if (photo == null) return null;
  final TextRecognizer recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  try {
    final RecognizedText text = await recognizer.processImage(
      InputImage.fromFilePath(photo.path),
    );
    return <String>[
      for (final TextBlock block in text.blocks)
        for (final TextLine line in block.lines) line.text,
    ];
  } finally {
    await recognizer.close();
  }
}

/// A camera button beside a plate field. The QR scanner holds the camera,
/// so [pauseScanner] stops it while the photo is taken and [resumeScanner]
/// starts it again. The plate is only filled after staff tap or edit it.
class SpReadPlateButton extends StatelessWidget {
  const SpReadPlateButton({
    super.key,
    required this.onPlate,
    this.knownPlates,
    this.pauseScanner,
    this.resumeScanner,
    this.reader = readPlateTextFromCamera,
  });

  final ValueChanged<String> onPlate;

  /// Plates the facility knows now (vehicles inside), ranked first.
  final Future<List<String>> Function()? knownPlates;
  final Future<void> Function()? pauseScanner;
  final Future<void> Function()? resumeScanner;
  final PlateTextReader reader;

  Future<void> _read(BuildContext context) async {
    try {
      await pauseScanner?.call();
    } catch (_) {
      // The photo still works if the scanner was already off.
    }
    try {
      if (!context.mounted) return;
      final String? plate = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            ReadPlateSheet(reader: reader, knownPlates: knownPlates),
      );
      if (plate != null && plate.trim().isNotEmpty) onPlate(plate);
    } finally {
      try {
        await resumeScanner?.call();
      } catch (_) {
        // Restarted when the Scanner tab is shown again.
      }
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Read plate with camera',
    onPressed: () => _read(context),
    icon: const Icon(Icons.photo_camera_outlined),
  );
}

/// Takes the photo, then shows the best guess large with up to two others,
/// editable before it is used. Pops the chosen plate, or nothing.
class ReadPlateSheet extends StatefulWidget {
  const ReadPlateSheet({super.key, required this.reader, this.knownPlates});

  final PlateTextReader reader;
  final Future<List<String>> Function()? knownPlates;

  @override
  State<ReadPlateSheet> createState() => _ReadPlateSheetState();
}

class _ReadPlateSheetState extends State<ReadPlateSheet> {
  final TextEditingController _plate = TextEditingController();
  List<String> _candidates = const <String>[];
  bool _reading = true;
  bool _cancelled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_take());
  }

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    setState(() {
      _reading = true;
      _error = null;
      _cancelled = false;
    });
    try {
      final List<String>? lines = await widget.reader();
      if (!mounted) return;
      if (lines == null) {
        setState(() {
          _reading = false;
          _cancelled = true;
        });
        return;
      }
      List<String> known = const <String>[];
      try {
        known = await widget.knownPlates?.call() ?? const <String>[];
      } catch (_) {
        known = const <String>[];
      }
      final List<String> found = plateCandidates(lines, knownPlates: known);
      if (!mounted) return;
      setState(() {
        _reading = false;
        _candidates = found;
        _plate.text = found.isEmpty ? '' : found.first;
        _error = found.isEmpty
            ? 'Couldn\'t read a plate. Try again closer, or type it.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _error = 'Couldn\'t read the photo. Try again, or type the plate.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Read plate',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Check it against the plate before using it. Glare, dirt and '
              'angles cause misreads.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            if (_reading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...<Widget>[
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: spDeniedColor)),
                ),
              if (_candidates.length > 1)
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final String c in _candidates)
                      ChoiceChip(
                        label: Text(c),
                        selected: _plate.text == c,
                        onSelected: (_) => setState(() => _plate.text = c),
                      ),
                  ],
                ),
              if (_candidates.isNotEmpty || _error != null) ...<Widget>[
                const SizedBox(height: 12),
                TextField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'ABC 1234',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _take,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _cancelled ? 'Take photo' : 'Try again',
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: normalizePlate(_plate.text).isEmpty
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(normalizePlate(_plate.text)),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Use this plate', maxLines: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
