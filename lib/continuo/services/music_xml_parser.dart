import 'package:xml/xml.dart';

import '../models/measure.dart';
import '../models/note.dart';
import '../models/score.dart';
import 'pitch_helper.dart';

/// Parses a MusicXML file and returns a [Score] with bass notes and any
/// figured bass annotations.
///
/// Supports:
///  - Single-part scores (takes the part or last part as bass)
///  - Multi-part scores (uses lowest pitched part as bass)
///  - Figured bass encoded as `<figured-bass>` elements (MusicXML 3.x/4.x)
///  - Figured bass encoded as `<lyric>` elements using the Figurato font
///    (Finale exports)
///  - Grand-staff keyboard parts: reads bass staff (staff 2) notes, not
///    treble (staff 1)
///  - Key and time signatures (including mid-score changes)
///  - Minor key detection workaround for Finale's incorrect exports
class MusicXmlParser {
  /// Parses [xmlContent] (a MusicXML string) and returns a populated [Score].
  Score parse(String xmlContent) {
    final document = XmlDocument.parse(xmlContent);
    final root = document.rootElement;
    final score = Score();

    // --- Metadata ---
    final workTitle = root
        .findAllElements('work-title')
        .firstOrNull
        ?.innerText
        .trim();
    if (workTitle != null && workTitle.isNotEmpty) {
      score.title = workTitle;
    }

    final creator = root
        .findAllElements('creator')
        .firstOrNull
        ?.innerText
        .trim();
    if (creator != null && creator.isNotEmpty) {
      score.composer = creator;
    }

    // --- Detect Figurato lyric font (Finale-style figured bass via lyrics) ---
    var isFigurato = false;
    for (final defaults in root.findAllElements('defaults')) {
      for (final child in defaults.childElements) {
        if (child.name.local == 'lyric-font') {
          final family =
              (child.getAttribute('font-family') ?? '').toLowerCase();
          if (family.contains('figurato')) {
            isFigurato = true;
            break;
          }
        }
      }
      if (isFigurato) break;
    }

    // --- Determine which part to use as bass (lowest part) ---
    final parts = root.findAllElements('part').toList();
    if (parts.isEmpty) {
      throw ArgumentError('No parts found in MusicXML file.');
    }

    // If multiple parts, choose the one with the lowest average pitch
    final bassPart = _selectBassPart(parts);

    // Identify the melody part: highest-pitched part other than the bass.
    // Returns null when there is only one part (no separate melody line).
    final melodyPart = _selectMelodyPart(parts, bassPart);

    // --- Detect number of staves for the selected bass part ---
    // Grand-staff keyboard parts have staves=2; the bass staff is staff 2.
    var numStaves = _detectNumStaves(bassPart);

    // --- Global defaults ---
    var currentDivisions = 1;

    score.keyFifths = 0;
    score.keyMode = 'major';
    score.beats = 4;
    score.beatType = 4;
    score.divisions = 1;

    for (final measureXml in bassPart.findElements('measure')) {
      final measureNum =
          int.tryParse(measureXml.getAttribute('number') ?? '') ?? 0;
      final measure = Measure(measureNum);

      // --- Attributes ---
      for (final attr in measureXml.findElements('attributes')) {
        final divisionsEl = attr.findElements('divisions').firstOrNull;
        if (divisionsEl != null) {
          currentDivisions = int.tryParse(divisionsEl.innerText) ?? 1;
          score.divisions = currentDivisions;
        }

        final stavesEl = attr.findElements('staves').firstOrNull;
        if (stavesEl != null) {
          // Update staves count if it changes mid-score (unusual but handle it)
          numStaves = (int.tryParse(stavesEl.innerText) ?? 1).clamp(1, 99);
        }

        final keyEl = attr.findElements('key').firstOrNull;
        if (keyEl != null) {
          final fifths = int.tryParse(
                keyEl.findElements('fifths').firstOrNull?.innerText ?? '',
              ) ??
              0;
          final modeRaw =
              (keyEl.findElements('mode').firstOrNull?.innerText ?? '').trim();
          final mode = modeRaw.isNotEmpty ? modeRaw : 'major';
          score.keyFifths = fifths;
          score.keyMode = mode;
          // Record key on the measure only when explicitly present in the XML
          measure.keySignature = {'fifths': fifths, 'mode': mode};
        }

        final timeEl = attr.findElements('time').firstOrNull;
        if (timeEl != null) {
          final beats = int.tryParse(
                timeEl.findElements('beats').firstOrNull?.innerText ?? '',
              ) ??
              4;
          final beatType = int.tryParse(
                timeEl.findElements('beat-type').firstOrNull?.innerText ?? '',
              ) ??
              4;
          score.beats = beats;
          score.beatType = beatType;
        }
      }

      // --- Notes and figured bass (single pass, position-aware) ---
      //
      // For single-staff parts: accept voice 1 notes only (standard behaviour).
      // For grand-staff (numStaves > 1): accept notes from the bass staff
      //   (highest-numbered staff, typically staff 2), regardless of voice
      //   number.
      //
      // Figured bass may be encoded as:
      //   (a) <figured-bass> elements appearing after the note (MusicXML
      //       standard)
      //   (b) <lyric> text using the Figurato font encoding (Finale exports)

      int? lastNoteIdx;

      for (final child in measureXml.childElements) {
        final name = child.name.local;

        if (name == 'note') {
          // --- Staff / voice filtering ---
          final isChord = child.findElements('chord').isNotEmpty;
          if (isChord) {
            // Chord (simultaneous) notes: skip -- the primary note per beat
            // is what we need.
            continue;
          }

          if (numStaves > 1) {
            // Grand-staff: only read from the bass staff (highest staff number)
            final staffNum = int.tryParse(
                  child.findElements('staff').firstOrNull?.innerText ?? '',
                ) ??
                1;
            if (staffNum != numStaves) {
              continue;
            }
          } else {
            // Single-staff: voice 1 only
            final voice = int.tryParse(
                  child.findElements('voice').firstOrNull?.innerText ?? '',
                ) ??
                1;
            if (voice != 1) {
              continue;
            }
          }

          final isRest = child.findElements('rest').isNotEmpty;
          final dur = int.tryParse(
                child.findElements('duration').firstOrNull?.innerText ?? '',
              ) ??
              0;
          final type =
              child.findElements('type').firstOrNull?.innerText ?? 'quarter';

          final durationInQuarters = currentDivisions > 0
              ? _round6(dur / currentDivisions)
              : 1.0;

          final voiceNum = int.tryParse(
                child.findElements('voice').firstOrNull?.innerText ?? '',
              ) ??
              1;

          Note note;
          if (isRest) {
            note = Note(
              step: 'C',
              octave: 4,
              duration: durationInQuarters,
              isRest: true,
              type: type,
              voice: voiceNum,
            );
          } else {
            final pitchEl = child.findElements('pitch').firstOrNull;
            final step =
                pitchEl?.findElements('step').firstOrNull?.innerText ?? 'C';
            final oct = int.tryParse(
                  pitchEl?.findElements('octave').firstOrNull?.innerText ?? '',
                ) ??
                4;
            final alterDouble = double.tryParse(
                  pitchEl?.findElements('alter').firstOrNull?.innerText ?? '',
                ) ??
                0.0;
            final alter = alterDouble.round();

            note = Note(
              step: step,
              octave: oct,
              duration: durationInQuarters,
              alter: alter,
              type: type,
              isRest: false,
              voice: voiceNum,
            );
          }

          // --- Figurato lyric figured bass (Finale exports) ---
          // When the file uses the Figurato font, <lyric> elements on bass
          // notes carry the figured bass in Figurato encoding.
          if (isFigurato && !isRest) {
            final lyricText = _extractLyricText(child);
            if (lyricText.isNotEmpty) {
              final figures = parseFiguratoString(lyricText);
              if (figures.isNotEmpty) {
                note = note.withFiguredBass(
                  figures.map((f) => f['number'] as int).toList(),
                );
              }
            }
          }

          lastNoteIdx = measure.bassNotes.length;
          measure.bassNotes.add(note);
        } else if (name == 'figured-bass' && lastNoteIdx != null) {
          // MusicXML standard <figured-bass> element -- parse figures and
          // attach
          final figures = <int>[];
          for (final fig in child.findElements('figure')) {
            final prefix =
                fig.findElements('prefix').firstOrNull?.innerText ?? '';
            final num = int.tryParse(
                  fig.findElements('figure-number').firstOrNull?.innerText ??
                      '',
                ) ??
                0;
            final suffix =
                fig.findElements('suffix').firstOrNull?.innerText ?? '';

            // Parse alter from prefix/suffix (for future use -- currently the
            // Dart Note model stores only figure numbers, but the alter info
            // is computed here faithfully following the PHP original)
            // ignore: unused_local_variable
            var alter = 0;
            if (prefix == 'sharp' || suffix == 'sharp') {
              alter = 1;
            } else if (prefix == 'flat' || suffix == 'flat') {
              alter = -1;
            } else if (prefix == 'natural') {
              alter = 0;
            }

            if (num > 0) {
              figures.add(num);
            }
          }

          if (figures.isNotEmpty) {
            measure.bassNotes[lastNoteIdx] =
                measure.bassNotes[lastNoteIdx].withFiguredBass(figures);
          }
        }
      }

      if (measure.bassNotes.isNotEmpty) {
        score.measures.add(measure);
      }
    }

    // --- Second pass: annotate measures with melody notes (if available) ---
    if (melodyPart != null && score.measures.isNotEmpty) {
      _parseMelodyIntoMeasures(melodyPart, score.measures);
    }

    // --- Mode-detection pass ---
    // Finale (and some other editors) export minor-key pieces with
    // mode="major" and the relative major key signature (e.g. E minor ->
    // 1 sharp, mode=major).  Detect this by checking whether the last
    // non-rest bass note lands on the relative-minor tonic: if so, the
    // piece is in minor.
    if (score.keyMode == 'major' && score.measures.isNotEmpty) {
      Note? lastNote;
      outer:
      for (final measure in score.measures.reversed) {
        for (final note in measure.bassNotes.reversed) {
          if (!note.isRest) {
            lastNote = note;
            break outer;
          }
        }
      }

      if (lastNote != null) {
        final majorScale = PitchHelper.buildScale(score.keyFifths, 'major');
        // degree 6 of major = relative-minor tonic (index 5, zero-based)
        final relMinorTonicPc = majorScale[5];
        if (lastNote.pitchClass() == relMinorTonicPc) {
          score.keyMode = 'minor';
          for (final measure in score.measures) {
            if (measure.keySignature != null &&
                (measure.keySignature!['mode'] as String?) == 'major') {
              measure.keySignature!['mode'] = 'minor';
            }
          }
        }
      }
    }

    return score;
  }

