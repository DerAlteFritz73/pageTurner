import '../models/note.dart';
import '../models/chord.dart';
import 'figured_bass_interpreter.dart';
import 'pitch_helper.dart';

/// Applies voice-leading rules to produce smooth, historically-correct
/// basso continuo realizations.
///
/// Rules implemented (in priority order):
///
/// 1. RANGE CONSTRAINTS (Baroque keyboard style, Gasparini):
///    - Soprano: C4-G5  (MIDI 60-79)
///    - Alto:    G3-C5  (MIDI 55-72)
///    - Tenor:   C3-E4  (MIDI 48-64)
///    - Bass:    given (unchanged)
///
/// 2. FORBIDDEN PARALLELS (Fux / Gasparini / Delair):
///    - No parallel (consecutive) perfect fifths between any pair of voices
///    - No parallel (consecutive) perfect octaves between any pair of voices
///    - No parallel (consecutive) unisons
///
/// 3. VOICE LEADING / LAW OF SHORTEST WAY (Delair):
///    - Prefer common tones between chords; retain them in the same voice
///    - Prefer steps over leaps
///    - Contrary motion between soprano and bass preferred
///
/// 4. DOUBLING RULES:
///    - Every voice draws from the full pool of chord-tone pitch classes
///      so the optimizer can freely mix doublings.
class VoiceLeadingEngine {
  // Voice range MIDI limits: [min, max]
  static const _sopranoRange = (60, 79); // C4-G5
  static const _altoRange = (55, 72); // G3-C5
  static const _tenorRange = (48, 64); // C3-E4

  /// Maximum right-hand span: soprano - tenor must not exceed a 9th
  /// (major 9th = 14 semitones)
  static const _maxHandSpan = 14;

  /// Perfect intervals in semitones (mod 12): unison/octave=0, fifth=7
  static const _perfectConsonances = [0, 7];

  /// Current key context, set per assignVoices() call.
  /// Retained for potential subclass / rule-extension use.
  int _keyFifths = 0; // ignore: unused_field
  String _keyMode = 'major'; // ignore: unused_field

  /// Choose upper voices (soprano, alto, tenor) for a chord given:
  ///  - The required intervals above bass (from figured bass interpreter)
  ///  - The previous chord (for voice leading)
  ///  - Key context
  ///
  /// Returns the Chord with upperVoices populated.
  Chord assignVoices({
    required Chord chord,
    required List<ExpandedInterval> intervals,
    required Chord? prevChord,
    required int keyFifths,
    required String keyMode,
    bool isLeadingTone7th = false,
    int? melodyPc,
    int numVoices = 4,
  }) {
    _keyFifths = keyFifths;
    _keyMode = keyMode;

    final bass = chord.bass;

    // Build candidate pitches for each interval
    var candidatePitches = _buildCandidates(bass, intervals, keyFifths, keyMode);

    if (candidatePitches.isEmpty) {
      // Fallback: triad
      candidatePitches = _buildCandidates(
        bass,
        [
          const ExpandedInterval(interval: 3),
          const ExpandedInterval(interval: 5),
        ],
        keyFifths,
        keyMode,
      );
    }

    final prevUpperMidis = prevChord != null
        ? prevChord.upperVoices.map((n) => n.midiPitch()).toList()
        : <int>[];
    final prevBassMidi = prevChord?.bass.midiPitch();

    // When 3 voices requested, check whether this chord requires 4
    final effectiveVoices = numVoices == 3
        ? _effectiveVoiceCount(intervals, prevChord, keyFifths, keyMode)
        : numVoices;

    // Choose pitches by minimizing total voice movement
    final chosen = _chooseVoices(
      candidatePitches,
      prevUpperMidis,
      bass.midiPitch(),
      isLeadingTone7th,
      prevBassMidi,
      melodyPc,
      effectiveVoices,
    );

    // Voice name order matches the upperVoices array order (lowest first)
    final voiceNumbers = effectiveVoices == 3
        ? [3, 2] // alto=voice 3, soprano=voice 2
        : [4, 3, 2]; // tenor=voice 4, alto=voice 3, soprano=voice 2

    for (var idx = 0; idx < chosen.length; idx++) {
      final voiceNum = idx < voiceNumbers.length ? voiceNumbers[idx] : 2;
      final note = PitchHelper.midiToNote(
        chosen[idx],
        bass.duration,
        bass.type,
        voiceNum,
        keyFifths,
      );
      chord.addUpperVoice(note);
    }

    return chord;
  }

