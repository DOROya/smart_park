import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/plate_reader.dart';

void main() {
  test('a clean car plate', () {
    expect(plateCandidates(<String>['ABC 1234']).first, 'ABC 1234');
    expect(plateCandidates(<String>['NCR', 'ABC-123']).first, 'ABC 123');
  });

  test('frame and dealer text around the plate is left out', () {
    final List<String> c = plateCandidates(<String>[
      'PILIPINAS',
      'NAQ 4521',
      'TOYOTA SAN PABLO',
      'MATATAG',
    ]);
    expect(c.first, 'NAQ 4521');
  });

  test('0/O and 1/I look-alikes are fixed in the right part', () {
    // O in the digits is a zero; 1 in the letters is an I.
    expect(plateCandidates(<String>['ABC 12O4']).first, 'ABC 1204');
    expect(plateCandidates(<String>['A1C 1234']).first, 'AIC 1234');
  });

  test('motorcycle formats', () {
    expect(plateCandidates(<String>['123 ABC']).first, '123 ABC');
    expect(plateCandidates(<String>['AB 12345']).first, 'AB 12345');
  });

  test('a plate the facility knows ranks first', () {
    final List<String> c = plateCandidates(
      <String>['ABC 1234', 'XYZ 9876'],
      knownPlates: <String>['XYZ9876'],
    );
    expect(c.first, 'XYZ 9876');
    expect(c, contains('ABC 1234'));
  });

  test('nothing plate-like gives nothing, never something random', () {
    expect(plateCandidates(<String>['WELCOME', 'PARKING ONLY']), isEmpty);
    expect(plateCandidates(<String>[]), isEmpty);
  });
}
