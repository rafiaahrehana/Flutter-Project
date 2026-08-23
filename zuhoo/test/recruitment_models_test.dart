import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/recruitment/recruitment_models.dart';

/// Hiring is a pipeline, so almost every decision the UI makes is "what can
/// happen to this next" — which stages to offer, whether an interview still
/// needs feedback, whether an offer is still live.
void main() {
  group('JobPosting', () {
    JobPosting job({String status = JobPostingStatus.open, String? deadline}) =>
        JobPosting.fromJson({
          'id': 1,
          'title': 'Senior Engineer',
          'status': status,
          'vacancies': 2,
          'deadline': deadline,
        });

    test('a draft can be published, a closed posting reopened', () {
      expect(job(status: JobPostingStatus.draft).canPublish, isTrue);
      expect(job(status: JobPostingStatus.onHold).canPublish, isTrue);
      expect(
        job(status: JobPostingStatus.open).canPublish,
        isFalse,
        reason: 'publishing something already live is a no-op',
      );
    });

    test('anything not already closed can be closed', () {
      expect(job(status: JobPostingStatus.open).canClose, isTrue);
      expect(job(status: JobPostingStatus.draft).canClose, isTrue);
      expect(job(status: JobPostingStatus.closed).canClose, isFalse);
    });

    test('flags a live posting whose deadline has passed', () {
      final past = DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String()
          .split('T')
          .first;
      final future = DateTime.now()
          .add(const Duration(days: 2))
          .toIso8601String()
          .split('T')
          .first;

      expect(job(deadline: past).deadlinePassed, isTrue);
      expect(job(deadline: future).deadlinePassed, isFalse);
      expect(
        job(status: JobPostingStatus.closed, deadline: past).deadlinePassed,
        isFalse,
        reason: 'a closed posting is not accepting applications regardless',
      );
      expect(job().deadlinePassed, isFalse);
    });

    test('falls back to the job title when the posting has no title', () {
      final untitled = JobPosting.fromJson({
        'id': 1,
        'status': 'OPEN',
        'vacancies': 1,
        'jobTitle': 'Engineer',
      });

      expect(untitled.title, 'Engineer');
    });

    test('remote and location combine into one line', () {
      JobPosting where({bool remote = false, String? location}) =>
          JobPosting.fromJson({
            'id': 1,
            'title': 'Role',
            'status': 'OPEN',
            'vacancies': 1,
            'remote': remote,
            'location': location,
          });

      expect(where(remote: true, location: 'Dhaka').whereLabel, 'Remote · Dhaka');
      expect(where(remote: true).whereLabel, 'Remote');
      expect(where(location: 'Dhaka').whereLabel, 'Dhaka');
      expect(where().whereLabel, isNull);
    });
  });

  group('JobApplication stage moves', () {
    JobApplication at(String status) => JobApplication.fromJson({
          'id': 1,
          'status': status,
          'candidateName': 'Nadia Karim',
        });

    test('never offers the stage it is already in', () {
      final shortlisted = at(ApplicationStatus.shortlisted);

      expect(
        shortlisted.nextStatuses,
        isNot(contains(ApplicationStatus.shortlisted)),
        reason: 'a move to the current stage is a no-op the API would accept',
      );
    });

    test('offers rejection and withdrawal from any live stage', () {
      for (final status in ApplicationStatus.pipeline) {
        final options = at(status).nextStatuses;
        expect(options, contains(ApplicationStatus.rejected), reason: status);
        expect(options, contains(ApplicationStatus.withdrawn), reason: status);
      }
    });

    test('a finished application offers nothing at all', () {
      for (final status in ApplicationStatus.terminal) {
        expect(
          at(status).nextStatuses,
          isEmpty,
          reason: '$status is terminal — the backend models no way back',
        );
      }
    });

    test('hired is terminal and recognised as such', () {
      expect(at(ApplicationStatus.hired).isHired, isTrue);
      expect(at(ApplicationStatus.hired).isTerminal, isTrue);
      expect(at(ApplicationStatus.applied).isTerminal, isFalse);
    });

    test('knows whether anybody has scored it', () {
      expect(at(ApplicationStatus.applied).hasScores, isFalse);

      final scored = JobApplication.fromJson({
        'id': 1,
        'status': 'SCREENING',
        'scoreEducation': 7,
      });

      expect(
        scored.hasScores,
        isTrue,
        reason: 'one score is enough to show the panel',
      );
    });

    test('falls back to an id when the candidate has no name', () {
      final anonymous = JobApplication.fromJson({
        'id': 5,
        'status': 'APPLIED',
        'candidateId': 42,
      });

      expect(anonymous.personLabel, 'Candidate #42');
    });
  });

  group('Interview', () {
    Interview at(String scheduledAt, {String status = 'SCHEDULED'}) =>
        Interview.fromJson({
          'id': 1,
          'jobApplicationId': 2,
          'status': status,
          'scheduledAt': scheduledAt,
        });

    String iso(Duration offset) =>
        DateTime.now().add(offset).toIso8601String();

    test('a passed slot still marked scheduled is awaiting feedback', () {
      expect(at(iso(const Duration(hours: -2))).awaitingFeedback, isTrue);
    });

    test('a future slot is not awaiting anything', () {
      expect(at(iso(const Duration(hours: 2))).awaitingFeedback, isFalse);
    });

    test('a completed interview is never awaiting feedback', () {
      expect(
        at(iso(const Duration(hours: -2)), status: 'COMPLETED')
            .awaitingFeedback,
        isFalse,
        reason: 'feedback has already been given — that is what completed it',
      );
    });

    test('recognises today regardless of the hour', () {
      expect(at(iso(const Duration(hours: 3))).isToday, isTrue);
      expect(at(iso(const Duration(days: 3))).isToday, isFalse);
    });

    test('an unreadable date never claims to be today or overdue', () {
      final broken = Interview.fromJson({
        'id': 1,
        'jobApplicationId': 2,
        'status': 'SCHEDULED',
        'scheduledAt': 'not-a-date',
      });

      expect(broken.isToday, isFalse);
      expect(broken.awaitingFeedback, isFalse);
    });

    test('feedback is present when either a rating or a call exists', () {
      Interview withFeedback(Map<String, dynamic> extra) =>
          Interview.fromJson({
            'id': 1,
            'jobApplicationId': 2,
            'status': 'COMPLETED',
            ...extra,
          });

      expect(withFeedback({'rating': 4}).hasFeedback, isTrue);
      expect(withFeedback({'recommendation': 'HIRE'}).hasFeedback, isTrue);
      expect(withFeedback({}).hasFeedback, isFalse);
    });
  });

  group('JobOffer', () {
    JobOffer offer({String status = OfferStatus.sent, bool expired = false}) =>
        JobOffer.fromJson({
          'id': 1,
          'jobApplicationId': 2,
          'status': status,
          'expired': expired,
        });

    test('an expired offer says so rather than showing as merely sent', () {
      // Expiry is not a stored status, so the chip has to derive it or the
      // reader sees a lapsed offer as one still awaiting an answer.
      expect(offer(expired: true).displayStatus, 'EXPIRED');
      expect(offer().displayStatus, OfferStatus.sent);
    });

    test('an expired offer is no longer pending', () {
      expect(offer().isPending, isTrue);
      expect(offer(expired: true).isPending, isFalse);
    });

    test('expiry only applies to an offer that actually went out', () {
      // A draft that happens to carry a past expiry date is not "expired" in
      // any sense the reader cares about.
      expect(offer(status: OfferStatus.draft, expired: true).displayStatus,
          OfferStatus.draft);
    });

    test('settled offers are the ones nobody is waiting on', () {
      expect(offer(status: OfferStatus.accepted).isSettled, isTrue);
      expect(offer(status: OfferStatus.declined).isSettled, isTrue);
      expect(offer(status: OfferStatus.withdrawn).isSettled, isTrue);
      expect(offer(status: OfferStatus.sent).isSettled, isFalse);
      expect(offer(status: OfferStatus.draft).isSettled, isFalse);
    });
  });
}