  /// Determine the effective voice count for a single chord when the user
  /// preference is 3 voices ("whenever possible").
  ///
  /// Upgrades to 4 voices when:
  ///  1. The chord has >= 3 intervals above the bass (7th chords, etc.)
  ///  2. The previous chord had a chordal seventh
  ///  3. The previous chord's upper voices contained the diatonic leading tone
  int _effectiveVoiceCount(
    List<ExpandedInterval> intervals,
    Chord? prevChord,
    int keyFifths,
    String keyMode,
  ) {
    // Rule 1: harmony needs 4 pitch classes
    if (intervals.length >= 3) {
      return 4;
    }

    if (prevChord == null) {
      return 3;
    }

    // Rule 2: previous chord had a chordal 7th
    for (final fig in prevChord.figures) {
      if (fig.number == 7) {
        return 4;
      }
    }

    // Rule 3: previous chord had the leading tone in an upper voice
    final scale = PitchHelper.buildScale(keyFifths, keyMode);
    final tonicPc = scale[0];
    final ltPc = (tonicPc - 1 + 12) % 12;
    for (final voice in prevChord.upperVoices) {
      if (voice.pitchClass() == ltPc) {
        return 4;
      }
    }

    return 3;
  }

  /// Build all valid MIDI pitches for each interval above bass, within voice
  /// ranges. Returns list of pitch lists, one per interval.
  List<List<int>> _buildCandidates(
    Note bass,
    List<ExpandedInterval> intervals,
    int keyFifths,
    String keyMode,
  ) {
    final bassMidi = bass.midiPitch();
    final allCandidates = <List<int>>[];

    for (final fig in intervals) {
      final genericInterval = fig.interval;
      final explicitAlter = fig.alter;
      final explicit = fig.explicit;

      // Compute the diatonic note above bass for this interval
      final targetNote =
          PitchHelper.diatonicInterval(bass, genericInterval, keyFifths, keyMode);
      var targetPc = targetNote.pitchClass();

      // Apply explicit alteration from figure if any
      if (explicit && explicitAlter != 0) {
        targetPc = (targetPc + explicitAlter + 12) % 12;
      }

      // Octave transpositions in the combined range
      final candidates = <int>[];
      for (var o = 2; o <= 5; o++) {
        final midi = (o + 1) * 12 + targetPc;
        if (midi > bassMidi && midi <= _sopranoRange.$2 + 12) {
          candidates.add(midi);
        }
      }

      if (candidates.isNotEmpty) {
        allCandidates.add(candidates);
      }
    }

    return allCandidates;
  }

  /// Generate candidate MIDI pitches within a voice range for a given set of
  /// pitch classes.
  List<int> _candidates(List<int> pitchClasses, (int, int) range, int bassMidi) {
    final (min, max) = range;
    final list = <int>[];
    for (final pc in pitchClasses) {
      for (var o = 2; o <= 5; o++) {
        final midi = (o + 1) * 12 + pc;
        if (midi >= min && midi <= max && midi > bassMidi) {
          list.add(midi);
        }
      }
    }
    list.sort();
    return list.toSet().toList()..sort();
  }

