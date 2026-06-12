import '../models/note.dart';

/// A single figured bass figure: an interval number with an optional
/// chromatic alteration (-1 = flat, 0 = natural, 1 = sharp).
class Figure {
  final int number;
  final int alter;

  const Figure({required this.number, this.alter = 0});

  @override
  String toString() {
    final acc = switch (alter) { 1 => '#', -1 => 'b', _ => '' };
    return '$acc$number';
  }

  @override
  bool operator ==(Object other) =>
      other is Figure && other.number == number && other.alter == alter;

  @override
  int get hashCode => Object.hash(number, alter);
}

/// An expanded interval above the bass, with alteration and whether it was
/// explicitly given in the original figures.
class ExpandedInterval {
  final int interval;
  final int alter;
  final bool explicit;

  const ExpandedInterval({
    required this.interval,
    this.alter = 0,
    this.explicit = false,
  });

  @override
  String toString() {
    final acc = switch (alter) { 1 => '#', -1 => 'b', _ => '' };
    return '$acc$interval${explicit ? '*' : ''}';
  }
}

/// A single step in the unfigured-bass decision trace.
class TraceStep {
  final String test;
  final bool passed;
  final bool isDecision;
  final String? rule;
  final String? source;
  final String? figures;
  final String? reason;
  final List<RuleCitation> citations;

  const TraceStep({
    required this.test,
    required this.passed,
    this.isDecision = false,
    this.rule,
    this.source,
    this.figures,
    this.reason,
    this.citations = const [],
  });
}

/// The result of [FiguredBassInterpreter.unfiguredDecision].
class UnfiguredDecisionResult {
  final List<Figure> figures;
  final List<TraceStep> trace;

  const UnfiguredDecisionResult({
    required this.figures,
    required this.trace,
  });
}

/// A scholarly citation for a figured-bass rule.
class RuleCitation {
  final String author;
  final String ref;
  final String lang;
  final String text;
  final String translation;

  const RuleCitation({
    required this.author,
    required this.ref,
    required this.lang,
    required this.text,
    required this.translation,
  });
}

/// Interprets figured bass notation and computes the complete set of intervals
/// to realize above a given bass note.
///
/// Rules implemented from:
///   - St. Lambert (1707). Nouveau traite de l'accompagnement du Clavecin.
///   - Dandrieu (1719). Principes de l'Accompagnement du Clavecin.
///   - Heinichen (1728). Der General-Bass in der Composition.
///   - Telemann (1733). Singe-, Spiel- und General-Bass-Ubungen.
///   - Christensen, Jesper Boje (2002). 18th-Century Continuo Playing.
///   - Wead & Knopke, ICMC 2007 decision tree system.
///
/// Figured bass notation (MusicXML-style figure numbers):
///   (nothing)  -> 5 3       (root position triad)
///   6          -> 6 3       (first inversion triad)
///   6 4        -> 6 4       (second inversion triad -- cadential 6/4)
///   7          -> 7 5 3     (root position seventh chord)
///   6 5        -> 6 5 3     (first inversion seventh chord)
///   4 3        -> 4 3 6     (second inversion seventh chord -- 6/4/3)
///   4 2        -> 4 2 6     (third inversion seventh chord -- bass is 7th)
///   #4         -> #4 2 6    (tritone chord = third-inversion dominant seventh)
///   b5         -> b5 6 3    (diminished-fifth chord = first-inversion dom. 7th)
///   #5         -> #5 7 9 3  (augmented-fifth chord -- Christensen S14)
///   b7         -> b7 5 3    (diminished seventh chord -- Christensen S15)
///   4          -> 4 5       (suspended fourth -- 5/4 suspension)
///   5 4        -> 4 5       (same as 4 alone, explicit 5/4 notation)
///   9          -> 9 5 3     (suspended ninth -- major ninth with 5th and 3rd)
///   9 7        -> 9 7 3     (minor ninth with seventh and third)
///   2          -> 4 2 6     if alone; see 4/2 above
class FiguredBassInterpreter {
  const FiguredBassInterpreter();

  // ---------------------------------------------------------------------------
  // Rule citations
  // ---------------------------------------------------------------------------

  static const String _chr =
      '18th-Century Continuo Playing: A Historical Guide to the Basics. '
      'Kassel: Barenreiter, 2002';

  static String _cp(String p) =>
      'Translated in Christensen, $_chr, $p.';

