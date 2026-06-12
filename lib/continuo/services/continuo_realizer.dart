import '../models/chord.dart';
import '../models/measure.dart';
import '../models/note.dart';
import '../models/score.dart';
import 'figured_bass_interpreter.dart';
import 'harmony_analyzer.dart';
import 'voice_leading_engine.dart';

/// Main orchestrator for basso continuo realization.
///
/// Algorithm (based on Wead & Knopke ICMC 2007 + Gasparini 1729 + Delair 1724):
///
/// For each bass note in sequence:
///  1. Determine if figured bass is already present
///  2. If not, run the unfigured bass decision tree:
///     a. Compute scale degree
///     b. Compute melodic motion (prev -> curr, curr -> next)
///     c. Select figures from decision tree
///  3. Expand figures to full interval list (FiguredBassInterpreter)
///  4. Realize upper voices (VoiceLeadingEngine)
///  5. Store realized Chord back into Measure
class ContinuoRealizer {
  final FiguredBassInterpreter _interpreter;
  final HarmonyAnalyzer _analyzer;
  final VoiceLeadingEngine _voiceLeading;

  ContinuoRealizer({
    required FiguredBassInterpreter interpreter,
    required HarmonyAnalyzer analyzer,
    required VoiceLeadingEngine voiceLeading,
  })  : _interpreter = interpreter,
        _analyzer = analyzer,
        _voiceLeading = voiceLeading;

  Score realize(Score score, {int numVoices = 4}) {
    Chord? prevChord;
    Note? prevNote;
    final allBassNotes = _collectAllBassNotes(score);
    var noteIndex = 0;

    for (final measure in score.measures) {
      final keyFifths =
          (measure.keySignature?['fifths'] as int?) ?? score.keyFifths;
      final keyMode =
          (measure.keySignature?['mode'] as String?) ?? score.keyMode;
      var bassOffset = 0.0; // cumulative quarter-note offset within measure

      for (var i = 0; i < measure.bassNotes.length; i++) {
        final bassNote = measure.bassNotes[i];

        if (bassNote.isRest) {
          prevNote = null;
          prevChord = null;
          bassOffset += bassNote.duration;
          noteIndex++;
          continue;
        }

        // Determine motion context (lookahead for next note)
        Note? nextNote;
        if (noteIndex + 1 < allBassNotes.length) {
          final candidate = allBassNotes[noteIndex + 1];
          nextNote = candidate.isRest ? null : candidate;
        }

        final currMotion = _analyzer.motion(prevNote, bassNote);
        final nextMotion = _analyzer.motion(bassNote, nextNote);

        // Scale degree of current bass note
        final scaleDeg =
            _analyzer.scaleDegree(bassNote, keyFifths, keyMode);

        // Get raw figures (from file or from decision tree)
        var rawFigures = bassNote.figuredBass
            .map((n) => Figure(number: n))
            .toList();
        var decisionSteps = <TraceStep>[];
        var figuresSource = 'file';

        if (rawFigures.isEmpty) {
          // Unfigured bass: run decision tree
          figuresSource = 'computed';
          final decisionResult = _interpreter.unfiguredDecision(
            scaleDegree: scaleDeg,
            motion: currMotion.type,
            nextMotion: nextMotion.type,
            mode: keyMode,
            leapSize: currMotion.size,
          );
          rawFigures = decisionResult.figures;
          decisionSteps = decisionResult.trace;
        }

        // Expand figures to interval list
        final intervals = _interpreter.expand(
          rawFigures,
          bassNote,
          keyFifths,
          keyMode,
        );

        // Determine if bass is leading tone (scale degree 7)
        final isLeadingTone = scaleDeg == 7;

        // Build chord object
        var chord = Chord(
          bass: bassNote,
          figures: rawFigures,
          chordSymbol: _chordSymbol(scaleDeg, rawFigures, keyMode),
        );

        // Store decision context and trace in chord
        chord.decisionTrace
          ..clear()
          ..add({
            'scaleDegree': scaleDeg,
            'motionIn': currMotion.type,
            'motionInSize': currMotion.size,
            'motionOut': nextMotion.type,
            'figuresSource': figuresSource,
            'keyFifths': keyFifths,
            'keyMode': keyMode,
            'steps': decisionSteps
                .map((s) => {
                      'test': s.test,
                      'passed': s.passed,
                      'isDecision': s.isDecision,
                      if (s.rule != null) 'rule': s.rule,
                      if (s.source != null) 'source': s.source,
                      if (s.figures != null) 'figures': s.figures,
                    })
                .toList(),
          });

        // Find melody pitch class sounding at this beat (if any)
        final melodyPc = _findMelodyPc(measure.melodyNotes, bassOffset);

        // Realize upper voices
        chord = _voiceLeading.assignVoices(
          chord: chord,
          intervals: intervals,
          prevChord: prevChord,
          keyFifths: keyFifths,
          keyMode: keyMode,
          isLeadingTone7th: isLeadingTone,
          melodyPc: melodyPc,
          numVoices: numVoices,
        );

        // Append voice-leading trace to decision steps (works for both
        // figured and unfigured notes: figured notes get only VL steps,
        // unfigured notes get the figure-decision steps + VL steps).
        final vlTrace = _voiceLeading.traceVoiceLeading(
          chord,
          prevChord,
          keyFifths,
          keyMode,
        );
        final mergedSteps = [...decisionSteps, ...vlTrace];

        // Update the trace with merged steps
        if (chord.decisionTrace.isNotEmpty) {
          chord.decisionTrace[0] = {
            ...chord.decisionTrace[0],
            'steps': mergedSteps,
          };
        }

        // Store realized chord in measure
        if (i < measure.realizedChords.length) {
          measure.realizedChords[i] = chord;
        } else {
          // Expand list to accommodate index
          while (measure.realizedChords.length < i) {
            measure.realizedChords.add(Chord(
              bass: const Note(step: 'C', octave: 0, isRest: true),
              figures: const [],
            ));
          }
          measure.realizedChords.add(chord);
        }

        prevNote = bassNote;
        prevChord = chord;
        bassOffset += bassNote.duration;
        noteIndex++;
      }
    }

    return score;
  }

