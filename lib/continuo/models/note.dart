class Note {
  final String step; // C, D, E, F, G, A, B
  final int octave;
  final double duration; // quarter note = 1.0
  final int alter; // -1=flat, 0=natural, 1=sharp
  final String type; // 'quarter', 'half', 'whole', etc.
  final bool isRest;
  final int? staff;
  final int? voice;
  final List<int> figuredBass; // figures on this note e.g. [6, 3]

  const Note({
    required this.step,
    required this.octave,
    this.duration = 1.0,
    this.alter = 0,
    this.type = 'quarter',
    this.isRest = false,
    this.staff,
    this.voice,
    this.figuredBass = const [],
  });

  static const _stepSemitones = {
    'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11,
  };

  int midiPitch() {
    if (isRest) return -1;
    return (octave + 1) * 12 + _stepSemitones[step]! + alter;
  }

  int pitchClass() => midiPitch() % 12;

  Note withOctave(int newOctave) => Note(
        step: step,
        octave: newOctave,
        duration: duration,
        alter: alter,
        type: type,
        isRest: isRest,
        staff: staff,
        voice: voice,
        figuredBass: figuredBass,
      );

  Note withFiguredBass(List<int> figures) => Note(
        step: step,
        octave: octave,
        duration: duration,
        alter: alter,
        type: type,
        isRest: isRest,
        staff: staff,
        voice: voice,
        figuredBass: figures,
      );

  Note withVoice(int? newVoice) => Note(
        step: step,
        octave: octave,
        duration: duration,
        alter: alter,
        type: type,
        isRest: isRest,
        staff: staff,
        voice: newVoice,
        figuredBass: figuredBass,
      );

  Note withDuration(double newDuration, String newType) => Note(
        step: step,
        octave: octave,
        duration: newDuration,
        alter: alter,
        type: newType,
        isRest: isRest,
        staff: staff,
        voice: voice,
        figuredBass: figuredBass,
      );

  @override
  String toString() {
    if (isRest) return 'R';
    final acc = switch (alter) { 1 => '#', -1 => 'b', _ => '' };
    return '$step$acc$octave';
  }
}
