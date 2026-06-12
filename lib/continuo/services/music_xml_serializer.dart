import 'package:xml/xml.dart';

import '../models/measure.dart';
import '../models/note.dart';
import '../models/score.dart';
import 'figured_bass_interpreter.dart';

/// Serializes a realized [Score] back to MusicXML format.
///
/// Output structure (MusicXML 4.0) -- single grand-staff part:
///  Staff 1 / treble: Voice 1 -- soprano + any other upper voice whose consolidated
///                    duration matches soprano at the same beat (shared stem chord).
///                    Voice 2 -- unplaced alto entries (consolidated duration differed
///                    from soprano), written with `<forward>` gaps.
///                    Voice 3 -- unplaced tenor entries, same treatment.
///  Staff 2 / bass:   Voice 4 -- original bass note with figured bass markings.
///
/// Per-voice consolidation ([consolidateVoicePart]) runs independently for soprano,
/// alto, and tenor.  At each beat position the durations are compared:
///  - same duration -> chord member in voice 1 (single stem)
///  - different duration -> deferred to voice 2 (alto) or voice 3 (tenor)
///
/// Keeping alto and tenor in separate MusicXML voices avoids the time-overlap
/// problem that arises when consolidated alto and tenor entries span different
/// beat ranges: a single-voice stream is always non-overlapping, so a simple
/// forward-only cursor is sufficient.
///
/// Measure layout:
///  Pass 1: voice 1 (soprano + chord-grouped alto/tenor) -> (cursor at measureDur)
///  Pass 2: backup -> voice 2 (unplaced alto, `<forward>` gaps) -> (cursor at v2End)
///          (omitted when all alto notes are chord-grouped)
///  Pass 3: backup -> voice 3 (unplaced tenor, `<forward>` gaps) -> (cursor at v3End)
///          (omitted when all tenor notes are chord-grouped)
///  Pass 4: backup -> bass voice 4 (no trailing backup)
///
/// Click-tracking xml:ids:
///  Soprano notes carry xml:id="chord-{N}" (N = global chord-store index).
///  Bass notes carry xml:id="bass-{N}".
///
/// Figure coloring:
///  - Figures from the input score ("file"): default black
///  - Figures computed by the decision tree: COMPUTED_FIGURE_COLOR (muted indigo)
///
/// Beaming:
///  - Notes shorter than the beat unit are beamed in groups per beat.
///  - Compound meters (6/8, 9/8, 12/8): beam in dotted-quarter groups (3 eighths).
///  - Simple meters: beam within each beat.
///  - Rests break beam groups.
class MusicXmlSerializer {
  const MusicXmlSerializer();

  // -------------------------------------------------------------------------
  // Public: full realization (grand staff)
  // -------------------------------------------------------------------------

  String serialize(Score score) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('score-partwise', attributes: {'version': '4.0'}, nest: () {
      // --- Work / Identification ---
      if (score.title != null && score.title!.isNotEmpty) {
        builder.element('work', nest: () {
          builder.element('work-title',
              nest: '${score.title} (Continuo Realization)');
        });
      }

      builder.element('identification', nest: () {
        builder.element('encoding', nest: () {
          builder.element('software', nest: 'Continuo Realizer (Flutter)');
          builder.element('encoding-date', nest: _todayString());
        });
      });

      // --- Part list ---
      builder.element('part-list', nest: () {
        builder.element('score-part', attributes: {'id': 'P1'}, nest: () {
          builder.element('part-name', nest: 'Realization');
          builder.element('score-instrument',
              attributes: {'id': 'P1-I1'}, nest: () {
            builder.element('instrument-name', nest: 'Harpsichord');
          });
        });
      });

      // --- Single part: realized continuo (grand staff, bass + upper voices) ---
      builder.element('part', attributes: {'id': 'P1'}, nest: () {
        var isFirst = true;
        var currentKeyFifths = score.keyFifths;
        var currentBeats = score.beats;
        var currentBeatType = score.beatType;
        var globalIdx = 0;

        for (final measure in score.measures) {
          if (measure.keySignature != null) {
            currentKeyFifths =
                measure.keySignature!['fifths'] as int? ?? currentKeyFifths;
          }
          if (measure.timeSignature != null) {
            currentBeats =
                measure.timeSignature!['beats'] ?? currentBeats;
            currentBeatType =
                measure.timeSignature!['beatType'] ?? currentBeatType;
          }
          globalIdx = _buildRealizationMeasure(
            builder,
            measure,
            score,
            isFirst,
            currentKeyFifths,
            currentBeats,
            currentBeatType,
            globalIdx,
          );
          isFirst = false;
        }
      });
    });