  /// Find the melody pitch class (0-11) sounding at [beatOffset] quarters
  /// into the measure.  Returns null when no melody note covers that position.
  int? _findMelodyPc(List<MelodyNote> melodyNotes, double beatOffset) {
    for (final mn in melodyNotes) {
      if (mn.offset <= beatOffset + 0.001 &&
          beatOffset < mn.offset + mn.duration - 0.001) {
        return mn.pitchClass;
      }
    }
    return null;
  }

  /// Flatten all bass notes from all measures into a single list for lookahead.
  List<Note> _collectAllBassNotes(Score score) {
    final all = <Note>[];
    for (final measure in score.measures) {
      all.addAll(measure.bassNotes);
    }
    return all;
  }

  /// Generate a Roman numeral chord symbol for display purposes.
  String _chordSymbol(int scaleDeg, List<Figure> figures, String mode) {
    final isMajor = mode.toLowerCase() == 'major';

    const majorQuality = ['I', 'ii', 'iii', 'IV', 'V', 'vi', 'vii°'];
    const minorQuality = ['i', 'ii°', 'III', 'iv', 'V', 'VI', 'vii°'];

    final symbols = isMajor ? majorQuality : minorQuality;
    final base =
        (scaleDeg >= 1 && scaleDeg <= 7) ? symbols[scaleDeg - 1] : '?';

    bool has(int n) => figures.any((f) => f.number == n);

    if (has(2) && !has(9)) return '$base²';
    if (has(4) && has(3)) return '$base⁴₃';
    if (has(6) && has(5)) return '$base⁶₅';
    if (has(7)) return '$base⁷';
    if (has(6) && has(4)) return '$base⁶₄';
    if (has(6)) return '$base⁶';

    return base;
  }
}