  // ---------------------------------------------------------------------------
  // extractLyricText
  // ---------------------------------------------------------------------------

  /// Extracts the text of the first `<lyric>` element of a note.
  /// Returns `''` if no lyric is present.
  String _extractLyricText(XmlElement noteXml) {
    for (final lyric in noteXml.findElements('lyric')) {
      final text =
          (lyric.findElements('text').firstOrNull?.innerText ?? '').trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  // ---------------------------------------------------------------------------
  // parseFiguratoString
  // ---------------------------------------------------------------------------

  /// Parses a Figurato-font figured bass string into a list of figure maps.
  ///
  /// Figurato encoding rules:
  ///   - Digits 2-9 represent intervals/figures.
  ///   - Accidentals immediately FOLLOWING a digit modify that figure:
  ///       `b` = flat (-1),  `s` or `#` = sharp (+1),  `n` = natural (0,
  ///       explicit), `/` or `+` = raised (+1, slash-through or augmented),
  ///       `x` = double-sharp (+2)
  ///   - A comma `,` separates independently stacked groups.
  ///   - A standalone accidental (not immediately after a digit) applies to
  ///     the 3rd.
  ///
  /// Examples:
  /// ```
  ///   "6"     -> [{6, 0}]            "6b"    -> [{6, -1}]
  ///   "6/"    -> [{6, +1}]           "4+"    -> [{4, +1}]
  ///   "65"    -> [{6,0},{5,0}]       "65b"   -> [{6,0},{5,-1}]
  ///   "6/5b"  -> [{6,+1},{5,-1}]     "643"   -> [{6,0},{4,0},{3,0}]
  ///   "7,b"   -> [{7,0},{3,-1}]      "s"     -> [{3,+1}]
  ///   "4+2+"  -> [{4,+1},{2,+1}]     "7ns"   -> [{7,0,explicit},{3,+1}]
  /// ```
  ///
  /// Returns a list of `{'number': int, 'alter': int}` maps (with optional
  /// `'explicit': true`).
  List<Map<String, dynamic>> parseFiguratoString(String text) {
    text = text.trim();
    if (text.isEmpty) {
      return [];
    }

    final figures = <Map<String, dynamic>>[];

    // Split by comma: each segment is an independently stacked figure group.
    final groups = text.split(',');

    for (var group in groups) {
      group = group.trim();
      final len = group.length;
      var i = 0;

      while (i < len) {
        final c = group[i];

        if (_isDigit(c)) {
          final num = int.parse(c);
          var alter = 0;
          var explicit = false;
          i++;

          // Look for an accidental suffix immediately following this digit
          if (i < len) {
            final next = group[i];
            switch (next) {
              case 'b':
                alter = -1;
                i++;
              case 's':
              case '#':
                alter = 1;
                i++;
              case 'n':
                alter = 0;
                explicit = true;
                i++;
              case '/':
              case '+':
                alter = 1;
                i++;
              case 'x':
                alter = 2;
                i++;
            }
          }

          // Ignore invalid figure numbers (0, 1 are not real intervals)
          if (num >= 2) {
            final fig = <String, dynamic>{'number': num, 'alter': alter};
            if (explicit) {
              fig['explicit'] = true;
            }
            figures.add(fig);
          }
        } else {
          // Standalone accidental -- applies to the 3rd by convention
          var alter = 0;
          var explicit = false;
          var skip = false;
          switch (c) {
            case 'b':
              alter = -1;
            case 's':
            case '#':
              alter = 1;
            case 'n':
              alter = 0;
              explicit = true;
            case '/':
            case '+':
              alter = 1;
            case 'x':
              alter = 2;
            default:
              i++;
              skip = true; // skip unknown characters
          }
          if (!skip) {
            final fig = <String, dynamic>{'number': 3, 'alter': alter};
            if (explicit) {
              fig['explicit'] = true;
            }
            figures.add(fig);
            i++;
          }
        }
      }
    }

    return figures;
  }

  // ---------------------------------------------------------------------------
  // selectMelodyPart
  // ---------------------------------------------------------------------------

  /// Returns the highest-pitched part other than the bass part (the melody).
  /// Returns `null` when there is only one part (no separate melody).
  /// Uses the MusicXML part `id` attribute to exclude the bass part.
  XmlElement? _selectMelodyPart(List<XmlElement> parts, XmlElement bassPart) {
    if (parts.length <= 1) {
      return null;
    }

    final bassId = bassPart.getAttribute('id') ?? '';
    XmlElement? bestPart;
    var bestAvg = -1e18; // equivalent to PHP_INT_MIN for doubles

    for (final part in parts) {
      if ((part.getAttribute('id') ?? '') == bassId) {
        continue; // skip the bass part
      }

      final pitches = <int>[];
      for (final noteXml in part.findAllElements('note')) {
        // Skip rests
        if (noteXml.findElements('rest').isNotEmpty) continue;
        final pitchEl = noteXml.findElements('pitch').firstOrNull;
        if (pitchEl == null) continue;

        final step =
            pitchEl.findElements('step').firstOrNull?.innerText ?? 'C';
        final oct = int.tryParse(
              pitchEl.findElements('octave').firstOrNull?.innerText ?? '',
            ) ??
            4;
        final alterDouble = double.tryParse(
              pitchEl.findElements('alter').firstOrNull?.innerText ?? '',
            ) ??
            0.0;
        final alter = alterDouble.round();
        final midi = (oct + 1) * 12 + (_stepToSemitone[step] ?? 0) + alter;
        pitches.add(midi);
      }

      if (pitches.isNotEmpty) {
        final avg = pitches.reduce((a, b) => a + b) / pitches.length;
        if (avg > bestAvg) {
          bestAvg = avg;
          bestPart = part;
        }
      }
    }

    return bestPart;
  }

  // ---------------------------------------------------------------------------
  // parseMelodyIntoMeasures
  // ---------------------------------------------------------------------------

  /// Parses melody notes from [melodyPart] and stores them in the
  /// corresponding [Measure] objects (matched by measure number).
  ///
  /// Only voice-1, non-chord, non-rest notes are recorded.  Backup/forward
  /// elements are handled so that the beat offset stays correct even in
  /// multi-voice melody parts.
  void _parseMelodyIntoMeasures(
    XmlElement melodyPart,
    List<Measure> measures,
  ) {
    // Build a lookup: measure number -> Measure object
    final measureMap = <int, Measure>{};
    for (final m in measures) {
      measureMap[m.number] = m;
    }

    var currentDivisions = 1;

    for (final measureXml in melodyPart.findElements('measure')) {
      final measureNum =
          int.tryParse(measureXml.getAttribute('number') ?? '') ?? 0;
      final measure = measureMap[measureNum];

      // Update divisions from attributes
      for (final attr in measureXml.findElements('attributes')) {
        final divisionsEl = attr.findElements('divisions').firstOrNull;
        if (divisionsEl != null) {
          currentDivisions = int.tryParse(divisionsEl.innerText) ?? 1;
        }
      }

      var beatOffset = 0.0;

      for (final child in measureXml.childElements) {
        final name = child.name.local;

        if (name == 'note') {
          final isChord = child.findElements('chord').isNotEmpty;
          final dur = int.tryParse(
                child.findElements('duration').firstOrNull?.innerText ?? '',
              ) ??
              0;
          final dq = currentDivisions > 0
              ? _round6(dur / currentDivisions)
              : 1.0;

          if (isChord) {
            continue; // chord notes don't advance the beat cursor
          }

          final voice = int.tryParse(
                child.findElements('voice').firstOrNull?.innerText ?? '',
              ) ??
              1;

          if (voice == 1 &&
              child.findElements('rest').isEmpty &&
              measure != null) {
            final pitchEl = child.findElements('pitch').firstOrNull;
            final step =
                pitchEl?.findElements('step').firstOrNull?.innerText ?? 'C';
            final alterDouble = double.tryParse(
                  pitchEl?.findElements('alter').firstOrNull?.innerText ?? '',
                ) ??
                0.0;
            final alter = alterDouble.round();
            final pc =
                ((_stepToSemitone[step] ?? 0) + alter + 12) % 12;

            measure.melodyNotes.add(MelodyNote(
              offset: beatOffset,
              duration: dq,
              pitchClass: pc,
            ));
          }

          beatOffset += dq;
        } else if (name == 'backup') {
          final dur = int.tryParse(
                child.findElements('duration').firstOrNull?.innerText ?? '',
              ) ??
              0;
          final dq = currentDivisions > 0 ? dur / currentDivisions : 0.0;
          beatOffset = (beatOffset - dq).clamp(0.0, double.infinity);
        } else if (name == 'forward') {
          final dur = int.tryParse(
                child.findElements('duration').firstOrNull?.innerText ?? '',
              ) ??
              0;
          final dq = currentDivisions > 0 ? dur / currentDivisions : 0.0;
          beatOffset += dq;
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // detectNumStaves
  // ---------------------------------------------------------------------------

  /// Detects how many staves a part uses (from its first `<staves>` attribute
  /// element).  Returns 1 for single-staff parts, 2 for grand-staff keyboard
  /// parts, etc.
  int _detectNumStaves(XmlElement part) {
    for (final attr in part.findAllElements('attributes')) {
      final stavesEl = attr.findElements('staves').firstOrNull;
      if (stavesEl != null) {
        final n = int.tryParse(stavesEl.innerText) ?? 1;
        return n < 1 ? 1 : n;
      }
    }
    return 1;
  }

  // ---------------------------------------------------------------------------
  // selectBassPart
  // ---------------------------------------------------------------------------

  /// Chooses the part with the lowest average MIDI pitch (the bass part).
  XmlElement _selectBassPart(List<XmlElement> parts) {
    if (parts.length == 1) {
      return parts[0];
    }

    var bestPart = parts.last; // default: last part
    var bestAvg = 1e18; // equivalent to PHP_INT_MAX for doubles

    for (final part in parts) {
      final pitches = <int>[];
      for (final noteXml in part.findAllElements('note')) {
        // Skip rests
        if (noteXml.findElements('rest').isNotEmpty) continue;
        final pitchEl = noteXml.findElements('pitch').firstOrNull;
        if (pitchEl == null) continue;

        final step =
            pitchEl.findElements('step').firstOrNull?.innerText ?? 'C';
        final oct = int.tryParse(
              pitchEl.findElements('octave').firstOrNull?.innerText ?? '',
            ) ??
            4;
        final alterDouble = double.tryParse(
              pitchEl.findElements('alter').firstOrNull?.innerText ?? '',
            ) ??
            0.0;
        final alter = alterDouble.round();
        final midi = (oct + 1) * 12 + (_stepToSemitone[step] ?? 0) + alter;
        pitches.add(midi);
      }

      if (pitches.isNotEmpty) {
        final avg = pitches.reduce((a, b) => a + b) / pitches.length;
        if (avg < bestAvg) {
          bestAvg = avg;
          bestPart = part;
        }
      }
    }

    return bestPart;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static const _stepToSemitone = {
    'C': 0,
    'D': 2,
    'E': 4,
    'F': 5,
    'G': 7,
    'A': 9,
    'B': 11,
  };

  /// Returns `true` if [c] is an ASCII digit ('0'-'9').
  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  /// Rounds [value] to 6 decimal places, matching the PHP `round($v, 6)`.
  static double _round6(double value) {
    // Multiply, round, divide -- avoids floating point noise.
    return (value * 1e6).roundToDouble() / 1e6;
  }
}
