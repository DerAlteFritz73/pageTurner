import '../models/note.dart';

class PitchHelper {
  static const steps = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

  static const _stepSemitones = {
    'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11,
  };

  static const _majorScale = [0, 2, 4, 5, 7, 9, 11]; // degrees 1-7
  static const _minorScale = [0, 2, 3, 5, 7, 8, 10];

  static List<int> buildScale(int keyFifths, String keyMode) {
    final int tonicPc;
    if (keyMode.toLowerCase() == 'minor') {
      tonicPc = ((keyFifths * 7 - 3) % 12 + 12) % 12;
    } else {
      tonicPc = ((keyFifths * 7) % 12 + 12) % 12;
    }

    final template =
        keyMode.toLowerCase() == 'minor' ? _minorScale : _majorScale;
    return template.map((interval) => (tonicPc + interval) % 12).toList();
  }

  static Note diatonicInterval(
    Note bass,
    int interval,
    int keyFifths,
    String keyMode,
  ) {
    final scale = buildScale(keyFifths, keyMode);
    final bassPc = bass.pitchClass();

    var bassIdx = scale.indexOf(bassPc);
    if (bassIdx == -1) {
      bassIdx = _closestScaleDegree(bassPc, scale);
    }

    final targetIdx = (bassIdx + (interval - 1)) % 7;
    final targetPc = scale[targetIdx];

    var targetMidi = (bass.octave + 1) * 12 + targetPc;
    final bassMidi = bass.midiPitch();

    while (targetMidi <= bassMidi) {
      targetMidi += 12;
    }
    while (targetMidi - bassMidi > 24) {
      targetMidi -= 12;
    }

    return midiToNote(targetMidi, bass.duration, bass.type, bass.voice,
        keyFifths);
  }

  static Note midiToNote(
    int midi, [
    double duration = 1.0,
    String type = 'quarter',
    int? voice,
    int keyFifths = 0,
  ]) {
    final pc = midi % 12;
    final octave = midi ~/ 12 - 1;

    // Flat keys: prefer flat spellings; Sharp keys: prefer sharp spellings
    const flatPcMap = {
      0: ('C', 0), 1: ('D', -1), 2: ('D', 0), 3: ('E', -1),
      4: ('E', 0), 5: ('F', 0), 6: ('G', -1), 7: ('G', 0),
      8: ('A', -1), 9: ('A', 0), 10: ('B', -1), 11: ('B', 0),
    };
    const sharpPcMap = {
      0: ('C', 0), 1: ('C', 1), 2: ('D', 0), 3: ('D', 1),
      4: ('E', 0), 5: ('F', 0), 6: ('F', 1), 7: ('G', 0),
      8: ('G', 1), 9: ('A', 0), 10: ('A', 1), 11: ('B', 0),
    };

    final pcMap = keyFifths < 0 ? flatPcMap : sharpPcMap;
    final (step, alter) = pcMap[pc]!;
    return Note(
      step: step,
      octave: octave,
      duration: duration,
      alter: alter,
      type: type,
      voice: voice,
    );
  }

  static Note midiToNoteWithStep(
    int midi,
    String preferredStep, [
    double duration = 1.0,
    String type = 'quarter',
    int? voice,
  ]) {
    final octave = midi ~/ 12 - 1;
    final pc = midi % 12;
    final expected = _stepSemitones[preferredStep]!;
    var alter = (pc - expected + 12) % 12;
    if (alter > 2) alter -= 12;
    alter = alter.clamp(-2, 2);
    return Note(
      step: preferredStep,
      octave: octave,
      duration: duration,
      alter: alter,
      type: type,
      voice: voice,
    );
  }

  static int stepToPitchClass(String step) => _stepSemitones[step] ?? 0;

  static String tonicFromFifths(int fifths, String mode) {
    const majorOrder = [
      'Cb', 'Gb', 'Db', 'Ab', 'Eb', 'Bb', 'F',
      'C', 'G', 'D', 'A', 'E', 'B', 'F#', 'C#',
    ];
    const minorOrder = [
      'Ab', 'Eb', 'Bb', 'F', 'C', 'G', 'D',
      'A', 'E', 'B', 'F#', 'C#', 'G#', 'D#', 'A#',
    ];

    final order = mode.toLowerCase() == 'minor' ? minorOrder : majorOrder;
    final idx = fifths + 7;
    if (idx < 0 || idx >= order.length) return 'C';
    return order[idx];
  }

  static int intervalClass(int midi1, int midi2) =>
      (midi1 - midi2).abs() % 12;

  static String stepAtDiatonic(String fromStep, int genericIntervalMinus1) {
    final idx = steps.indexOf(fromStep);
    if (idx == -1) return 'C';
    return steps[(idx + genericIntervalMinus1) % 7];
  }

  static int _closestScaleDegree(int pitchClass, List<int> scale) {
    var best = 0;
    var bestDist = 12;
    for (var idx = 0; idx < scale.length; idx++) {
      final pc = scale[idx];
      final dist = [
        (pc - pitchClass).abs(),
        12 - (pc - pitchClass).abs(),
      ].reduce((a, b) => a < b ? a : b);
      if (dist < bestDist) {
        bestDist = dist;
        best = idx;
      }
    }
    return best;
  }
}