  static final Map<String, List<RuleCitation>> _ruleCitations = {
    'leading_tone': [
      RuleCitation(
        author: 'Dandrieu, Jean-Francois',
        ref: "Principes de l'Accompagnement du Clavecin. Paris, 1719. ${_cp('17')}",
        lang: 'en',
        text: 'This chord consists of the diminished fifth, the sixth, and the '
            'third. It is usually played on the seventh degree of the scale '
            '-- the leading tone -- provided that it proceeds to the tonic '
            '(VII-I).',
        translation: 'The leading tone (scale degree 7) resolving to the tonic '
            'takes the diminished-fifth chord (b5/6/3 = V6/5, first inversion '
            'of the dominant seventh).',
      ),
    ],
    'ascending_passing': [
      RuleCitation(
        author: 'Lambert, Michel de',
        ref: "Nouveau traite de l'accompagnement du Clavecin. Paris, 1707. "
            "${_cp('42')}",
        lang: 'en',
        text: 'Whenever the bass proceeds in stepwise motion, it suffices to '
            'harmonize the notes that fall on the main beats of the bar and '
            'to treat the notes between them as passing notes.',
        translation: 'Scale degree 4 ascending by step in a passing context '
            'takes a 6th (first inversion) to avoid parallel fifths and '
            'maintain linear motion.',
      ),
    ],
    'petit_accord_supertonic': [
      RuleCitation(
        author: 'Dandrieu, Jean-Francois',
        ref: "Principes de l'Accompagnement du Clavecin. Paris, 1719. "
            "${_cp('14-15')}",
        lang: 'en',
        text: 'This chord, comprising the sixth, the third, and the fourth, '
            'is generally called the petite sixte. It is usually played on '
            'the second degree of the scale when [the bass] proceeds downward '
            'to the tonic. The sixth is almost invariably major.',
        translation: 'Scale degree 2 descending to the tonic takes 6/4/3 '
            '(the petite sixte -- second inversion of the dominant seventh), '
            'per the central rule of French basso continuo.',
      ),
    ],
    'subdominant_65': [
      RuleCitation(
        author: 'Dandrieu, Jean-Francois',
        ref: "Principes de l'Accompagnement du Clavecin. Paris, 1719. "
            "${_cp('21')}",
        lang: 'en',
        text: 'This chord is formed of the fifth, the sixth, and the third. '
            'It is generally played on the fourth degree of the scale, the '
            'subdominant, when followed by the dominant. The corresponding '
            'figure is 6/5.',
        translation: 'Scale degree 4 followed by the dominant takes a 6/5 '
            'chord (first-inversion supertonic seventh, or subdominant with '
            'added sixth).',
      ),
    ],
    'mediant_first_inv': [
      RuleCitation(
        author: 'Christensen, Jesper Boje',
        ref: '$_chr, 42.',
        lang: 'en',
        text: 'Whenever the bass proceeds in stepwise motion, it suffices to '
            'harmonize the notes that fall on the main beats of the bar and '
            'to treat the notes between them as passing notes.',
        translation: 'Scale degree 3 as a stepwise ascending passing tone '
            'takes a 6th (first inversion of I or VI).',
      ),
    ],
    'ascending_submediant': [
      RuleCitation(
        author: 'Christensen, Jesper Boje',
        ref: '$_chr, 10.',
        lang: 'en',
        text: 'The basic chord consists of the octave, the fifth, and the '
            'third. Scale degree 6 ascending by step represents the '
            'submediant triad in root position.',
        translation: 'Scale degree 6 ascending by step takes root position '
            '(5 3), forming the submediant triad (vi).',
      ),
    ],
    'descending_submediant': [
      RuleCitation(
        author: 'Dandrieu, Jean-Francois',
        ref: "Principes de l'Accompagnement du Clavecin. Paris, 1719. "
            "${_cp('13')}",
        lang: 'en',
        text: 'The Simple Sixth Chord consists of the sixth, the octave, and '
            'the third. It is usually played on the third degree of the '
            'scale. Its figure is written: 6.',
        translation: 'Scale degree 6 descending by step takes a 6th (IV6 in '
            'major), maintaining smooth voice leading.',
      ),
    ],
    'submediant_root_major': [
      RuleCitation(
        author: 'Christensen, Jesper Boje',
        ref: '$_chr, 10.',
        lang: 'en',
        text: 'Scale degree 6 with a leap or repeated note in major mode '
            'takes root position (5), forming the submediant triad (vi).',
        translation: 'Scale degree 6 with a leap or repeated note takes root '
            'position in major (vi triad).',
      ),
    ],
    'submediant_first_inv_minor': [
      RuleCitation(
        author: 'Christensen, Jesper Boje',
        ref: '$_chr, 10.',
        lang: 'en',
        text: 'Scale degree 6 with a leap or repeated note in minor mode '
            'takes a 6th (first inversion), since the minor submediant chord '
            'sits naturally in first inversion.',
        translation: 'Scale degree 6 with a leap or repeated note takes a '
            '6th in minor (first inversion).',
      ),
    ],
    'dominant_seventh': [
      RuleCitation(
        author: 'Rameau, Jean-Philippe',
        ref: "Traite de l'harmonie. Paris: Ballard, 1722, II.5.",
        lang: 'fr',
        text: 'La dominante qui precede la tonique par degres descendants '
            'recoit la septieme.',
        translation: 'The dominant preceding the tonic by descending step '
            'receives the seventh.',
      ),
      RuleCitation(
        author: 'Christensen, Jesper Boje',
        ref: '$_chr, 28.',
        lang: 'en',
        text: 'The dissonant 7 must always be resolved. When scale degree 5 '
            'descends by step to the tonic, the seventh chord intensifies '
            'the harmonic pull.',
        translation: 'When scale degree 5 is followed by a descending step, '
            'it takes a 7th figure (V7).',
      ),
    ],
    'dominant_root': [
      RuleCitation(
        author: 'Christensen, Jesper Boje',
        ref: '$_chr, 28.',
        lang: 'en',
        text: 'Scale degree 5 without a following descending step takes root '
            'position (5), forming the dominant triad (V). The full seventh '
            'chord is not required when there is no strong resolution motion '
            'following.',
        translation: 'Scale degree 5 without descending motion to the tonic '
            'takes root position (5 3).',
      ),
    ],
    'tonic_root': [
      RuleCitation(
        author: 'Christensen, Jesper Boje',
        ref: '$_chr, 10.',
        lang: 'en',
        text: 'The basic chord consists of the octave, the fifth, and the '
            'third. Scale degree 1 (tonic) always takes this root-position '
            'triad (I).',
        translation: 'Scale degree 1 (tonic) always takes root position '
            '(5 3), forming the tonic triad (I).',
      ),
    ],
    'cadential_64': [
      RuleCitation(
        author: 'Heinichen, Johann David',
        ref: 'Der General-Bass in der Composition. 2nd ed. Dresden, 1728 '
            '[1711]. ${_cp('72')}',
        lang: 'en',
        text: 'The fourth may also be combined with the sixth instead of the '
            'fifth. In this case, it is not necessarily tied over from the '
            'previous chord, but it is resolved downward as usual. The 6/4 '
            'and 5/4 chords occur most frequently in cadences; they should '
            'be played in cadences even when not expressly called for in the '
            'bass figures.',
        translation: 'A leap of a fourth to scale degree 4 suggests a '
            'cadential 6/4 chord (second inversion), used as harmonic '
            'preparation before a cadence.',
      ),
    ],
    'subdominant_root': [
      RuleCitation(
        author: 'Christensen, Jesper Boje',
        ref: '$_chr, 10.',
        lang: 'en',
        text: 'Scale degree 4 (subdominant) in most contexts takes root '
            'position (5), forming the subdominant triad (IV).',
        translation: 'Scale degree 4 in most contexts takes root position '
            '(5 3), forming the subdominant triad (IV).',
      ),
    ],
    'default_rule': [
      RuleCitation(
        author: 'Wead, Andrew, and Ian Knopke',
        ref: '"Basso Continuo Realization." In Proceedings of the '
            'International Computer Music Conference (ICMC). Copenhagen, 2007.',
        lang: 'en',
        text: 'Default harmonization: root position (5 3) when no specific '
            'rule matches the bass scale degree and melodic context.',
        translation: 'Default harmonization: root position (5 3) when no '
            'specific rule matches the bass scale degree and melodic context.',
      ),
    ],
    'tritone_chord_iv': [
      RuleCitation(
        author: 'Christensen, Jesper Boje',
        ref: '$_chr, 24.',
        lang: 'en',
        text: 'In this chord, the tritone is combined with the sixth and the '
            'second. It is generally played on the fourth or subdominant '
            'degree of the scale (IV) when followed by the mediant (III). '
            'Its figure may read #4 or natural. Another alternative is b4.',
        translation: 'Scale degree 4 followed by descending step to III '
            'takes the tritone chord (#4/6/2 = V4/2, third inversion of the '
            'dominant seventh).',
      ),
    ],
    'augmented_fifth': [
      RuleCitation(
        author: 'Christensen, Jesper Boje',
        ref: '$_chr, 35-36.',
        lang: 'en',
        text: 'The augmented-fifth chord combines the #5 with the seventh '
            'and the ninth: 9/7/#5/3. It typically occurs on the tonic or '
            'submediant bass note and creates a highly dissonant, expressive '
            'sonority that demands resolution.',
        translation: 'Figure #5 expands to the augmented-fifth chord: '
            '3, #5, 7, 9 -- a dissonant chromatic chord requiring careful '
            'voice-leading resolution.',
      ),
    ],
    'diminished_seventh': [
      RuleCitation(
        author: 'Christensen, Jesper Boje',
        ref: '$_chr, 36-37.',
        lang: 'en',
        text: 'The diminished seventh chord consists of the diminished '
            'seventh, the diminished fifth, and the minor third above the '
            'bass. Figure b7 (alone) signals this fully diminished chord. '
            'It most commonly appears on the raised seventh degree (leading '
            'tone) in minor mode and resolves inward on all voices.',
        translation: 'Figure b7 alone expands to the diminished seventh '
            'chord: 3, 5, b7 -- all intervals diminished relative to the '
            'bass, resolving to the tonic chord.',
      ),
    ],
  };