  /// Choose upper voice MIDI pitches from candidate lists.
  ///
  /// Algorithm:
  ///  1. Assign each interval candidate list to a voice
  ///  2. Minimize total motion from previous chord
  ///  3. Enforce range constraints
  ///  4. Check for forbidden parallels (post-selection)
  ///  5. Doubling: every voice draws from the full pool of chord-tone pitch
  ///     classes so the optimizer can freely mix doublings.
  List<int> _chooseVoices(
    List<List<int>> candidateLists,
    List<int> prevMidis,
    int bassMidi,
    bool isLeadingTone,
    int? prevBassMidi,
    int? melodyPc,
    int numVoices,
  ) {
    if (candidateLists.isEmpty) {
      return [];
    }

    // Collect the pitch classes required by the figured-bass intervals
    final requiredPcs = <int>{};
    for (final list in candidateLists) {
      for (final midi in list) {
        requiredPcs.add(midi % 12);
      }
    }

    // Melody completion: remove melody PC from required set so the freed
    // voice can use a better doubling
    final requiredPcsForVoices = requiredPcs.toList();
    if (melodyPc != null) {
      requiredPcsForVoices.remove(melodyPc);
    }

    // Build the full chord-tone pool
    final numUpper = numVoices == 3 ? 2 : 3;
    final allPcs = requiredPcs.toSet();
    final maxForRoot = numVoices == 3 ? 1 : 2;
    if (requiredPcs.length <= maxForRoot) {
      final bassPc = bassMidi % 12;
      allPcs.add(bassPc);
    }

    // Build per-voice candidate lists within each voice's range
    final voiceRanges = numVoices == 3
        ? [_altoRange, _sopranoRange]
        : [_tenorRange, _altoRange, _sopranoRange];

    final filtered = <int, List<int>>{};
    for (var v = 0; v < numUpper; v++) {
      final range = voiceRanges[v];
      var list = _candidates(allPcs.toList(), range, bassMidi);

      if (list.isEmpty) {
        // Expand range by 5 semitones in each direction
        final expandedRange = (range.$1 - 5, range.$2 + 5);
        list = _candidates(allPcs.toList(), expandedRange, bassMidi);
      }

      if (list.isEmpty) {
        list = [bassMidi + 7];
      }

      filtered[v] = list;
    }

    const limit = 8;

    if (numVoices == 3) {
      // 3-voice mode: alto + soprano only
      final bestChosen = [filtered[0]![0], filtered[1]![0]];
      final aOpts = filtered[0]!.take(limit).toList();
      final sOpts = filtered[1]!.take(limit).toList();

      var found = searchVoices2(
        aOpts, sOpts, prevMidis, bassMidi, _maxHandSpan,
        prevBassMidi, requiredPcsForVoices, melodyPc,
      );
      if (found != null) return found;

      found = searchVoices2(
        aOpts, sOpts, prevMidis, bassMidi, 16,
        prevBassMidi, requiredPcsForVoices, melodyPc,
      );
      return found ?? bestChosen;
    }

    // 4-voice mode: tenor + alto + soprano
    final bestChosen = [filtered[0]![0], filtered[1]![0], filtered[2]![0]];
    final tOpts = filtered[0]!.take(limit).toList();
    final aOpts = filtered[1]!.take(limit).toList();
    final sOpts = filtered[2]!.take(limit).toList();

    var found = searchVoices(
      tOpts, aOpts, sOpts, prevMidis, bassMidi, _maxHandSpan,
      prevBassMidi, requiredPcsForVoices, melodyPc,
    );
    if (found != null) return found;

    found = searchVoices(
      tOpts, aOpts, sOpts, prevMidis, bassMidi, 16,
      prevBassMidi, requiredPcsForVoices, melodyPc,
    );
    return found ?? bestChosen;
  }

  /// Inner search loop: evaluate all tenor/alto/soprano combinations within
  /// [maxSpan]. Returns the best [tenor, alto, soprano] list, or null if no
  /// combination qualifies.
  List<int>? searchVoices(
    List<int> tOpts,
    List<int> aOpts,
    List<int> sOpts,
    List<int> prevMidis,
    int bassMidi,
    int maxSpan, [
    int? prevBassMidi,
    List<int> requiredPcs = const [],
    int? melodyPc,
  ]) {
    var bestCost = double.infinity;
    List<int>? bestChosen;

    final isStart = prevMidis.isEmpty;

    for (final t in tOpts) {
      if (t <= bassMidi) continue;

      for (final a in aOpts) {
        for (final s in sOpts) {
          // Voice ordering: tenor <= alto <= soprano
          if (!(t <= a && a <= s)) continue;

          // Prevent adjacent-voice unisons (collapse of voice independence)
          if (t == a || a == s) continue;

          // Right-hand span constraint
          if ((s - t) > maxSpan) continue;

          var cost = _voiceCost(
            [t, a, s], prevMidis, bassMidi, isStart, prevBassMidi,
          );

          // Hard penalty for omitting a required figured-bass interval.
          // 150 per missing PC dwarfs any motion-cost gain, so the
          // optimizer will always prefer a voicing that includes all
          // figure tones.
          if (requiredPcs.isNotEmpty) {
            final presentPcs = {t % 12, a % 12, s % 12};
            for (final rpc in requiredPcs) {
              if (!presentPcs.contains(rpc)) {
                cost += 150.0;
              }
            }
          }

          // Melody avoidance: penalise doubling the melody pitch class.
          // 40 per voice steers away when alternatives exist but stays
          // below the required-PC penalty (150).
          if (melodyPc != null) {
            if (t % 12 == melodyPc) cost += 40.0;
            if (a % 12 == melodyPc) cost += 40.0;
            if (s % 12 == melodyPc) cost += 40.0;
          }

          if (cost < bestCost) {
            bestCost = cost;
            bestChosen = [t, a, s];
          }
        }
      }
    }

    return bestChosen;
  }

