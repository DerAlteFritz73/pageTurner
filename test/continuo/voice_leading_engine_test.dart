import 'package:flutter_test/flutter_test.dart';
import 'package:leggio/continuo/models/chord.dart';
import 'package:leggio/continuo/models/note.dart';
import 'package:leggio/continuo/services/figured_bass_interpreter.dart';
import 'package:leggio/continuo/services/voice_leading_engine.dart';

void main() {
  final engine = VoiceLeadingEngine();

  group('checkParallels', () {
    test('no parallels when voices move by different intervals', () {
      // I → IV in C major with proper voice leading (contrary motion)
      final prev = Chord(
        bass: const Note(step: 'C', octave: 3), // 48
        figures: const [],
        upperVoices: [
          const Note(step: 'E', octave: 5), // 76 soprano
          const Note(step: 'G', octave: 4), // 67 alto
          const Note(step: 'E', octave: 4), // 64 tenor
        ],
      );
      final curr = Chord(
        bass: const Note(step: 'F', octave: 3), // 53
        figures: const [],
        upperVoices: [
          const Note(step: 'F', octave: 5), // 77 soprano (step up)
          const Note(step: 'A', octave: 4), // 69 alto (step up)
          const Note(step: 'C', octave: 4), // 60 tenor (step down)
        ],
      );
      final violations = engine.checkParallels(prev, curr);
      expect(violations, isEmpty);
    });

    test('detects parallel fifths between two voices', () {
      // Bass and soprano both form P5 and move by step
      final prev = Chord(
        bass: const Note(step: 'C', octave: 3), // 48
        figures: const [],
        upperVoices: [
          const Note(step: 'G', octave: 3), // 55 — P5 above bass
        ],
      );
      final curr = Chord(
        bass: const Note(step: 'D', octave: 3), // 50
        figures: const [],
        upperVoices: [
          const Note(step: 'A', octave: 3), // 57 — P5 above bass
        ],
      );
      final violations = engine.checkParallels(prev, curr);
      expect(violations.any((v) => v.contains('fifths')), true);
    });

    test('detects parallel octaves between two voices', () {
      final prev = Chord(
        bass: const Note(step: 'C', octave: 3), // 48
        figures: const [],
        upperVoices: [
          const Note(step: 'C', octave: 4), // 60 — octave above
        ],
      );
      final curr = Chord(
        bass: const Note(step: 'D', octave: 3), // 50
        figures: const [],
        upperVoices: [
          const Note(step: 'D', octave: 4), // 62 — octave above
        ],
      );
      final violations = engine.checkParallels(prev, curr);
      expect(
          violations
              .any((v) => v.contains('octave') || v.contains('unison')),
          true);
    });

    test('static voice (common tone) is not flagged', () {
      // G stays the same in soprano — no parallel even though bass P5
      final prev = Chord(
        bass: const Note(step: 'C', octave: 3),
        figures: const [],
        upperVoices: [
          const Note(step: 'G', octave: 4), // stays
        ],
      );
      final curr = Chord(
        bass: const Note(step: 'G', octave: 3),
        figures: const [],
        upperVoices: [
          const Note(step: 'G', octave: 4), // common tone
        ],
      );
      // Bass moves but soprano doesn't, so no parallel motion
      final violations = engine.checkParallels(prev, curr);
      // checkParallels requires both voices to actually move
      expect(violations, isEmpty);
    });
  });

  group('assignVoices', () {
    test('produces correct number of upper voices (4-voice)', () {
      final chord = Chord(
        bass: const Note(step: 'C', octave: 3),
        figures: const [],
      );
      final intervals = [
        const ExpandedInterval(interval: 3),
        const ExpandedInterval(interval: 5),
      ];
      final result = engine.assignVoices(
        chord: chord,
        intervals: intervals,
        prevChord: null,
        keyFifths: 0,
        keyMode: 'major',
        numVoices: 4,
      );
      expect(result.upperVoices.length, 3);
    });

    test('produces correct number of upper voices (3-voice)', () {
      final chord = Chord(
        bass: const Note(step: 'C', octave: 3),
        figures: const [],
      );
      final intervals = [
        const ExpandedInterval(interval: 3),
        const ExpandedInterval(interval: 5),
      ];
      final result = engine.assignVoices(
        chord: chord,
        intervals: intervals,
        prevChord: null,
        keyFifths: 0,
        keyMode: 'major',
        numVoices: 3,
      );
      expect(result.upperVoices.length, 2);
    });

    test('all upper voices are above the bass', () {
      final chord = Chord(
        bass: const Note(step: 'C', octave: 3),
        figures: const [],
      );
      final intervals = [
        const ExpandedInterval(interval: 3),
        const ExpandedInterval(interval: 5),
      ];
      final result = engine.assignVoices(
        chord: chord,
        intervals: intervals,
        prevChord: null,
        keyFifths: 0,
        keyMode: 'major',
        numVoices: 4,
      );

      for (final voice in result.upperVoices) {
        expect(voice.midiPitch(), greaterThan(chord.bass.midiPitch()),
            reason:
                '${voice.step}${voice.octave} should be above bass C3');
      }
    });

    test('chord contains only pitch classes from the intervals', () {
      const bass = Note(step: 'C', octave: 3); // C=0
      final chord = Chord(bass: bass, figures: const []);
      // 3rd above C = E (pc 4), 5th above C = G (pc 7)
      final intervals = [
        const ExpandedInterval(interval: 3),
        const ExpandedInterval(interval: 5),
      ];
      final result = engine.assignVoices(
        chord: chord,
        intervals: intervals,
        prevChord: null,
        keyFifths: 0,
        keyMode: 'major',
        numVoices: 4,
      );

      final validPcs = {0, 4, 7}; // C, E, G
      for (final voice in result.upperVoices) {
        expect(validPcs.contains(voice.pitchClass()), true,
            reason:
                '${voice.step}${voice.octave} (pc=${voice.pitchClass()}) '
                'should be in $validPcs');
      }
    });
  });
}
