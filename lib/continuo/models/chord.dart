import 'note.dart';
import '../services/figured_bass_interpreter.dart';

class Chord {
  final Note bass;
  final List<Figure> figures; // raw figured bass e.g. [Figure(7), Figure(5), Figure(3)]
  final String chordSymbol; // e.g. "I", "V7", "IV6"
  final List<Note> upperVoices; // soprano, alto, tenor
  final List<Map<String, dynamic>> decisionTrace;

  Chord({
    required this.bass,
    required this.figures,
    this.chordSymbol = '',
    List<Note>? upperVoices,
    List<Map<String, dynamic>>? decisionTrace,
  })  : upperVoices = upperVoices ?? [],
        decisionTrace = decisionTrace ?? [];

  void addUpperVoice(Note note) => upperVoices.add(note);

  List<Note> allNotes() => [bass, ...upperVoices];

  Set<int> pitchClasses() =>
      allNotes().map((n) => n.pitchClass()).toSet();
}