    return builder.buildDocument().toXmlString(pretty: true);
  }

  // -------------------------------------------------------------------------
  // Public: clean bass-line MusicXML (single staff, with correct accidentals)
  // -------------------------------------------------------------------------

  String serializeBassLine(Score score) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('score-partwise', attributes: {'version': '4.0'}, nest: () {
      if (score.title != null && score.title!.isNotEmpty) {
        builder.element('work', nest: () {
          builder.element('work-title', nest: score.title!);
        });
      }

      builder.element('part-list', nest: () {
        builder.element('score-part', attributes: {'id': 'P1'}, nest: () {
          builder.element('part-name', nest: 'Bass');
        });
      });

      builder.element('part', attributes: {'id': 'P1'}, nest: () {
        var isFirst = true;
        var currentKeyFifths = score.keyFifths;
        var currentKeyMode = score.keyMode;
        var currentBeats = score.beats;
        var currentBeatType = score.beatType;

        for (final measure in score.measures) {
          if (measure.keySignature != null) {
            currentKeyFifths =
                measure.keySignature!['fifths'] as int? ?? currentKeyFifths;
            currentKeyMode =
                measure.keySignature!['mode'] as String? ?? currentKeyMode;
          }
          if (measure.timeSignature != null) {
            currentBeats =
                measure.timeSignature!['beats'] ?? currentBeats;
            currentBeatType =
                measure.timeSignature!['beatType'] ?? currentBeatType;
          }
          _buildBassMeasureClean(
            builder,
            measure,
            score,
            isFirst,
            currentKeyFifths,
            currentKeyMode,
            currentBeats,
            currentBeatType,
          );
          isFirst = false;
        }
      });
    });

    return builder.buildDocument().toXmlString(pretty: true);
  }

  // -------------------------------------------------------------------------
  // Part 1: Bass line (single staff, bass clef) -- for original display
  // -------------------------------------------------------------------------

  void _buildBassMeasureClean(
    XmlBuilder builder,
    Measure measure,
    Score score,
    bool isFirst,
    int keyFifths,
    String keyMode,
    int beats,
    int beatType,
  ) {
    // Collect all elements first so beam markers can be applied before writing.
    final elements = <_MeasureElement>[];

    if (isFirst) {
      elements.add(_MeasureElement.attributes((b) {
        b.element('attributes', nest: () {
          b.element('divisions', nest: score.divisions.toString());
          _keyElement(b, keyFifths, keyMode);
          _timeElement(b, score.beats, score.beatType);
          b.element('clef', nest: () {
            b.element('sign', nest: 'F');
            b.element('line', nest: '4');
          });
        });
      }));
    } else if (measure.keySignature != null) {
      elements.add(_MeasureElement.attributes(
          (b) => _buildKeyChangeAttributes(b, measure)));
    }

    final acc = <String, int>{};
    final bassBeamItems = <_BeamItem>[];

    for (final note in measure.bassNotes) {
      final accidental = _resolveAccidental(note, acc, keyFifths);
      final dur = _durationTicks(note.duration, score.divisions);
      final noteXml = _noteXml(note, 1, score.divisions, 1, false,
          accidental: accidental);
      bassBeamItems.add(_BeamItem(noteXml, dur, note.isRest));
      elements.add(_MeasureElement.note(noteXml));

      // Figured-bass must appear AFTER its note so that on re-submission the
      // parser's lastNoteIdx approach (which attaches figures to the preceding
      // note) correctly picks them up.
      if (note.figuredBass.isNotEmpty) {
        final figures = note.figuredBass
            .map((n) => Figure(number: n))
            .toList();
        elements.add(_MeasureElement.figuredBass(figures, false));
      }
    }

    _applyBeams(bassBeamItems, beats, beatType, score.divisions);

    // Write the complete measure
    builder.element('measure',
        attributes: {'number': measure.number.toString()}, nest: () {
      for (final elem in elements) {
        elem.writeTo(builder);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Part 2: Grand staff realization (2 staves, treble + bass)
  // -------------------------------------------------------------------------

  /// Returns the updated globalIdx after processing this measure.
  int _buildRealizationMeasure(
    XmlBuilder builder,
    Measure measure,
    Score score,
    bool isFirst,
    int currentKeyFifths,
    int beats,
    int beatType,
    int globalIdx,
  ) {
    // We need to build the measure content using intermediate XML structures
    // because beam elements are applied retroactively after collecting all notes.
    // We'll build as XmlDocument fragments and then serialize into the builder.

    final keyFifths = currentKeyFifths;

    // Build a map: local beat index -> global chord-store index.
    final origGlobalIdx = <int, int?>{};
    for (var i = 0; i < measure.bassNotes.length; i++) {
      final bassNote = measure.bassNotes[i];
      if (!bassNote.isRest &&
          i < measure.realizedChords.length) {
        origGlobalIdx[i] = globalIdx++;
      } else {
        origGlobalIdx[i] = null;
      }
    }

    final measureDur = measure.bassNotes.fold<int>(
        0, (sum, n) => sum + _durationTicks(n.duration, score.divisions));

    // Build per-voice consolidated streams
    final sStream = _consolidateVoicePart(measure, 0, score.divisions);
    final aStream = _consolidateVoicePart(measure, 1, score.divisions);
    final tStream = _consolidateVoicePart(measure, 2, score.divisions);

    // Index alto and tenor by their first covered origIdx
    final aByIdx = <int, _PlacedEntry>{};
    for (final entry in aStream) {
      aByIdx[entry.origIdxs[0]] = _PlacedEntry(entry: entry);
    }
    final tByIdx = <int, _PlacedEntry>{};
    for (final entry in tStream) {
      tByIdx[entry.origIdxs[0]] = _PlacedEntry(entry: entry);
    }

    // Cumulative bass-note positions (quarter-note units from measure start)
    final bassPos = <int, double>{};
    var cumPosQ = 0.0;
    for (var i = 0; i < measure.bassNotes.length; i++) {
      bassPos[i] = cumPosQ;
      cumPosQ += measure.bassNotes[i].duration;
    }

    // Collect all elements for this measure in order
    final measureElements = <_MeasureElement>[];

    // First element: attributes
    if (isFirst) {
      measureElements.add(_MeasureElement.attributes(
          (b) => _buildGrandStaffAttributes(b, score)));
    } else if (measure.keySignature != null) {
      measureElements.add(_MeasureElement.attributes(
          (b) => _buildKeyChangeAttributes(b, measure)));
    }

    // -- Pass 1: voice 1 (soprano primary + chord-grouped alto/tenor) --
    final accV1 = <String, int>{};
    final v1BeamItems = <_BeamItem>[];

    for (final sEntry in sStream) {
      final firstIdx = sEntry.origIdxs[0];
      final sDq = sEntry.dq;
      final dur = _durationTicks(sDq, score.divisions);

      if (sEntry.isRest) {
        final rest = Note(
            step: 'C', octave: 4, duration: sDq, type: sEntry.type,
            isRest: true);
        final noteData = _noteXml(rest, 1, score.divisions, 1, false,
            durationOverride: sDq, typeOverride: sEntry.type,
            dot: sEntry.dot);
        v1BeamItems.add(_BeamItem(noteData, dur, true));
        measureElements.add(_MeasureElement.note(noteData));

        // Suppress alto/tenor rests from appearing in voice-2 pass
        if (aByIdx.containsKey(firstIdx) && aByIdx[firstIdx]!.entry.isRest) {
          aByIdx[firstIdx]!.placed = true;
        }
        if (tByIdx.containsKey(firstIdx) && tByIdx[firstIdx]!.entry.isRest) {
          tByIdx[firstIdx]!.placed = true;
        }
      } else {
        // Write soprano note
        final acc = _resolveAccidental(sEntry.note!, accV1, keyFifths);
        final noteData = _noteXml(sEntry.note!, 1, score.divisions, 1, false,
            accidental: acc, durationOverride: sDq, typeOverride: sEntry.type,
            dot: sEntry.dot);
        final gIdx = origGlobalIdx[firstIdx];
        if (gIdx != null) {
          noteData.xmlId = 'chord-$gIdx';
        }
        v1BeamItems.add(_BeamItem(noteData, dur, false));
        measureElements.add(_MeasureElement.note(noteData));

        // Alto: chord-group if same start position and same duration
        if (aByIdx.containsKey(firstIdx) &&
            !aByIdx[firstIdx]!.placed &&
            !aByIdx[firstIdx]!.entry.isRest &&
            (aByIdx[firstIdx]!.entry.dq - sDq).abs() < 0.001) {
          final aEntry = aByIdx[firstIdx]!.entry;
          final aAcc = _resolveAccidental(aEntry.note!, accV1, keyFifths);
          final chordData = _noteXml(
              aEntry.note!, 1, score.divisions, 1, true,
              accidental: aAcc, durationOverride: sDq,
              typeOverride: sEntry.type, dot: sEntry.dot);
          measureElements.add(_MeasureElement.note(chordData));
          aByIdx[firstIdx]!.placed = true;
        }

        // Tenor: chord-group if same start position and same duration
        if (tByIdx.containsKey(firstIdx) &&
            !tByIdx[firstIdx]!.placed &&
            !tByIdx[firstIdx]!.entry.isRest &&
            (tByIdx[firstIdx]!.entry.dq - sDq).abs() < 0.001) {
          final tEntry = tByIdx[firstIdx]!.entry;
          final tAcc = _resolveAccidental(tEntry.note!, accV1, keyFifths);
          final chordData = _noteXml(
              tEntry.note!, 1, score.divisions, 1, true,
              accidental: tAcc, durationOverride: sDq,
              typeOverride: sEntry.type, dot: sEntry.dot);
          measureElements.add(_MeasureElement.note(chordData));
          tByIdx[firstIdx]!.placed = true;
        }
      }
    }
    _applyBeams(v1BeamItems, beats, beatType, score.divisions);

    // -- Collect unplaced alto and tenor --
    List<_UnplacedEntry> collectUnplaced(Map<int, _PlacedEntry> byIdx) {
      final list = <_UnplacedEntry>[];
      for (final entry in byIdx.entries) {
        if (!entry.value.placed && !entry.value.entry.isRest) {
          list.add(_UnplacedEntry(
            pos: bassPos[entry.key]!,
            entry: entry.value.entry,
          ));
        }
      }
      list.sort((a, b) => a.pos.compareTo(b.pos));
      return list;
    }

    final unplacedAlto = collectUnplaced(aByIdx);
    final unplacedTenor = collectUnplaced(tByIdx);

    // Merge tenor entries into voice 2 (alto) as chord members when they are
    // at the same position with the same consolidated duration.
    final altoByPos = <String, int>{};
    for (var k = 0; k < unplacedAlto.length; k++) {
      altoByPos[unplacedAlto[k].pos.toStringAsFixed(6)] = k;
    }
    final remainingTenor = <_UnplacedEntry>[];
    for (final tu in unplacedTenor) {
      final key = tu.pos.toStringAsFixed(6);
      if (altoByPos.containsKey(key)) {
        final ak = altoByPos[key]!;
        if ((unplacedAlto[ak].entry.dq - tu.entry.dq).abs() < 0.001) {
          unplacedAlto[ak].chordMembers.add(tu.entry);
          continue; // absorbed into voice 2
        }
      }
      remainingTenor.add(tu);
    }

    // Helper: write one stream of unplaced entries as a single voice
    int writeVoiceStream(
      List<_UnplacedEntry> stream,
      int voiceNum,
      List<_BeamItem> beamItems, {
      String? stem,
    }) {
      final accState = <String, int>{};
      var posTicks = 0;
      for (final u in stream) {
        final entry = u.entry;
        final targetTicks = _durationTicks(u.pos, score.divisions);
        if (targetTicks > posTicks) {
          measureElements.add(
              _MeasureElement.forward(targetTicks - posTicks));
          posTicks = targetTicks;
        }
        final acc = _resolveAccidental(entry.note!, accState, keyFifths);
        final noteData = _noteXml(
            entry.note!, voiceNum, score.divisions, 1, false,
            accidental: acc, durationOverride: entry.dq,
            typeOverride: entry.type, dot: entry.dot, stem: stem);
        final dur = _durationTicks(entry.dq, score.divisions);
        beamItems.add(_BeamItem(noteData, dur, false));
        measureElements.add(_MeasureElement.note(noteData));
        posTicks += dur;

        // Coincident chord members
        for (final cm in u.chordMembers) {
          final cmAcc = _resolveAccidental(cm.note!, accState, keyFifths);
          final cmData = _noteXml(
              cm.note!, voiceNum, score.divisions, 1, true,
              accidental: cmAcc, durationOverride: cm.dq,
              typeOverride: cm.type, dot: cm.dot);
          measureElements.add(_MeasureElement.note(cmData));
        }
      }
      return posTicks;
    }

    var lastVoiceEnd = measureDur; // voice 1 ends at measureDur

    // Pass 2 -- voice 2 (unplaced alto)
    if (unplacedAlto.isNotEmpty) {
      measureElements.add(_MeasureElement.backup(lastVoiceEnd));
      final v2BeamItems = <_BeamItem>[];
      lastVoiceEnd =
          writeVoiceStream(unplacedAlto, 2, v2BeamItems);
      _applyBeams(v2BeamItems, beats, beatType, score.divisions);
    }

    // Pass 3 -- voice 3 (unplaced tenor); stems explicitly down per convention
    if (remainingTenor.isNotEmpty) {
      measureElements.add(_MeasureElement.backup(lastVoiceEnd));
      final v3BeamItems = <_BeamItem>[];
      lastVoiceEnd =
          writeVoiceStream(remainingTenor, 3, v3BeamItems, stem: 'down');
      _applyBeams(v3BeamItems, beats, beatType, score.divisions);
    }

    // Final backup to measure start for the bass pass
    measureElements.add(_MeasureElement.backup(lastVoiceEnd));

    // -- Pass 4: bass (voice 4, staff 2) --
    final accB = <String, int>{};
    final bassBeamItems = <_BeamItem>[];

    for (var i = 0; i < measure.bassNotes.length; i++) {
      final bassNote = measure.bassNotes[i];
      final chord = (i < measure.realizedChords.length)
          ? measure.realizedChords[i]
          : null;
      final dur = _durationTicks(bassNote.duration, score.divisions);

      if (chord == null || bassNote.isRest) {
        final rest = Note(
            step: 'C', octave: 4, duration: bassNote.duration,
            type: bassNote.type, isRest: true);
        final restData = _noteXml(rest, 4, score.divisions, 2, false);
        bassBeamItems.add(_BeamItem(restData, dur, true));
        measureElements.add(_MeasureElement.note(restData));
      } else {
        // <figured-bass> precedes its note
        if (chord.figures.isNotEmpty) {
          measureElements.add(_MeasureElement.figuredBass(
              chord.figures, true));
        }
        final acc = _resolveAccidental(bassNote, accB, keyFifths);
        final noteData = _noteXml(
            bassNote, 4, score.divisions, 2, false, accidental: acc);
        final gIdx = origGlobalIdx[i];
        if (gIdx != null) {
          noteData.xmlId = 'bass-$gIdx';
        }
        bassBeamItems.add(_BeamItem(noteData, dur, false));
        measureElements.add(_MeasureElement.note(noteData));
      }
    }
    _applyBeams(bassBeamItems, beats, beatType, score.divisions);

    // Now write the entire measure to the builder
    builder.element('measure',
        attributes: {'number': measure.number.toString()}, nest: () {
      for (final elem in measureElements) {
        elem.writeTo(builder);
      }
    });

    return globalIdx;
  }

  // -------------------------------------------------------------------------
  // Note consolidation (repeated pitches -> longer values)
  // -------------------------------------------------------------------------

  /// Map a duration in quarter-note units to a MusicXML note type + dot flag.
  /// Returns null when the duration cannot be represented as a simple or
  /// dotted value.
  static ({String type, bool dot})? _consolidatedType(double dur) {
    dur = _roundTo6(dur);
    return switch (dur) {
      6.0 => (type: 'whole', dot: true),
      4.0 => (type: 'whole', dot: false),
      3.0 => (type: 'half', dot: true),
      2.0 => (type: 'half', dot: false),
      1.5 => (type: 'quarter', dot: true),
      1.0 => (type: 'quarter', dot: false),
      0.75 => (type: 'eighth', dot: true),
      0.5 => (type: 'eighth', dot: false),
      0.375 => (type: '16th', dot: true),
      0.25 => (type: '16th', dot: false),
      0.125 => (type: '32nd', dot: false),
      _ => null,
    };
  }

  /// Build and consolidate a single upper-voice stream for the treble staff.
  ///
  /// [voiceIndex]: 0=soprano, 1=alto, 2=tenor
  ///   (index into reversed upperVoices, so 0 = highest pitch)
  ///
  /// Consecutive slots with the same MIDI pitch are merged into one longer
  /// note provided the combined duration maps to a representable type.
  /// Rests and missing-chord slots are emitted individually.
  List<_ConsolidatedEntry> _consolidateVoicePart(
      Measure measure, int voiceIndex, int divisions) {
    // Build raw entries: one per bass note
    final raw = <_RawEntry>[];
    for (var i = 0; i < measure.bassNotes.length; i++) {
      final bassNote = measure.bassNotes[i];
      final chord = (i < measure.realizedChords.length)
          ? measure.realizedChords[i]
          : null;
      if (chord == null || bassNote.isRest) {
        raw.add(_RawEntry(
          note: null,
          midi: null,
          dq: bassNote.duration,
          type: bassNote.type,
          origIdx: i,
        ));
      } else {
        // upperVoices reversed -> [soprano=0, alto=1, tenor=2]
        final reversed = chord.upperVoices.reversed.toList();
        final note =
            (voiceIndex < reversed.length) ? reversed[voiceIndex] : null;
        raw.add(_RawEntry(
          note: note,
          midi: note?.midiPitch(),
          dq: bassNote.duration,
          type: bassNote.type,
          origIdx: i,
        ));
      }
    }

    final result = <_ConsolidatedEntry>[];
    final n = raw.length;
    var i = 0;

    while (i < n) {
      final entry = raw[i];

      // Rests / missing notes pass through unchanged
      if (entry.midi == null) {
        final ti = _consolidatedType(entry.dq);
        result.add(_ConsolidatedEntry(
          note: entry.note,
          dq: entry.dq,
          type: ti?.type ?? entry.type,
          dot: ti?.dot ?? false,
          origIdxs: [entry.origIdx],
          isRest: true,
        ));
        i++;
        continue;
      }

      // Find the extent of the run (same MIDI pitch, no rest interruption)
      var runEnd = i + 1;
      while (runEnd < n &&
          raw[runEnd].midi != null &&
          raw[runEnd].midi == entry.midi) {
        runEnd++;
      }

      if (runEnd == i + 1) {
        // Single note -- no run to merge
        final ti = _consolidatedType(entry.dq);
        result.add(_ConsolidatedEntry(
          note: entry.note,
          dq: entry.dq,
          type: ti?.type ?? entry.type,
          dot: ti?.dot ?? false,
          origIdxs: [entry.origIdx],
          isRest: false,
        ));
        i++;
        continue;
      }

      // Multiple notes in run -- try to consolidate
      var totalDq = 0.0;
      final origIdxs = <int>[];
      for (var k = i; k < runEnd; k++) {
        totalDq += raw[k].dq;
        origIdxs.add(raw[k].origIdx);
      }

      final ti = _consolidatedType(totalDq);
      if (ti != null) {
        // Merge the whole run into one note
        result.add(_ConsolidatedEntry(
          note: entry.note,
          dq: totalDq,
          type: ti.type,
          dot: ti.dot,
          origIdxs: origIdxs,
          isRest: false,
        ));
        i = runEnd;
      } else {
        // Cannot represent total -- emit individually
        for (var k = i; k < runEnd; k++) {
          final rk = raw[k];
          final tiK = _consolidatedType(rk.dq);
          result.add(_ConsolidatedEntry(
            note: rk.note,
            dq: rk.dq,
            type: tiK?.type ?? rk.type,
            dot: tiK?.dot ?? false,
            origIdxs: [rk.origIdx],
            isRest: false,
          ));
        }
        i = runEnd;
      }
    }

    return result;
  }

  // -------------------------------------------------------------------------
  // Beaming
  // -------------------------------------------------------------------------

  /// Add beam begin/continue/end markers to beamable note sequences.
  ///
  /// A note is beamable when its duration in ticks is strictly less than one
  /// quarter note (i.e. eighth notes, sixteenth notes, etc.).
  ///
  /// Beam grouping rules:
  ///  - Compound meters (6/8, 9/8, 12/8): group = dotted quarter (3 eighths)
  ///  - All other meters: group = one beat (quarter * 4/beatType ticks)
  ///  - Rests and quarter-or-longer notes break the beam.
  void _applyBeams(
      List<_BeamItem> items, int beats, int beatType, int divisions) {
    if (items.length < 2) return;

    final ticksPerQuarter = divisions;

    // Compound time: beatType=8 with an even number of beats >= 6 divisible by 3
    final isCompound = (beatType == 8 && beats >= 6 && (beats % 3) == 0);

    // Ticks per beam group
    final groupTicks = isCompound
        ? (ticksPerQuarter * 1.5).round() // dotted quarter
        : (ticksPerQuarter * 4.0 / (beatType > 0 ? beatType : 1)).round();

    // Walk through items: tag each with its group index and beamability
    var pos = 0;
    final annotated = <_AnnotatedBeamItem>[];
    for (final item in items) {
      annotated.add(_AnnotatedBeamItem(
        item: item,
        groupIdx: groupTicks > 0 ? pos ~/ groupTicks : 0,
        beamable: !item.isRest && item.dur < ticksPerQuarter,
      ));
      pos += item.dur;
    }

    // Find consecutive runs of beamable notes in the same group, then mark them
    final n = annotated.length;
    var i = 0;
    while (i < n) {
      if (!annotated[i].beamable) {
        i++;
        continue;
      }

      // Extend the run while same group and still beamable
      final gIdx = annotated[i].groupIdx;
      var j = i;
      while (j + 1 < n &&
          annotated[j + 1].beamable &&
          annotated[j + 1].groupIdx == gIdx) {
        j++;
      }

      if (j > i) {
        // At least two notes -- add beam markings
        for (var k = i; k <= j; k++) {
          final value =
              (k == i) ? 'begin' : ((k == j) ? 'end' : 'continue');
          annotated[k].item.noteData.beams.add(_Beam(number: 1, value: value));
        }
      }

      i = j + 1;
    }
  }

  // -------------------------------------------------------------------------
  // Attribute builders
  // -------------------------------------------------------------------------

  void _buildGrandStaffAttributes(XmlBuilder builder, Score score) {
    builder.element('attributes', nest: () {
      builder.element('divisions', nest: score.divisions.toString());
      _keyElement(builder, score.keyFifths, score.keyMode);
      _timeElement(builder, score.beats, score.beatType);
      builder.element('staves', nest: '2');

      // Treble clef -- staff 1 (soprano / alto / tenor)
      builder.element('clef', attributes: {'number': '1'}, nest: () {
        builder.element('sign', nest: 'G');
        builder.element('line', nest: '2');
      });

      // Bass clef -- staff 2 (bass voice)
      builder.element('clef', attributes: {'number': '2'}, nest: () {
        builder.element('sign', nest: 'F');
        builder.element('line', nest: '4');
      });
    });
  }

  void _buildKeyChangeAttributes(XmlBuilder builder, Measure measure) {
    final fifths = measure.keySignature?['fifths'] as int? ?? 0;
    final mode = measure.keySignature?['mode'] as String? ?? 'major';
    builder.element('attributes', nest: () {
      _keyElement(builder, fifths, mode);
    });
  }

  // -------------------------------------------------------------------------
  // Element helpers
  // -------------------------------------------------------------------------

  void _keyElement(XmlBuilder builder, int fifths, String mode) {
    builder.element('key', nest: () {
      builder.element('fifths', nest: fifths.toString());
      builder.element('mode', nest: mode);
    });
  }

  void _timeElement(XmlBuilder builder, int beats, int beatType) {
    builder.element('time', nest: () {
      builder.element('beats', nest: beats.toString());
      builder.element('beat-type', nest: beatType.toString());
    });
  }

  /// Build a note data structure (not yet written to XML).
  ///
  /// Element order follows MusicXML 4.0 spec:
  ///   chord?, rest|pitch, duration, voice, type, dot?, accidental?, stem?, staff
  ///   [beam elements appended later by _applyBeams()]
  _NoteData _noteXml(
    Note note,
    int voice,
    int divisions,
    int staff,
    bool chordMember, {
    String? accidental,
    double? durationOverride,
    String? typeOverride,
    bool dot = false,
    String? stem,
  }) {
    final effectiveDur = durationOverride ?? note.duration;
    final effectiveType = typeOverride ?? (note.type.isNotEmpty ? note.type : 'quarter');

    return _NoteData(
      isChord: chordMember,
      isRest: note.isRest,
      step: note.step,
      alter: note.alter,
      octave: note.octave,
      duration: _durationTicks(effectiveDur, divisions),
      voice: voice,
      type: effectiveType,
      dot: dot,
      accidental: _resolveAccidentalString(note, accidental),
      stem: (!note.isRest && stem != null) ? stem : null,
      staff: staff,
    );
  }

  /// Resolve the accidental string to emit. If [explicit] is non-null, use it.
  /// Otherwise, fall back to the note's own alter if non-zero.
  String? _resolveAccidentalString(Note note, String? explicit) {
    if (note.isRest) return null;
    if (explicit != null) return explicit;
    // The PHP code had a secondary fallback: if no explicit accidental was
    // resolved via the tracker, it would still emit accidentals for altered
    // notes. However, in this port _resolveAccidental() handles all cases,
    // so we only emit when explicitly told.
    return null;
  }

  /// Write a [_NoteData] to the [XmlBuilder].
  void _writeNoteElement(XmlBuilder builder, _NoteData data) {
    builder.element('note', attributes: data.xmlId != null
        ? {'xml:id': data.xmlId!}
        : {}, nest: () {
      if (data.isChord) {
        builder.element('chord');
      }

      if (data.isRest) {
        builder.element('rest');
      } else {
        builder.element('pitch', nest: () {
          builder.element('step', nest: data.step);
          if (data.alter != 0) {
            builder.element('alter', nest: data.alter.toString());
          }
          builder.element('octave', nest: data.octave.toString());
        });
      }

      builder.element('duration', nest: data.duration.toString());
      builder.element('voice', nest: data.voice.toString());
      builder.element('type', nest: data.type);
      if (data.dot) {
        builder.element('dot');
      }

      if (!data.isRest && data.accidental != null) {
        builder.element('accidental', nest: data.accidental!);
      }

      if (data.stem != null) {
        builder.element('stem', nest: data.stem!);
      }

      builder.element('staff', nest: data.staff.toString());

      for (final beam in data.beams) {
        builder.element('beam',
            attributes: {'number': beam.number.toString()}, nest: beam.value);
      }
    });
  }

  /// Write a figured-bass element to the builder.
  void _figuredBassXml(XmlBuilder builder, List<Figure> figures,
      [bool abbreviate = false]) {
    var effectiveFigures = figures;
    // Conventional abbreviation: "5 3" -> "5" (omit the 3), only for
    // computed figures
    if (abbreviate) {
      final nums = figures.map((f) => f.number).toList();
      final alts = figures.map((f) => f.alter).toList();
      if (_listEquals(nums, [5, 3]) && _listEquals(alts, [0, 0])) {
        effectiveFigures = [const Figure(number: 5)];
      }
    }
    builder.element('figured-bass',
        attributes: {'placement': 'below'}, nest: () {
      for (final fig in effectiveFigures) {
        if (fig.number <= 0) continue;
        builder.element('figure', nest: () {
          if (fig.alter != 0) {
            final acc = fig.alter > 0 ? 'sharp' : 'flat';
            builder.element('prefix', nest: acc);
          }
          builder.element('figure-number', nest: fig.number.toString());
        });
      }
    });
  }

  /// Determine the default alter a key signature applies to a step.
  /// Returns 1 (sharp), -1 (flat), or 0 (natural).
  int _keyAlterForStep(String step, int keyFifths) {
    if (keyFifths > 0) {
      final sharps = const ['F', 'C', 'G', 'D', 'A', 'E', 'B']
          .sublist(0, keyFifths.clamp(0, 7));
      return sharps.contains(step) ? 1 : 0;
    }
    if (keyFifths < 0) {
      final flats = const ['B', 'E', 'A', 'D', 'G', 'C', 'F']
          .sublist(0, (-keyFifths).clamp(0, 7));
      return flats.contains(step) ? -1 : 0;
    }
    return 0;
  }

  /// Given a note and the current in-measure accidental tracker for its staff,
  /// return the explicit accidental string to emit (or null if none needed),
  /// and update the tracker.
  String? _resolveAccidental(
      Note note, Map<String, int> tracker, int keyFifths) {
    if (note.isRest) return null;

    final keyAlter = _keyAlterForStep(note.step, keyFifths);
    final activeAlter = tracker[note.step] ?? keyAlter;

    if (note.alter == activeAlter) {
      return null; // matches current state -- no accidental needed
    }

    tracker[note.step] = note.alter;

    return switch (note.alter) {
      1 => 'sharp',
      -1 => 'flat',
      2 => 'double-sharp',
      -2 => 'flat-flat',
      0 => 'natural',
      _ => null,
    };
  }

  int _durationTicks(double durationInQuarters, int divisions) {
    return (durationInQuarters * divisions).round();
  }

  static double _roundTo6(double v) {
    return (v * 1000000).roundToDouble() / 1000000;
  }

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// =============================================================================
// Internal data classes
// =============================================================================

/// Intermediate representation of a `<note>` element, allowing beam elements
/// to be attached after initial construction.
class _NoteData {
  final bool isChord;
  final bool isRest;
  final String step;
  final int alter;
  final int octave;
  final int duration;
  final int voice;
  final String type;
  final bool dot;
  final String? accidental;
  final String? stem;
  final int staff;
  final List<_Beam> beams = [];
  String? xmlId;

  _NoteData({
    required this.isChord,
    required this.isRest,
    required this.step,
    required this.alter,
    required this.octave,
    required this.duration,
    required this.voice,
    required this.type,
    required this.dot,
    required this.accidental,
    required this.stem,
    required this.staff,
  });
}

class _Beam {
  final int number;
  final String value;
  const _Beam({required this.number, required this.value});
}

/// A beam tracking item: references the note data, its tick duration, and
/// whether it's a rest.
class _BeamItem {
  final _NoteData noteData;
  final int dur;
  final bool isRest;
  const _BeamItem(this.noteData, this.dur, this.isRest);
}

class _AnnotatedBeamItem {
  final _BeamItem item;
  final int groupIdx;
  final bool beamable;
  const _AnnotatedBeamItem({
    required this.item,
    required this.groupIdx,
    required this.beamable,
  });
}

/// Raw entry before consolidation.
class _RawEntry {
  final Note? note;
  final int? midi;
  final double dq;
  final String type;
  final int origIdx;
  const _RawEntry({
    required this.note,
    required this.midi,
    required this.dq,
    required this.type,
    required this.origIdx,
  });
}

/// Consolidated voice entry after merging repeated pitches.
class _ConsolidatedEntry {
  final Note? note;
  final double dq;
  final String type;
  final bool dot;
  final List<int> origIdxs;
  final bool isRest;
  const _ConsolidatedEntry({
    required this.note,
    required this.dq,
    required this.type,
    required this.dot,
    required this.origIdxs,
    required this.isRest,
  });
}

/// Wrapper tracking whether a consolidated entry has been placed in voice 1.
class _PlacedEntry {
  final _ConsolidatedEntry entry;
  bool placed = false;
  _PlacedEntry({required this.entry});
}

/// An unplaced entry awaiting voice-2 or voice-3 writing, with its position
/// in quarter-note units from measure start.
class _UnplacedEntry {
  final double pos;
  final _ConsolidatedEntry entry;
  final List<_ConsolidatedEntry> chordMembers = [];
  _UnplacedEntry({required this.pos, required this.entry});
}

/// A deferred measure element that can be written to an [XmlBuilder].
/// This allows collecting all elements (notes, backups, forwards, etc.)
/// before writing, so that beam markers can be applied retroactively.
class _MeasureElement {
  final _MeasureElementType _type;
  final _NoteData? _noteData;
  final int? _ticks;
  final void Function(XmlBuilder)? _attrBuilder;
  final List<Figure>? _figures;
  final bool _abbreviate;

  _MeasureElement._({
    required _MeasureElementType type,
    _NoteData? noteData,
    int? ticks,
    void Function(XmlBuilder)? attrBuilder,
    List<Figure>? figures,
    bool abbreviate = false,
  })  : _type = type,
        _noteData = noteData,
        _ticks = ticks,
        _attrBuilder = attrBuilder,
        _figures = figures,
        _abbreviate = abbreviate;

  factory _MeasureElement.note(_NoteData data) =>
      _MeasureElement._(type: _MeasureElementType.note, noteData: data);

  factory _MeasureElement.backup(int ticks) =>
      _MeasureElement._(type: _MeasureElementType.backup, ticks: ticks);

  factory _MeasureElement.forward(int ticks) =>
      _MeasureElement._(type: _MeasureElementType.forward, ticks: ticks);

  factory _MeasureElement.attributes(void Function(XmlBuilder) build) =>
      _MeasureElement._(
          type: _MeasureElementType.attributes, attrBuilder: build);

  factory _MeasureElement.figuredBass(List<Figure> figures, bool abbreviate) =>
      _MeasureElement._(
          type: _MeasureElementType.figuredBass,
          figures: figures,
          abbreviate: abbreviate);

  void writeTo(XmlBuilder builder) {
    switch (_type) {
      case _MeasureElementType.note:
        MusicXmlSerializer()._writeNoteElement(builder, _noteData!);
      case _MeasureElementType.backup:
        builder.element('backup', nest: () {
          builder.element('duration', nest: _ticks.toString());
        });
      case _MeasureElementType.forward:
        builder.element('forward', nest: () {
          builder.element('duration', nest: _ticks.toString());
        });
      case _MeasureElementType.attributes:
        _attrBuilder!(builder);
      case _MeasureElementType.figuredBass:
        MusicXmlSerializer()._figuredBassXml(builder, _figures!, _abbreviate);
    }
  }
}

enum _MeasureElementType { note, backup, forward, attributes, figuredBass }
