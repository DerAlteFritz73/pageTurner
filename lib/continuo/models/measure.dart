import 'chord.dart';
import 'note.dart';

class MelodyNote {
  final double offset; // quarter-note units from measure start
  final double duration;
  final int pitchClass; // 0-11

  const MelodyNote({
    required this.offset,
    required this.duration,
    required this.pitchClass,
  });
}

class Measure {
  final int number;
  final List<Note> bassNotes = [];
  final List<Chord> realizedChords = [];
  final List<MelodyNote> melodyNotes = [];

  Map<String, dynamic>? keySignature; // {'fifths': int, 'mode': String}
  Map<String, int>? timeSignature; // {'beats': int, 'beatType': int}

  Measure(this.number);
}
