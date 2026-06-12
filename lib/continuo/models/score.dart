import 'measure.dart';

class Score {
  final List<Measure> measures = [];
  String? title;
  String? composer;
  int keyFifths = 0; // -7..7
  String keyMode = 'major'; // 'major' or 'minor'
  int beats = 4;
  int beatType = 4;
  int divisions = 1;

  static const _majorTonics = {
    -7: 'Cb', -6: 'Gb', -5: 'Db', -4: 'Ab', -3: 'Eb', -2: 'Bb', -1: 'F',
    0: 'C', 1: 'G', 2: 'D', 3: 'A', 4: 'E', 5: 'B', 6: 'F#', 7: 'C#',
  };

  static const _minorTonics = {
    -7: 'Ab', -6: 'Eb', -5: 'Bb', -4: 'F', -3: 'C', -2: 'G', -1: 'D',
    0: 'A', 1: 'E', 2: 'B', 3: 'F#', 4: 'C#', 5: 'G#', 6: 'D#', 7: 'A#',
  };

  String tonic() {
    final map = keyMode == 'minor' ? _minorTonics : _majorTonics;
    return map[keyFifths] ?? 'C';
  }
}