  /// 2-voice inner search loop (3-voice mode: alto + soprano).
  /// Returns the best [alto, soprano] list, or null if none qualifies.
  List<int>? searchVoices2(
    List<int> aOpts,
    List<int> sOpts,
    List<int> prevMidis,
    int bassMidi,
    int maxSpan, [
    int? prevBassMidi,
    List<int> requiredPcs = const [],
    int? melodyPc,
  ]) {
    var bestCost = double.infinity;
    List<int>? bestChosen;

    final isStart = prevMidis.isEmpty;

    for (final a in aOpts) {
      if (a <= bassMidi) continue;

      for (final s in sOpts) {
        if (a > s) continue; // alto <= soprano
        if (a == s) continue; // no unison
        if ((s - a) > maxSpan) continue;

        var cost = _voiceCost2(
          [a, s], prevMidis, bassMidi, isStart, prevBassMidi,
        );

        if (requiredPcs.isNotEmpty) {
          final present = {a % 12, s % 12};
          for (final rpc in requiredPcs) {
            if (!present.contains(rpc)) {
              cost += 150.0;
            }
          }
        }

        if (melodyPc != null) {
          if (a % 12 == melodyPc) cost += 40.0;
          if (s % 12 == melodyPc) cost += 40.0;
        }

        if (cost < bestCost) {
          bestCost = cost;
          bestChosen = [a, s];
        }
      }
    }

    return bestChosen;
  }

  /// Cost function for a 4-voice chord voicing (tenor, alto, soprano + bass).
  ///
  /// Ported from the PHP `voiceCostFallback()` method as the primary cost
  /// function. Weights:
  ///   - Step motion:        0-9 based on semitone distance
  ///   - Large leap:         motion * 3
  ///   - Contrary motion:    +6 penalty when soprano moves same direction as bass
  ///   - Parallel 5ths:      +40
  ///   - Parallel octaves:   +60
  ///   - Voice crossing:     +100
  ///   - Range overshoot:    (distance * 3) per semitone outside ideal range
  double _voiceCost(
    List<int> chosen,
    List<int> prevMidis,
    int bassMidi,
    bool isStart, [
    int? prevBassMidi,
  ]) {
    var cost = 0.0;

    // Motion from previous chord -- prefer common tones, then steps
    for (var i = 0; i < chosen.length; i++) {
      final midi = chosen[i];
      final prev = i < prevMidis.length ? prevMidis[i] : null;
      if (prev != null) {
        final motion = (midi - prev).abs();
        if (motion == 0) {
          cost += 0; // common tone -- best
        } else if (motion <= 2) {
          cost += 1; // step
        } else if (motion <= 4) {
          cost += 4; // small leap
        } else if (motion <= 7) {
          cost += 9; // leap of 5th/6th
        } else {
          cost += motion * 3; // large leap -- heavy penalty
        }
      }
    }

    // Contrary motion between soprano and bass
    if (prevBassMidi != null && prevMidis.length >= 3) {
      final bassDir = bassMidi - prevBassMidi;
      final sopDir = chosen[2] - prevMidis[2];
      if (bassDir != 0 && sopDir != 0 && ((bassDir > 0) == (sopDir > 0))) {
        cost += 6.0;
      }
    }

    // Parallel perfect consonances penalty
    if (prevMidis.length >= 3) {
      final allCurr = [...chosen, bassMidi];
      final allPrev = [...prevMidis, bassMidi];
      final n = allCurr.length;

      for (var a = 0; a < n; a++) {
        for (var b = a + 1; b < n; b++) {
          if (a >= allPrev.length || b >= allPrev.length) continue;
          final prevInterval = (allPrev[a] - allPrev[b]).abs() % 12;
          final currInterval = (allCurr[a] - allCurr[b]).abs() % 12;
          final moved =
              (allPrev[a] != allCurr[a]) || (allPrev[b] != allCurr[b]);
          if (moved && prevInterval == currInterval) {
            if (currInterval == 7) {
              cost += 40; // parallel 5ths
            } else if (currInterval == 0) {
              cost += 60; // parallel octaves/unisons
            }
          }
        }
      }
    }

    // Voice crossing
    for (var i = 0; i < chosen.length - 1; i++) {
      if (chosen[i] > chosen[i + 1]) {
        cost += 100;
      }
    }

    // Outside ideal range
    const ranges = [_tenorRange, _altoRange, _sopranoRange];
    for (var i = 0; i < chosen.length; i++) {
      final midi = chosen[i];
      final (lo, hi) = ranges[i];
      if (midi < lo) cost += (lo - midi) * 3;
      if (midi > hi) cost += (midi - hi) * 3;
    }

    return cost;
  }