  /// Returns the citations for a given rule key, or an empty list if not found.
  static List<RuleCitation> ruleCitations(String rule) =>
      _ruleCitations[rule] ?? const [];

  // ---------------------------------------------------------------------------
  // expand()
  // ---------------------------------------------------------------------------

  /// Given raw figures (list of [Figure]), return the expanded, ordered list
  /// of generic intervals to place above the bass.
  ///
  /// [rawFigures] e.g. `[Figure(number: 6, alter: 0), Figure(number: 5, alter: 1)]`
  /// [bass] the bass note (for context)
  /// [keyFifths] number of sharps (+) or flats (-) in the key signature
  /// [keyMode] 'major' or 'minor'
  List<ExpandedInterval> expand(
    List<Figure> rawFigures,
    Note bass,
    int keyFifths,
    String keyMode,
  ) {
    // Sort figures descending (highest interval first)
    final sorted = List<Figure>.of(rawFigures)
      ..sort((a, b) => b.number.compareTo(a.number));

    final nums = sorted.map((f) => f.number).toList();

    // Helper: get the alter value for a specific figure number (null = absent)
    int? alterOf(int n) {
      for (final f in sorted) {
        if (f.number == n) return f.alter;
      }
      return null;
    }

    // No figures -> root-position triad
    if (nums.isEmpty) {
      return _withAlters([3, 5], sorted);
    }

    // Figure "6" alone -> first inversion: 3, 6
    if (_listEquals(nums, [6])) {
      return _withAlters([3, 6], sorted);
    }

    // Figure "4 2", "6 4 2", or "2" alone -> third inversion 7th chord: 2, 4, 6
    // Must come before the "6 4" check so that [6,4,2] is not mistaken for
    // a cadential 6/4.
    if (nums.contains(2) && !nums.contains(9)) {
      return _withAlters([2, 4, 6], sorted);
    }

    // Figure "4 3" or "6 4 3" -> second inversion 7th chord: 3, 4, 6 (= 6/4/3)
    // Must come before the "6 4" and suspended-4 checks.
    if (nums.contains(4) && nums.contains(3)) {
      return _withAlters([3, 4, 6], sorted);
    }

    // Figure "#4" (augmented fourth / tritone chord, Christensen pp. 24-25):
    // Third-inversion dominant seventh -> 2, #4, 6.
    // Must come before cadential-6/4 and suspended-4 checks.
    if (nums.contains(4) && (alterOf(4) ?? 0) > 0) {
      return _withAlters([2, 4, 6], sorted);
    }

    // Figure "6 4" -> second inversion (cadential or passing 6/4): 4, 6
    if (_listEquals(nums, [6, 4])) {
      return _withAlters([4, 6], sorted);
    }

    // Figure "b7" alone (diminished seventh, Christensen pp. 36-37):
    // Fully diminished seventh chord: 3, 5, b7.
    // Must come before the plain-7 check so the alteration is not ignored.
    if (_listEquals(nums, [7]) && (alterOf(7) ?? 0) < 0) {
      return _withAlters([3, 5, 7], sorted);
    }

    // Figure "7" alone -> root-position 7th chord: 3, 5, 7
    if (_listEquals(nums, [7])) {
      return _withAlters([3, 5, 7], sorted);
    }

    // Figure "7 5" or "7 5 3" -> root-position 7th (explicit): 3, 5, 7
    if (nums.contains(7) && nums.contains(5)) {
      return _withAlters([3, 5, 7], sorted);
    }

    // Figure "6 5", "6 5 3" -> first inversion 7th chord: 3, 5, 6 (= 6/5/3)
    if (nums.contains(6) && nums.contains(5)) {
      return _withAlters([3, 5, 6], sorted);
    }

    // Figure "9 7" (minor ninth + seventh, Christensen p. 30):
    // Must come before the general 9 check.
    if (nums.contains(9) && nums.contains(7)) {
      return _withAlters([3, 7, 9], sorted);
    }

    // Figure "9" alone or "9 5" -> suspended major ninth: 3, 5, 9
    if (nums.contains(9)) {
      return _withAlters([3, 5, 9], sorted);
    }

    // Suspension "7 6" -- bass stays, 7 resolves to 6
    if (_listEquals(nums, [7, 6])) {
      return _withAlters([3, 7], sorted);
    }

    // Figure "b5" alone (diminished-fifth chord, Christensen pp. 16-17):
    // First-inversion dominant seventh -> 3, b5, 6.
    // A plain "5" with no alteration falls through to the [3,5] root-position
    // handling below.
    if (_listEquals(nums, [5]) && (alterOf(5) ?? 0) < 0) {
      return _withAlters([3, 5, 6], sorted);
    }

    // Suspended fourth: "4" alone, "5/4" (explicit), "4/5/8", etc. -- any
    // combination that includes 4 but not 2, 3, 6, 7, 9, and where the 4 is
    // not augmented (#4 handled above).
    // Christensen pp. 22-23: the four is combined with the fifth (and octave).
    if (nums.contains(4) &&
        !nums.contains(2) &&
        !nums.contains(3) &&
        !nums.contains(6) &&
        !nums.contains(7) &&
        !nums.contains(9)) {
      return _withAlters([4, 5], sorted);
    }

    // Figure "#5" (augmented-fifth chord, Christensen pp. 35-36):
    // Augmented fifth combined with seventh and ninth: 3, #5, 7, 9.
    // Must come before the plain-5 check.
    if (_listEquals(nums, [5]) && (alterOf(5) ?? 0) > 0) {
      return _withAlters([3, 5, 7, 9], sorted);
    }

    // Figure "5" alone -> root position triad: 3, 5
    if (_listEquals(nums, [5])) {
      return _withAlters([3, 5], sorted);
    }

    // Diminished 7th: "7 3" with b-alter on 3 and 5
    if (nums.contains(7) && nums.contains(3)) {
      return _withAlters([3, 5, 7], sorted);
    }

    // Fallback: use the numbers as given + fill in 3 if not present
    final intervals = List<int>.of(nums);
    if (!intervals.contains(3)) {
      intervals.add(3);
    }
    intervals.sort();
    return _withAlters(intervals, sorted);
  }

