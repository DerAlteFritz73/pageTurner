import 'package:flutter_test/flutter_test.dart';
import 'package:leggio/continuo/models/note.dart';
import 'package:leggio/continuo/services/harmony_analyzer.dart';

void main() {
  final analyzer = HarmonyAnalyzer();

  group('scaleDegree', () {
    test('C in C major → 1', () {
      const note = Note(step: 'C', octave: 3);
      expect(analyzer.scaleDegree(note, 0, 'major'), 1);
    });

    test('G in C major → 5', () {
      const note = Note(step: 'G', octave: 3);
      expect(analyzer.scaleDegree(note, 0, 'major'), 5);
    });

    test('B in C major → 7 (leading tone)', () {
      const note = Note(step: 'B', octave: 3);
      expect(analyzer.scaleDegree(note, 0, 'major'), 7);
    });

    test('D in G major → 5', () {
      const note = Note(step: 'D', octave: 3);
      expect(analyzer.scaleDegree(note, 1, 'major'), 5);
    });

    test('A in A minor → 1', () {
      const note = Note(step: 'A', octave: 3);
      expect(analyzer.scaleDegree(note, 0, 'minor'), 1);
    });

    test('E in A minor → 5', () {
      const note = Note(step: 'E', octave: 3);
      expect(analyzer.scaleDegree(note, 0, 'minor'), 5);
    });

    test('F in D minor → 3', () {
      const note = Note(step: 'F', octave: 3);
      expect(analyzer.scaleDegree(note, -1, 'minor'), 3);
    });

    test('chromatic note maps to closest degree', () {
      // F# in C major → closest to F (degree 4) or G (degree 5)
      const note = Note(step: 'F', octave: 3, alter: 1);
      final deg = analyzer.scaleDegree(note, 0, 'major');
      expect(deg, anyOf(4, 5));
    });
  });

  group('motion', () {
    test('null prev → start', () {
      const curr = Note(step: 'C', octave: 3);
      final result = analyzer.motion(null, curr);
      expect(result.type, 'start');
      expect(result.size, 0);
    });

    test('rest prev → start', () {
      const rest = Note(step: 'C', octave: 0, isRest: true);
      const curr = Note(step: 'C', octave: 3);
      final result = analyzer.motion(rest, curr);
      expect(result.type, 'start');
    });

    test('same note → same', () {
      const a = Note(step: 'C', octave: 3);
      const b = Note(step: 'C', octave: 3);
      final result = analyzer.motion(a, b);
      expect(result.type, 'same');
      expect(result.size, 0);
    });

    test('C3 to D3 → step-up (2 semitones)', () {
      const a = Note(step: 'C', octave: 3);
      const b = Note(step: 'D', octave: 3);
      final result = analyzer.motion(a, b);
      expect(result.type, 'step-up');
      expect(result.size, 2);
    });

    test('D3 to C3 → step-down (2 semitones)', () {
      const a = Note(step: 'D', octave: 3);
      const b = Note(step: 'C', octave: 3);
      final result = analyzer.motion(a, b);
      expect(result.type, 'step-down');
      expect(result.size, 2);
    });

    test('C3 to E3 → leap-up (4 semitones)', () {
      const a = Note(step: 'C', octave: 3);
      const b = Note(step: 'E', octave: 3);
      final result = analyzer.motion(a, b);
      expect(result.type, 'leap-up');
      expect(result.size, 4);
    });

    test('G3 to C3 → leap-down (7 semitones)', () {
      const a = Note(step: 'G', octave: 3);
      const b = Note(step: 'C', octave: 3);
      final result = analyzer.motion(a, b);
      expect(result.type, 'leap-down');
      expect(result.size, 7);
    });

    test('E3 to F3 → step-up (1 semitone)', () {
      const a = Note(step: 'E', octave: 3);
      const b = Note(step: 'F', octave: 3);
      final result = analyzer.motion(a, b);
      expect(result.type, 'step-up');
      expect(result.size, 1);
    });
  });

  group('genericInterval', () {
    test('0 semitones → unison', () {
      expect(analyzer.genericInterval(0), 'unison');
    });
    test('2 semitones → 2nd', () {
      expect(analyzer.genericInterval(2), '2nd');
    });
    test('7 semitones → 5th', () {
      expect(analyzer.genericInterval(7), '5th');
    });
    test('6 semitones → tritone', () {
      expect(analyzer.genericInterval(6), 'tritone');
    });
    test('12 semitones → octave', () {
      expect(analyzer.genericInterval(12), 'octave');
    });
  });
}
