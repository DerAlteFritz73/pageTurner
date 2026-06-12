import '../models/note.dart';
import 'pitch_helper.dart';

class MotionResult {
  final String type; // 'start', 'step-up', 'step-down', 'leap-up', 'leap-down', 'same'
  final int size; // semitones

  const MotionResult({required this.type, required this.size});
}

class HarmonyAnalyzer {
  int scaleDegree(Note note, int keyFifths, String keyMode) {
    final scale = PitchHelper.buildScale(keyFifths, keyMode);
    final pc = note.pitchClass();

    final idx = scale.indexOf(pc);
    if (idx != -1) return idx + 1;

    // No exact match — find closest
    var bestDeg = 1;
    var bestDist = 12;
    for (var deg = 0; deg < scale.length; deg++) {
      final scalePc = scale[deg];
      final dist = [
        (pc - scalePc).abs(),
        12 - (pc - scalePc).abs(),
      ].reduce((a, b) => a < b ? a : b);
      if (dist < bestDist) {
        bestDist = dist;
        bestDeg = deg + 1;
      }
    }
    return bestDeg;
  }

  MotionResult motion(Note? prevNote, Note? currNote) {
    if (prevNote == null || prevNote.isRest) {
      return const MotionResult(type: 'start', size: 0);
    }
    if (currNote == null || currNote.isRest) {
      return const MotionResult(type: 'start', size: 0);
    }

    final interval = currNote.midiPitch() - prevNote.midiPitch();
    final absInt = interval.abs();

    if (absInt == 0) {
      return const MotionResult(type: 'same', size: 0);
    }

    final String type;
    if (absInt <= 2) {
      type = interval > 0 ? 'step-up' : 'step-down';
    } else {
      type = interval > 0 ? 'leap-up' : 'leap-down';
    }

    return MotionResult(type: type, size: absInt);
  }

  String genericInterval(int semitones) {
    final abs = semitones.abs();
    return switch (abs) {
      0 => 'unison',
      1 || 2 => '2nd',
      3 || 4 => '3rd',
      5 => '4th',
      6 => 'tritone',
      7 => '5th',
      8 || 9 => '6th',
      10 || 11 => '7th',
      12 => 'octave',
      _ => '${abs}st',
    };
  }
}
