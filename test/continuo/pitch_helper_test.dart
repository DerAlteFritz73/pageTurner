import 'package:flutter_test/flutter_test.dart';
import 'package:leggio/continuo/models/note.dart';
import 'package:leggio/continuo/services/pitch_helper.dart';

void main() {
  group('PitchHelper.buildScale', () {
    test('C major (0 fifths)', () {
      final scale = PitchHelper.buildScale(0, 'major');
      expect(scale, [0, 2, 4, 5, 7, 9, 11]); // C D E F G A B
    });

    test('G major (1 sharp)', () {
      final scale = PitchHelper.buildScale(1, 'major');
      // G=7, A=9, B=11, C=0, D=2, E=4, F#=6
      expect(scale, [7, 9, 11, 0, 2, 4, 6]);
    });

    test('D major (2 sharps)', () {
      final scale = PitchHelper.buildScale(2, 'major');
      // D=2, E=4, F#=6, G=7, A=9, B=11, C#=1
      expect(scale, [2, 4, 6, 7, 9, 11, 1]);
    });

    test('F major (1 flat)', () {
      final scale = PitchHelper.buildScale(-1, 'major');
      // F=5, G=7, A=9, Bb=10, C=0, D=2, E=4
      expect(scale, [5, 7, 9, 10, 0, 2, 4]);
    });

    test('Bb major (2 flats)', () {
      final scale = PitchHelper.buildScale(-2, 'major');
      // Bb=10, C=0, D=2, Eb=3, F=5, G=7, A=9
      expect(scale, [10, 0, 2, 3, 5, 7, 9]);
    });

    test('A minor (0 fifths)', () {
      final scale = PitchHelper.buildScale(0, 'minor');
      // A=9, B=11, C=0, D=2, E=4, F=5, G=7
      expect(scale, [9, 11, 0, 2, 4, 5, 7]);
    });

    test('D minor (1 flat)', () {
      final scale = PitchHelper.buildScale(-1, 'minor');
      // D=2, E=4, F=5, G=7, A=9, Bb=10, C=0
      expect(scale, [2, 4, 5, 7, 9, 10, 0]);
    });

    test('E minor (1 sharp)', () {
      final scale = PitchHelper.buildScale(1, 'minor');
      // E=4, F#=6, G=7, A=9, B=11, C=0, D=2
      expect(scale, [4, 6, 7, 9, 11, 0, 2]);
    });
  });

  group('PitchHelper.diatonicInterval', () {
    test('3rd above C3 in C major → E3', () {
      const bass = Note(step: 'C', octave: 3);
      final result = PitchHelper.diatonicInterval(bass, 3, 0, 'major');
      expect(result.step, 'E');
      expect(result.midiPitch(), 52); // E3
    });

    test('5th above C3 in C major → G3', () {
      const bass = Note(step: 'C', octave: 3);
      final result = PitchHelper.diatonicInterval(bass, 5, 0, 'major');
      expect(result.step, 'G');
      expect(result.midiPitch(), 55); // G3
    });

    test('6th above D3 in G major → B3', () {
      const bass = Note(step: 'D', octave: 3);
      final result = PitchHelper.diatonicInterval(bass, 6, 1, 'major');
      expect(result.step, 'B');
      expect(result.midiPitch(), 59); // B3
    });

    test('result is always above the bass', () {
      const bass = Note(step: 'B', octave: 3);
      final result = PitchHelper.diatonicInterval(bass, 3, 0, 'major');
      expect(result.midiPitch(), greaterThan(bass.midiPitch()));
    });
  });

  group('PitchHelper.midiToNote', () {
    test('middle C → C4', () {
      final note = PitchHelper.midiToNote(60);
      expect(note.step, 'C');
      expect(note.octave, 4);
      expect(note.alter, 0);
    });

    test('MIDI 61 sharp key → C#4', () {
      final note = PitchHelper.midiToNote(61, 1.0, 'quarter', null, 1);
      expect(note.step, 'C');
      expect(note.alter, 1);
      expect(note.octave, 4);
    });

    test('MIDI 61 flat key → Db4', () {
      final note = PitchHelper.midiToNote(61, 1.0, 'quarter', null, -1);
      expect(note.step, 'D');
      expect(note.alter, -1);
      expect(note.octave, 4);
    });
  });

  group('Note.midiPitch', () {
    test('C4 = 60', () {
      const note = Note(step: 'C', octave: 4);
      expect(note.midiPitch(), 60);
    });

    test('A4 = 69', () {
      const note = Note(step: 'A', octave: 4);
      expect(note.midiPitch(), 69);
    });

    test('C#4 = 61', () {
      const note = Note(step: 'C', octave: 4, alter: 1);
      expect(note.midiPitch(), 61);
    });

    test('Bb3 = 58', () {
      const note = Note(step: 'B', octave: 3, alter: -1);
      expect(note.midiPitch(), 58);
    });

    test('rest returns -1', () {
      const rest = Note(step: 'C', octave: 0, isRest: true);
      expect(rest.midiPitch(), -1);
    });
  });
}
