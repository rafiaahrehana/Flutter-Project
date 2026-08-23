import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/performance/performance_models.dart';

/// An appraisal is a signed record that moves through five stages, so the
/// rules that matter are which actions are still open and what is safe to show.
void main() {
  PerformanceReview review({
    String stage = PerformanceStage.selfAssessment,
    bool finalised = false,
    Map<String, dynamic> extra = const {},
  }) =>
      PerformanceReview.fromJson({
        'id': 1,
        'employeeId': 9,
        'employeeName': 'Rafi Ahmed',
        'stage': stage,
        'finalised': finalised,
        ...extra,
      });

  group('stage progression', () {
    test('a review in flight can be advanced but not finalised', () {
      final early = review();

      expect(early.canAdvance, isTrue);
      expect(
        early.canFinalise,
        isFalse,
        reason: 'signing off before the last stage would skip the rest',
      );
    });

    test('only a completed review can be finalised', () {
      final done = review(stage: PerformanceStage.completed);

      expect(done.canFinalise, isTrue);
      expect(
        done.canAdvance,
        isFalse,
        reason: 'there is no stage after completed to advance into',
      );
    });

    test('a finalised review offers nothing at all', () {
      for (final stage in PerformanceStage.ordered) {
        final signed = review(stage: stage, finalised: true);
        expect(signed.canAdvance, isFalse, reason: stage);
        expect(signed.canFinalise, isFalse, reason: stage);
      }
    });

    test('stage index follows the documented order', () {
      expect(review(stage: PerformanceStage.selfAssessment).stageIndex, 0);
      expect(review(stage: PerformanceStage.hrApproval).stageIndex, 2);
      expect(review(stage: PerformanceStage.completed).stageIndex, 4);
    });

    test('an unknown stage falls back to the start, not off the end', () {
      // The stage bar indexes into a fixed list; a negative index would throw
      // and take the whole screen with it.
      final odd = review(stage: 'SOMETHING_NEW');

      expect(odd.stageIndex, 0);
      expect(odd.stageLabel, 'SOMETHING NEW');
    });
  });

  group('scores', () {
    test('shows only the dimensions somebody filled in', () {
      final partial = review(extra: {
        'scoreWorkQuality': 8,
        'scoreTeamwork': 6,
      });

      expect(partial.hasScores, isTrue);
      expect(partial.filledScores, hasLength(2));
      expect(
        partial.filledScores.map((s) => s.label),
        ['Work quality', 'Teamwork'],
        reason: 'order follows the appraisal form, not the payload',
      );
    });

    test('an unscored review shows no score panel', () {
      expect(review().hasScores, isFalse);
      expect(review().filledScores, isEmpty);
    });

    test('a zero is a real score, not a missing one', () {
      final zeroed = review(extra: {'scoreInitiative': 0});

      expect(
        zeroed.hasScores,
        isTrue,
        reason: 'zero out of ten is a judgement somebody made',
      );
    });
  });

  group('narrative', () {
    test('drops blank sections rather than rendering empty headings', () {
      final mixed = review(extra: {
        'strengths': 'Ships carefully.',
        'areasForImprovement': '   ',
        'comments': '',
      });

      expect(mixed.narrative, hasLength(1));
      expect(mixed.narrative.first.title, 'Strengths');
      expect(mixed.narrative.first.body, 'Ships carefully.');
    });

    test('keeps the sections in reading order', () {
      final full = review(extra: {
        'comments': 'c',
        'strengths': 's',
        'goalsForNextPeriod': 'g',
      });

      expect(
        full.narrative.map((s) => s.title),
        ['Strengths', 'Goals for next period', 'Comments'],
      );
    });
  });

  group('labels', () {
    test('falls back to an id when the employee has no name', () {
      final anonymous = PerformanceReview.fromJson({
        'id': 3,
        'employeeId': 42,
        'stage': 'MANAGER_REVIEW',
        'finalised': false,
      });

      expect(anonymous.personLabel, 'Employee #42');
    });

    test('names each stage in plain words', () {
      expect(
        review(stage: PerformanceStage.hrApproval).stageLabel,
        'HR approval',
      );
      expect(
        review(stage: PerformanceStage.selfAssessment).stageLabel,
        'Self assessment',
      );
    });

    test('a period needs at least one end of it', () {
      expect(review().period, isNull);
      expect(
        review(extra: {'reviewPeriodStart': '2026-01-01'}).period,
        '2026-01-01 → ?',
      );
    });
  });
}