  /// Cost function for 2-voice (alto + soprano) mode.
  /// Index 0 = alto, index 1 = soprano.
  double _voiceCost2(
    List<int> curr,
    List<int> prevMidis,
    int bassCurr,
    bool isStart, [
    int? prevBassMidi,
  ]) {
    var cost = 0.0;
    final bassPrev = isStart ? bassCurr : (prevBassMidi ?? bassCurr);

    // Motion from previous chord
    for (var i = 0; i < curr.length; i++) {
      final midi = curr[i];
      final prev = i < prevMidis.length ? prevMidis[i] : null;
      if (prev != null) {
        final motion = (midi - prev).abs();
        if (motion == 0) {
          cost += 0;
        } else if (motion <= 2) {
          cost += 1;
        } else if (motion <= 4) {
          cost += 4;
        } else if (motion <= 7) {
          cost += 9;
        } else {
          cost += motion * 3;
        }
      }
    }

    // Contrary motion: soprano (index 1) vs bass
    if (!isStart && prevMidis.length >= 2) {
      final bassDir = bassCurr - bassPrev;
      final sopDir = curr[1] - prevMidis[1];
      if (bassDir != 0 && sopDir != 0 && ((bassDir > 0) == (sopDir > 0))) {
        cost += 6.0;
      }
    }

    // Parallel perfect consonances (check alto-soprano and each vs bass)
    if (!isStart && prevMidis.length >= 2) {
      final allCurr = [curr[0], curr[1], bassCurr];
      final allPrev = [prevMidis[0], prevMidis[1], bassPrev];
      for (var i = 0; i < 3; i++) {
        for (var j = i + 1; j < 3; j++) {
          final pInt = (allPrev[i] - allPrev[j]).abs() % 12;
          final cInt = (allCurr[i] - allCurr[j]).abs() % 12;
          if (pInt == cInt &&
              (allPrev[i] != allCurr[i] || allPrev[j] != allCurr[j])) {
            if (cInt == 7) {
              cost += 40; // parallel 5ths
            } else if (cInt == 0) {
              cost += 60; // parallel octaves
            }
          }
        }
      }
    }

    // Voice crossing
    if (curr[0] > curr[1]) {
      cost += 100;
    }

    // Outside ideal range
    for (var i = 0; i < curr.length; i++) {
      final midi = curr[i];
      final (lo, hi) = i == 0 ? _altoRange : _sopranoRange;
      if (midi < lo) cost += (lo - midi) * 3;
      if (midi > hi) cost += (midi - hi) * 3;
    }

    return cost;
  }

