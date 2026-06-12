import 'package:flutter_test/flutter_test.dart';
import 'package:leggio/continuo/models/measure.dart';
import 'package:leggio/continuo/models/note.dart';
import 'package:leggio/continuo/models/score.dart';
import 'package:leggio/continuo/services/continuo_realizer.dart';
import 'package:leggio/continuo/services/figured_bass_interpreter.dart';
import 'package:leggio/continuo/services/harmony_analyzer.dart';
import 'package:leggio/continuo/services/voice_leading_engine.dart';

void main() {
  late ContinuoRealizer realizer;

  setUp(() {
    realizer = ContinuoRealizer(
      interpreter: const FiguredBassInterpreter(),
      analyzer: HarmonyAnalyzer(),
      voiceLeading: VoiceLeadingEngine(),
    );
  });

  Score _makeScore(List<Note> bassNotes, {int keyFifths = 0, String keyMode = 'major'}) {
    final score = Score()
      ..keyFifths = keyFifths
      ..keyMode = keyMode;
    final measure = Measure(1);
    measure.bassNotes.addAll(bassNotes);
    score.measures.add(measure);
    return score;
  }

  group('realize - basic', () {
    test('single note produces a realization', () {
      final score = _makeScore([
        const Note(step: 'C', octave: 3),
      ]);
      final result = realizer.realize(score);

      expect(result.measures.length, 1);
      expect(result.measures[0].realizedChords.length, 1);
      expect(result.measures[0].realizedChords[0].upperVoices.length, 3);
    });

    test('rest notes are skipped', () {
      final score = _makeScore([
        const Note(step: 'C', octave: 0, isRest: true),
        const Note(step: 'G', octave: 3),
      ]);
      final result = realizer.realize(score);

      final chords = result.measures[0].realizedChords;
      expect(chords.length, 2);
      expect(chords[0].bass.isRest, true);
      expect(chords[0].upperVoices, isEmpty);
      expect(chords[1].upperVoices.length, 3);
    });

    test('figured bass notes use file figures', () {
      final score = _makeScore([
        const Note(step: 'C', octave: 3, figuredBass: [6]),
      ]);
      final result = realizer.realize(score);
      final chord = result.measures[0].realizedChords[0];

      expect(chord.decisionTrace, isNotEmpty);
      expect(chord.decisionTrace[0]['figuresSource'], 'file');
    });

    test('unfigured bass notes use computed figures', () {
      final score = _makeScore([
        const Note(step: 'C', octave: 3),
      ]);
      final result = realizer.realize(score);
      final chord = result.measures[0].realizedChords[0];

      expect(chord.decisionTrace, isNotEmpty);
      expect(chord.decisionTrace[0]['figuresSource'], 'computed');
    });
  });

  group('realize - voice leading quality', () {
    test('I-V-I cadence has no parallel fifths or octaves', () {
      final score = _makeScore([
        const Note(step: 'C', octave: 3), // I
        const Note(step: 'G', octave: 2), // V
        const Note(step: 'C', octave: 3), // I
      ]);
      final result = realizer.realize(score);
      final chords = result.measures[0].realizedChords;

      final engine = VoiceLeadingEngine();
      for (var i = 1; i < chords.length; i++) {
        if (chords[i].bass.isRest || chords[i - 1].bass.isRest) continue;
        final violations = engine.checkParallels(chords[i - 1], chords[i]);
        expect(violations, isEmpty,
            reason: 'Parallel violation at chord $i: $violations');
      }
    });

    test('chromatic bass line produces valid realizations', () {
      // Test a descending bass pattern in minor
      final score = _makeScore([
        const Note(step: 'A', octave: 3),
        const Note(step: 'G', octave: 3, alter: 1), // G# (raised 7th)
        const Note(step: 'G', octave: 3),
        const Note(step: 'F', octave: 3),
        const Note(step: 'E', octave: 3),
      ], keyFifths: 0, keyMode: 'minor');
      final result = realizer.realize(score);

      for (final chord in result.measures[0].realizedChords) {
        if (chord.bass.isRest) continue;
        expect(chord.upperVoices, isNotEmpty);
        // All upper voices should be above the bass
        for (final voice in chord.upperVoices) {
          expect(voice.midiPitch(), greaterThan(chord.bass.midiPitch()),
              reason:
                  'Voice ${voice.step}${voice.octave} is not above bass '
                  '${chord.bass.step}${chord.bass.octave}');
        }
      }
    });
  });

  group('realize - 3-voice mode', () {
    test('3-voice produces 2 upper voices', () {
      final score = _makeScore([
        const Note(step: 'C', octave: 3),
      ]);
      final result = realizer.realize(score, numVoices: 3);
      expect(result.measures[0].realizedChords[0].upperVoices.length, 2);
    });
  });

  group('realize - decision trace', () {
    test('each chord has decision trace with key context', () {
      final score = _makeScore([
        const Note(step: 'C', octave: 3),
        const Note(step: 'D', octave: 3),
      ]);
      final result = realizer.realize(score);

      for (final chord in result.measures[0].realizedChords) {
        if (chord.bass.isRest) continue;
        expect(chord.decisionTrace, isNotEmpty);
        final info = chord.decisionTrace[0];
        expect(info.containsKey('scaleDegree'), true);
        expect(info.containsKey('keyFifths'), true);
        expect(info.containsKey('keyMode'), true);
        expect(info.containsKey('steps'), true);
      }
    });

    test('chord symbols are generated', () {
      final score = _makeScore([
        const Note(step: 'C', octave: 3),
      ]);
      final result = realizer.realize(score);
      final chord = result.measures[0].realizedChords[0];
      expect(chord.chordSymbol, isNotEmpty);
      expect(chord.chordSymbol, startsWith('I'));
    });
  });
}
