/// Picks Philippine plate numbers out of text read from a photo (ML Kit's
/// on-device text recognition). Reading is never sure: glare, dirt, angles
/// and frame text mislead it, and it confuses 0/O, 1/I, 8/B, 5/S and 2/Z.
/// So these are only suggestions for staff to confirm, never saved alone.
/// The plate patterns live here so they can be tuned.
library;

/// One way a plate is written, e.g. 3 letters then 3-4 digits.
class _PlateShape {
  const _PlateShape(this.letters, this.digits, {this.lettersFirst = true});

  /// Allowed letter count range and digit count range.
  final (int, int) letters;
  final (int, int) digits;
  final bool lettersFirst;
}

/// Most likely first. Cars: ABC 1234 (newer) and ABC 123 (older).
/// Motorcycles: 123 ABC, AB 12345, AB 1234.
const List<_PlateShape> _shapes = <_PlateShape>[
  _PlateShape((3, 3), (4, 4)),
  _PlateShape((3, 3), (3, 3)),
  _PlateShape((3, 3), (3, 3), lettersFirst: false),
  _PlateShape((2, 2), (4, 5)),
  _PlateShape((2, 3), (2, 5)),
];

const Map<String, String> _toLetter = <String, String>{
  '0': 'O',
  '1': 'I',
  '8': 'B',
  '5': 'S',
  '2': 'Z',
  '6': 'G',
};
const Map<String, String> _toDigit = <String, String>{
  'O': '0',
  'Q': '0',
  'D': '0',
  'I': '1',
  'L': '1',
  'B': '8',
  'S': '5',
  'Z': '2',
  'G': '6',
};

/// Uppercase letters and digits only.
String _clean(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// "ABC1234" as "ABC 1234" (letters and digits apart).
String formatPlate(String compact) {
  final Match? m =
      RegExp(r'^([A-Z]+)(\d+)$').firstMatch(compact) ??
      RegExp(r'^(\d+)([A-Z]+)$').firstMatch(compact);
  return m == null ? compact : '${m.group(1)} ${m.group(2)}';
}

/// [compact] read as [shape], fixing look-alike characters; null if it
/// can't be. The second value counts the fixes (fewer is likelier).
(String, int)? _asShape(String compact, _PlateShape shape) {
  for (int l = shape.letters.$1; l <= shape.letters.$2; l++) {
    for (int d = shape.digits.$1; d <= shape.digits.$2; d++) {
      if (compact.length != l + d) continue;
      final String a = shape.lettersFirst
          ? compact.substring(0, l)
          : compact.substring(0, d);
      final String b = shape.lettersFirst
          ? compact.substring(l)
          : compact.substring(d);
      final String letterPart = shape.lettersFirst ? a : b;
      final String digitPart = shape.lettersFirst ? b : a;
      int fixes = 0;
      final StringBuffer letters = StringBuffer();
      for (final String c in letterPart.split('')) {
        if (RegExp(r'[A-Z]').hasMatch(c)) {
          letters.write(c);
        } else if (_toLetter[c] != null) {
          letters.write(_toLetter[c]);
          fixes++;
        } else {
          letters.clear();
          break;
        }
      }
      final StringBuffer digits = StringBuffer();
      for (final String c in digitPart.split('')) {
        if (RegExp(r'\d').hasMatch(c)) {
          digits.write(c);
        } else if (_toDigit[c] != null) {
          digits.write(_toDigit[c]);
          fixes++;
        } else {
          digits.clear();
          break;
        }
      }
      if (letters.length != letterPart.length ||
          digits.length != digitPart.length) {
        continue;
      }
      return shape.lettersFirst
          ? ('$letters$digits', fixes)
          : ('$digits$letters', fixes);
    }
  }
  return null;
}

/// Up to [max] plate guesses from recognized [lines] of text, best first.
/// A plate the facility already knows ([knownPlates]: parked now, today's
/// temporary QRs, recent walk-ins) ranks first; then the likeliest shape
/// with the fewest look-alike fixes. Empty when nothing looks like a plate.
List<String> plateCandidates(
  List<String> lines, {
  Iterable<String> knownPlates = const <String>[],
  int max = 3,
}) {
  final Set<String> known = knownPlates.map(_clean).toSet();
  // Single tokens, and neighbours joined ("ABC" "1234" -> "ABC1234").
  final List<String> pieces = <String>[];
  for (final String line in lines) {
    final List<String> tokens = line
        .split(RegExp(r'[\s\-–_.:|/]+'))
        .map(_clean)
        .where((String t) => t.isNotEmpty)
        .toList();
    for (int i = 0; i < tokens.length; i++) {
      pieces.add(tokens[i]);
      if (i + 1 < tokens.length) pieces.add(tokens[i] + tokens[i + 1]);
    }
    pieces.add(_clean(line));
  }
  final Map<String, int> score = <String, int>{};
  for (final String piece in pieces) {
    if (piece.length < 4 || piece.length > 8) continue;
    for (int s = 0; s < _shapes.length; s++) {
      final (String, int)? read = _asShape(piece, _shapes[s]);
      if (read == null) continue;
      final (String plate, int fixes) = read;
      // Lower is better: known plates far ahead, then fewer look-alike
      // fixes (a fix is a guess), then the commoner shape.
      final int points =
          (known.contains(plate) ? 0 : 1000) + fixes * 50 + s * 10;
      if (!score.containsKey(plate) || points < score[plate]!) {
        score[plate] = points;
      }
    }
  }
  final List<String> ranked = score.keys.toList()
    ..sort((String a, String b) => score[a]!.compareTo(score[b]!));
  return ranked.take(max).map(formatPlate).toList();
}
