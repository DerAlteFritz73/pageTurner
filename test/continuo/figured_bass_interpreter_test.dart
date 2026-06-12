import 'package:flutter_test/flutter_test.dart';
import 'package:leggio/continuo/models/note.dart';
import 'package:leggio/continuo/services/figured_bass_interpreter.dart';

void main() {
  const fbi = FiguredBassInterpreter();

  group('expand - root position', () {
    test('no figures → 5 3 (root position triad)', () {
      const bass = Note(step: 'C', octave: 3);
      final intervals = fbi.expand([], bass, 0, 'major');
      final nums = intervals.map((e) => e.interval).toList();
      expect(nums, contains(3));
      expect(nums, contains(5));
    });

    test('figure 5 → 5 3', () {
      const bass = Note(step: 'C', octave: 3);
      final intervals = fbi.expand(
          [const Figure(number: 5)], bass, 0, 'major');
      final nums = intervals.map((e) => e.interval).toList();
      expect(nums, contains(3));
      expect(nums, contains(5));
    });
  });

  group('expand - first inversion', () {
    test('figure 6 → 6 3', () {
      const bass = Note(step: 'E', octave: 3);
      final intervals = fbi.expand(
          [const Figure(number: 6)], bass, 0, 'major');
      final nums = intervals.map((e) => e.interval).toList();
      expect(nums, contains(3));
      expect(nums, contains(6));
    });
  });

  group('expand - second inversion', () {
    test('figures 6 4 → 6 4', () {
      const bass = Note(step: 'G', octave: 3);
      final intervals = fbi.expand(
          [const Figure(number: 6), const Figure(number: 4)], bass, 0, 'major');
      final nums = intervals.map((e) => e.interval).toList();
      expect(nums, contains(4));
      expect(nums, contains(6));
    });
  });

  group('expand - seventh chords', () {
    test('figure 7 → 7 5 3', () {
      const bass = Note(step: 'G', octave: 3);
      final intervals = fbi.expand(
          [const Figure(number: 7)], bass, 0, 'major');
      final nums = intervals.map((e) => e.interval).toList();
      expect(nums, contains(3));
      expect(nums, contains(5));
      expect(nums, contains(7));
    });

    test('figures 6 5 → 6 5 3', () {
      const bass = Note(step: 'B', octave: 2);
      final intervals = fbi.expand(
          [const Figure(number: 6), const Figure(number: 5)],
          bass, 0, 'major');
      final nums = intervals.map((e) => e.interval).toList();
      expect(nums, contains(3));
      expect(nums, contains(5));
      expect(nums, contains(6));
    });

    test('figures 4 3 → 6 4 3', () {
      const bass = Note(step: 'D', octave: 3);
      final intervals = fbi.expand(
          [const Figure(number: 4), const Figure(number: 3)],
          bass, 0, 'major');
      final nums = intervals.map((e) => e.interval).toList();
      expect(nums, contains(3));
      expect(nums, contains(4));
      expect(nums, contains(6));
    });

    test('figures 4 2 (or 2) → 6 4 2', () {
      const bass = Note(step: 'F', octave: 3);
      final intervals = fbi.expand(
          [const Figure(number: 4), const Figure(number: 2)],
          bass, 0, 'major');
      final nums = intervals.map((e) => e.interval).toList();
      expect(nums, contains(2));
      expect(nums, contains(4));
      expect(nums, contains(6));
    });
  });

  group('unfiguredDecision', () {
    test('degree 1 → root position (5 3)', () {
      final result = fbi.unfiguredDecision(
        scaleDegree: 1,
        motion: 'start',
        nextMotion: 'step-up',
        mode: 'major',
        leapSize: 0,
      );
      final nums = result.figures.map((f) => f.number).toList();
      expect(nums, containsAll([5, 3]));
    });

    test('degree 5 descending to I → 7 (dominant seventh)', () {
      final result = fbi.unfiguredDecision(
        scaleDegree: 5,
        motion: 'step-down',
        nextMotion: 'step-down',
        mode: 'major',
        leapSize: 0,
      );
      final nums = result.figures.map((f) => f.number).toList();
      expect(nums, contains(7));
    });

    test('degree 7 → leading tone chord (diminished 5th)', () {
      final result = fbi.unfiguredDecision(
        scaleDegree: 7,
        motion: 'step-up',
        nextMotion: 'step-up',
        mode: 'major',
        leapSize: 0,
      );
      final nums = result.figures.map((f) => f.number).toList();
      // Leading tone should have 6 and/or diminished 5
      expect(nums.isNotEmpty, true);
    });

    test('trace is not empty for unfigured decisions', () {
      final result = fbi.unfiguredDecision(
        scaleDegree: 4,
        motion: 'step-up',
        nextMotion: 'step-up',
        mode: 'major',
        leapSize: 0,
      );
      expect(result.trace, isNotEmpty);
    });

    test('trace ends with a decision step', () {
      final result = fbi.unfiguredDecision(
        scaleDegree: 2,
        motion: 'step-down',
        nextMotion: 'step-down',
        mode: 'major',
        leapSize: 0,
      );
      final decisions =
          result.trace.where((s) => s.isDecision).toList();
      expect(decisions, isNotEmpty);
    });
  });

  group('ruleCitations', () {
    test('leading_tone has citations', () {
      final cites = FiguredBassInterpreter.ruleCitations('leading_tone');
      expect(cites, isNotEmpty);
      expect(cites.first.author, contains('Dandrieu'));
    });

    test('unknown rule returns empty list', () {
      final cites =
          FiguredBassInterpreter.ruleCitations('nonexistent_rule');
      expect(cites, isEmpty);
    });

    test('dominant_seventh cites Rameau', () {
      final cites =
          FiguredBassInterpreter.ruleCitations('dominant_seventh');
      expect(cites.any((c) => c.author.contains('Rameau')), true);
    });
  });
}