  /// Produce a human-readable trace of the voice-leading choices made for
  /// [chord] relative to [prevChord]. Returns a list of step maps compatible
  /// with the chord-inspector UI.
  List<Map<String, dynamic>> traceVoiceLeading(
    Chord chord,
    Chord? prevChord,
    int keyFifths,
    String keyMode,
  ) {
    final steps = <Map<String, dynamic>>[];
    final currUpper = chord.upperVoices;
    final voiceNames = currUpper.length == 2
        ? ['Alto', 'Soprano']
        : ['Tenor', 'Alto', 'Soprano'];
    final prevUpper = prevChord?.upperVoices ?? [];

    // -- Per-voice motion --
    for (var vi = 0; vi < currUpper.length; vi++) {
      final name = vi < voiceNames.length ? voiceNames[vi] : 'Voice';
      final currNote = currUpper[vi];
      final currLabel = _noteLabel(currNote);
      final prevNote = vi < prevUpper.length ? prevUpper[vi] : null;

      if (prevNote == null) {
        steps.add({
          'test': '$name: $currLabel (opening)',
          'passed': true,
          'isDecision': false,
        });
        continue;
      }

      final motion = currNote.midiPitch() - prevNote.midiPitch();
      final abs = motion.abs();
      final dir = motion > 0 ? '↑' : (motion < 0 ? '↓' : '');
      final prevLabel = _noteLabel(prevNote);

      String desc;
      if (abs == 0) {
        desc = 'common tone';
      } else if (abs <= 2) {
        desc = 'step $dir';
      } else if (abs <= 4) {
        desc = 'small leap $dir ($abs st.)';
      } else {
        desc = 'leap $dir ($abs st.)';
      }

      steps.add({
        'test': '$name: $prevLabel → $currLabel — $desc',
        'passed': abs <= 7,
        'isDecision': false,
      });
    }

    // -- Parallel consonances --
    if (prevChord != null) {
      final violations = checkParallels(prevChord, chord);
      if (violations.isEmpty) {
        steps.add({
          'test': 'No parallel 5ths or octaves',
          'passed': true,
          'isDecision': true,
          'rule': 'Forbidden Parallels',
          'source': 'Gasparini 1729; Delair 1724',
          'reason': 'All voice pairs move without forbidden parallels',
        });
      } else {
        for (final v in violations) {
          steps.add({
            'test': 'Parallel: $v',
            'passed': false,
            'isDecision': true,
            'rule': 'Forbidden Parallels',
            'source': 'Gasparini 1729; Delair 1724',
            'reason': v,
          });
        }
      }

      // -- Contrary motion (soprano vs bass) --
      final prevSop = prevUpper.length >= 3
          ? prevUpper[2]
          : (prevUpper.length >= 2
              ? prevUpper[1]
              : (prevUpper.isNotEmpty ? prevUpper[0] : null));
      final currSop = currUpper.length >= 3
          ? currUpper[2]
          : (currUpper.length >= 2
              ? currUpper[1]
              : (currUpper.isNotEmpty ? currUpper[0] : null));

      if (prevSop != null && currSop != null) {
        final bassDir =
            chord.bass.midiPitch() - prevChord.bass.midiPitch();
        final sopDir = currSop.midiPitch() - prevSop.midiPitch();
        if (bassDir != 0 && sopDir != 0) {
          final contrary = (bassDir > 0) != (sopDir > 0);
          steps.add({
            'test': contrary
                ? 'Soprano and bass move in contrary motion'
                : 'Soprano and bass move in similar motion',
            'passed': contrary,
            'isDecision': true,
            'rule': 'Contrary Motion (outer voices)',
            'source': 'Delair 1724',
            'reason': contrary
                ? 'Outer voices in opposite directions — preferred'
                : 'Similar motion of outer voices — penalised',
          });
        }
      }
    }

    // -- Right-hand span --
    if (currUpper.length >= 3) {
      final span = currUpper[2].midiPitch() - currUpper[0].midiPitch();
      steps.add({
        'test':
            'Right-hand span: $span st. (${span <= _maxHandSpan ? "within" : "exceeds"} 9th limit)',
        'passed': span <= _maxHandSpan,
        'isDecision': false,
      });
    }

    return steps;
  }

  /// Format a note as e.g. "C#4", "Bb3".
  String _noteLabel(Note note) {
    final acc = switch (note.alter) {
      1 => '#',
      -1 => 'b',
      2 => '##',
      -2 => 'bb',
      _ => '',
    };
    return '${note.step}$acc${note.octave}';
  }

  /// Check if parallel fifths or octaves exist between two chords.
  /// Returns list of violation description strings.
  List<String> checkParallels(Chord prev, Chord curr) {
    final violations = <String>[];
    final prevNotes = prev.allNotes();
    final currNotes = curr.allNotes();

    final n = prevNotes.length < currNotes.length
        ? prevNotes.length
        : currNotes.length;

    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final prevAbs =
            (prevNotes[i].midiPitch() - prevNotes[j].midiPitch()).abs() % 12;
        final currAbs =
            (currNotes[i].midiPitch() - currNotes[j].midiPitch()).abs() % 12;

        if (_perfectConsonances.contains(prevAbs) &&
            prevAbs == currAbs &&
            // Voices must actually move (not a unison on the same pitch)
            prevNotes[i].midiPitch() != currNotes[i].midiPitch()) {
          final type =
              prevAbs == 7 ? 'parallel fifths' : 'parallel octaves/unisons';
          violations.add('Voices $i and $j: $type');
        }
      }
    }

    return violations;
  }
}