  /// Take a list of generic intervals and annotate each with the correct
  /// alteration from the raw figures (override over key-signature default).
  List<ExpandedInterval> _withAlters(
    List<int> intervals,
    List<Figure> rawFigures,
  ) {
    // Build a lookup from figure number -> alter
    final alterMap = <int, int>{};
    for (final f in rawFigures) {
      alterMap[f.number] = f.alter;
    }

    return [
      for (final interval in intervals)
        ExpandedInterval(
          interval: interval,
          alter: alterMap[interval] ?? 0,
          explicit: alterMap.containsKey(interval),
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // unfiguredDecision()
  // ---------------------------------------------------------------------------

  /// Unfigured bass decision tree (Gasparini / Delair rules).
  ///
  /// Determines the most likely figured bass for an unfigured bass note
  /// based on:
  ///  - Scale degree of the bass note (1..7)
  ///  - Melodic motion ('step-up','step-down','leap-up','leap-down','same','start')
  ///  - Next motion (motion to the following note)
  ///  - Mode ('major'|'minor')
  ///  - Leap size in generic intervals (e.g. 4 for a fourth)
  UnfiguredDecisionResult unfiguredDecision({
    required int scaleDegree,
    required String motion,
    required String nextMotion,
    required String mode,
    int leapSize = 0,
  }) {
    final isMajor = mode.toLowerCase() == 'major';
    final trace = <TraceStep>[];

    // --- Gasparini Rule Set (primary) ---

    // Scale degree 7:
    //  * In major: the leading tone (sensibile) takes V6 (first inversion)
    //    when it resolves upward by step to tonic -- Gasparini's rule.
    //  * In minor: scale degree 7 is the natural subtonic (e.g. D in E minor),
    //    which forms a major triad (VII) in root position.
    if (scaleDegree == 7) {
      trace.add(const TraceStep(
        test: 'Is scale degree 7 (leading tone)?',
        passed: true,
      ));
      if (isMajor) {
        trace.add(const TraceStep(
          test: 'Is the mode major?',
          passed: true,
        ));
        // Leading tone resolving upward to tonic (VII->I) ->
        // diminished-fifth chord (b5/6/3 = V6/5)
        if (nextMotion == 'step-up') {
          trace.add(TraceStep(
            test: 'Does next motion resolve upward by step?',
            passed: true,
            isDecision: true,
            rule: 'Leading-tone diminished-fifth chord',
            source: 'Dandrieu 1719; Christensen S4',
            figures: 'b5',
            reason: 'Leading tone (VII) resolving to tonic takes the '
                'diminished-fifth chord (b5/6/3 = V6/5).',
            citations: ruleCitations('leading_tone'),
          ));
          return UnfiguredDecisionResult(
            figures: const [Figure(number: 5, alter: -1)],
            trace: trace,
          );
        }
        // Other contexts (descending scale, leap) -> simple sixth chord (V6)
        trace.add(TraceStep(
          test: 'Does next motion resolve upward by step?',
          passed: false,
          isDecision: true,
          rule: 'Leading-tone sixth chord',
          source: 'Dandrieu 1719; Christensen S4',
          figures: '6',
          reason: 'Leading tone in other contexts takes the sixth chord (V6).',
          citations: ruleCitations('leading_tone'),
        ));
        return UnfiguredDecisionResult(
          figures: _makeFig([6]),
          trace: trace,
        );
      }
      // Minor subtonic (natural bVII) -> root position major triad
      trace.add(TraceStep(
        test: 'Is the mode major?',
        passed: false,
        isDecision: true,
        rule: 'Default root position',
        source: 'Wead & Knopke 2007',
        figures: '5 3',
        reason: 'Minor subtonic (natural bVII) takes root position.',
        citations: ruleCitations('default_rule'),
      ));
      return UnfiguredDecisionResult(
        figures: _makeFig([5, 3]),
        trace: trace,
      );
    }
    trace.add(const TraceStep(
      test: 'Is scale degree 7 (leading tone)?',
      passed: false,
    ));

    // Scale degree 4 (subdominant) followed by ascending step to dominant -> 6/5
    // (Dandrieu, Christensen p. 21): IV -> V takes the six-five chord.
    // Must come BEFORE the ascending-passing check.
    if (scaleDegree == 4 && nextMotion == 'step-up' && motion != 'step-up') {
      trace.add(TraceStep(
        test: 'Is scale degree 4 with next step up (not approached by step up)?',
        passed: true,
        isDecision: true,
        rule: 'Subdominant six-five chord',
        source: 'Dandrieu 1719; Christensen p. 21',
        figures: '6 5',
        reason: 'Scale degree 4 followed by dominant takes a 6/5 chord.',
        citations: ruleCitations('subdominant_65'),
      ));
      return UnfiguredDecisionResult(
        figures: _makeFig([6, 5]),
        trace: trace,
      );
    }
    if (scaleDegree == 4) {
      trace.add(const TraceStep(
        test: 'Is scale degree 4 with next step up (not approached by step up)?',
        passed: false,
      ));
    }

    // Scale degree 4 ascending step -> 6 (passing) -- true passing-tone context:
    // both the approach AND the continuation are step-up (III -> IV -> V).
    if (scaleDegree == 4 && motion == 'step-up' && nextMotion == 'step-up') {
      trace.add(TraceStep(
        test: 'Is scale degree 4 as ascending passing tone (step-up both sides)?',
        passed: true,
        isDecision: true,
        rule: 'Ascending passing tone',
        source: 'Lambert 1707; Christensen p. 42',
        figures: '6',
        reason: 'Scale degree 4 ascending by step in a passing context takes '
            'a 6th (first inversion).',
        citations: ruleCitations('ascending_passing'),
      ));
      return UnfiguredDecisionResult(
        figures: _makeFig([6]),
        trace: trace,
      );
    }
    trace.add(const TraceStep(
      test: 'Is scale degree 4 as ascending passing tone (step-up both sides)?',
      passed: false,
    ));

    // Scale degree 2 (supertonic):
    //  * Petite sixte (6/4/3) when leading by step to I or III.
    //  * Otherwise root position.
    if (scaleDegree == 2) {
      trace.add(const TraceStep(
        test: 'Is scale degree 2 (supertonic)?',
        passed: true,
      ));
      // Petite sixte on degree II leading by step to I or III
      if (nextMotion == 'step-down' || nextMotion == 'step-up') {
        trace.add(TraceStep(
          test: 'Does next motion lead by step to I or III?',
          passed: true,
          isDecision: true,
          rule: 'Petite sixte on supertonic',
          source: 'Dandrieu 1719; Christensen pp. 14-15',
          figures: '6 4 3',
          reason: 'Scale degree 2 leading by step takes the petite sixte '
              '(6/4/3 = second inversion of the dominant seventh).',
          citations: ruleCitations('petit_accord_supertonic'),
        ));
        return UnfiguredDecisionResult(
          figures: _makeFig([6, 4, 3]),
          trace: trace,
        );
      }
      // All other supertonic contexts -> fall through to default
      trace.add(const TraceStep(
        test: 'Does next motion lead by step to I or III?',
        passed: false,
      ));
    }
    // (degree 2 falls through to the default root-position rule below)
    if (scaleDegree != 2) {
      trace.add(const TraceStep(
        test: 'Is scale degree 2 (supertonic)?',
        passed: false,
      ));
    }

    // Scale degree 3 (mediant) -> first inversion only when ascending stepwise
    // passing tone (both motions are step-up).
    if (scaleDegree == 3) {
      trace.add(const TraceStep(
        test: 'Is scale degree 3 (mediant)?',
        passed: true,
      ));
      final isStepwise = (motion == 'step-up' && nextMotion == 'step-up');
      if (isStepwise) {
        trace.add(TraceStep(
          test: 'Is it a stepwise ascending passing tone?',
          passed: true,
          isDecision: true,
          rule: 'Mediant first inversion',
          source: 'Christensen p. 42',
          figures: '6',
          reason: 'Scale degree 3 as a stepwise ascending passing tone takes '
              'a 6th (first inversion).',
          citations: ruleCitations('mediant_first_inv'),
        ));
        return UnfiguredDecisionResult(
          figures: _makeFig([6]),
          trace: trace,
        );
      }
      // Mediant at a leap or as a structural note -> root position
      trace.add(TraceStep(
        test: 'Is it a stepwise ascending passing tone?',
        passed: false,
        isDecision: true,
        rule: 'Default root position',
        source: 'Wead & Knopke 2007',
        figures: '5 3',
        reason: 'Mediant at a leap or as a structural note takes root position.',
        citations: ruleCitations('default_rule'),
      ));
      return UnfiguredDecisionResult(
        figures: _makeFig([5, 3]),
        trace: trace,
      );
    }
    trace.add(const TraceStep(
      test: 'Is scale degree 3 (mediant)?',
      passed: false,
    ));

    // Scale degree 6 -> depends on context
    if (scaleDegree == 6) {
      trace.add(const TraceStep(
        test: 'Is scale degree 6 (submediant)?',
        passed: true,
      ));
      // Submediant ascending step -> 5 3 (vi)
      if (motion == 'step-up') {
        trace.add(TraceStep(
          test: 'Was the approach motion step-up?',
          passed: true,
          isDecision: true,
          rule: 'Ascending submediant root position',
          source: 'Christensen p. 10',
          figures: '5 3',
          reason: 'Scale degree 6 ascending by step takes root position (vi).',
          citations: ruleCitations('ascending_submediant'),
        ));
        return UnfiguredDecisionResult(
          figures: _makeFig([5, 3]),
          trace: trace,
        );
      }
      trace.add(const TraceStep(
        test: 'Was the approach motion step-up?',
        passed: false,
      ));
      // Submediant descending -> 6 (IV6) in major only.
      if (motion == 'step-down' && isMajor) {
        trace.add(TraceStep(
          test: 'Was the approach motion step-down (major mode)?',
          passed: true,
          isDecision: true,
          rule: 'Descending submediant sixth chord',
          source: 'Dandrieu 1719; Christensen p. 13',
          figures: '6',
          reason: 'Scale degree 6 descending by step takes a 6th (IV6 in major).',
          citations: ruleCitations('descending_submediant'),
        ));
        return UnfiguredDecisionResult(
          figures: _makeFig([6]),
          trace: trace,
        );
      }
      // All remaining submediant contexts -> root position
      trace.add(TraceStep(
        test: 'Was the approach motion step-down (major mode)?',
        passed: false,
        isDecision: true,
        rule: 'Submediant root position',
        source: 'Christensen p. 10',
        figures: '5 3',
        reason: 'Submediant in remaining contexts takes root position.',
        citations: ruleCitations('submediant_root_major'),
      ));
      return UnfiguredDecisionResult(
        figures: _makeFig([5, 3]),
        trace: trace,
      );
    }
    trace.add(const TraceStep(
      test: 'Is scale degree 6 (submediant)?',
      passed: false,
    ));

    // Scale degree 5 (dominant)
    if (scaleDegree == 5) {
      trace.add(const TraceStep(
        test: 'Is scale degree 5 (dominant)?',
        passed: true,
      ));
      // If next motion descends by step to 1 -> use V7
      if (nextMotion == 'step-down') {
        trace.add(TraceStep(
          test: 'Does next motion descend by step (toward tonic)?',
          passed: true,
          isDecision: true,
          rule: 'Dominant seventh chord',
          source: 'Rameau 1722; Christensen p. 28',
          figures: '7',
          reason: 'Scale degree 5 descending by step to tonic takes V7.',
          citations: ruleCitations('dominant_seventh'),
        ));
        return UnfiguredDecisionResult(
          figures: _makeFig([7]),
          trace: trace,
        );
      }
      trace.add(TraceStep(
        test: 'Does next motion descend by step?',
        passed: false,
        isDecision: true,
        rule: 'Dominant root position',
        source: 'Christensen p. 28',
        figures: '5 3',
        reason: 'Scale degree 5 without descending step takes root position (V).',
        citations: ruleCitations('dominant_root'),
      ));
      return UnfiguredDecisionResult(
        figures: _makeFig([5, 3]),
        trace: trace,
      );
    }
    trace.add(const TraceStep(
      test: 'Is scale degree 5 (dominant)?',
      passed: false,
    ));

    // Scale degree 1 (tonic) -> I (5/3) always
    if (scaleDegree == 1) {
      trace.add(TraceStep(
        test: 'Is scale degree 1 (tonic)?',
        passed: true,
        isDecision: true,
        rule: 'Tonic root position',
        source: 'Christensen p. 10',
        figures: '5 3',
        reason: 'Scale degree 1 (tonic) always takes root position (I).',
        citations: ruleCitations('tonic_root'),
      ));
      return UnfiguredDecisionResult(
        figures: _makeFig([5, 3]),
        trace: trace,
      );
    }
    trace.add(const TraceStep(
      test: 'Is scale degree 1 (tonic)?',
      passed: false,
    ));

    // Scale degree 4 (subdominant) -- reached only if earlier degree-4 checks
    // (6/5, ascending passing) did not match.
    if (scaleDegree == 4) {
      trace.add(const TraceStep(
        test: 'Is scale degree 4 (subdominant)?',
        passed: true,
      ));
      // Leap of 4th up or 5th down -> cadential 6/4
      if (leapSize == 4 &&
          (motion == 'leap-up' || motion == 'leap-down')) {
        trace.add(TraceStep(
          test: 'Was there a leap of a fourth?',
          passed: true,
          isDecision: true,
          rule: 'Cadential 6/4',
          source: 'Heinichen 1728; Christensen p. 72',
          figures: '6 4',
          reason: 'A leap of a fourth to scale degree 4 suggests a cadential '
              '6/4 chord.',
          citations: ruleCitations('cadential_64'),
        ));
        return UnfiguredDecisionResult(
          figures: _makeFig([6, 4]),
          trace: trace,
        );
      }
      trace.add(const TraceStep(
        test: 'Was there a leap of a fourth?',
        passed: false,
      ));
      // Descending step to mediant (IV -> III) -> tritone chord (#4/6/2 = V4/2)
      if (nextMotion == 'step-down') {
        trace.add(TraceStep(
          test: 'Does next motion descend by step to mediant?',
          passed: true,
          isDecision: true,
          rule: 'Tritone chord on subdominant',
          source: 'Christensen S8, p. 24',
          figures: '#4',
          reason: 'Scale degree 4 followed by descending step to III takes '
              'the tritone chord (#4/6/2 = V4/2).',
          citations: ruleCitations('tritone_chord_iv'),
        ));
        return UnfiguredDecisionResult(
          figures: const [Figure(number: 4, alter: 1)],
          trace: trace,
        );
      }
      trace.add(TraceStep(
        test: 'Does next motion descend by step to mediant?',
        passed: false,
        isDecision: true,
        rule: 'Subdominant root position',
        source: 'Christensen p. 10',
        figures: '5 3',
        reason: 'Scale degree 4 in remaining contexts takes root position (IV).',
        citations: ruleCitations('subdominant_root'),
      ));
      return UnfiguredDecisionResult(
        figures: _makeFig([5, 3]),
        trace: trace,
      );
    }
    trace.add(const TraceStep(
      test: 'Is scale degree 4 (subdominant)?',
      passed: false,
    ));

    // Default -> root position triad
    trace.add(TraceStep(
      test: 'Default rule (no specific match)',
      passed: true,
      isDecision: true,
      rule: 'Default root position',
      source: 'Wead & Knopke 2007',
      figures: '5 3',
      reason: 'Default harmonization: root position (5 3).',
      citations: ruleCitations('default_rule'),
    ));
    return UnfiguredDecisionResult(
      figures: _makeFig([5, 3]),
      trace: trace,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Create a list of [Figure] with alter = 0 for each number.
  static List<Figure> _makeFig(List<int> numbers) =>
      [for (final n in numbers) Figure(number: n)];

  /// Compare two lists of ints for value equality.
  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
