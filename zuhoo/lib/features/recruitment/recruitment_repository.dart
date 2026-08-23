import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/paged_controller.dart';
import 'recruitment_models.dart';

/// Hiring: postings, the applications against them, and the interviews and
/// offers that follow.
///
/// Deliberately absent:
///
/// * **Hiring an applicant.** `POST /applications/{id}/hire` provisions a user
///   account and its body carries a plaintext `password` alongside department,
///   designation, manager, shift and start date. That is an onboarding form,
///   not a one-handed action, and it is gated on EMPLOYEE_CREATE rather than
///   APPLICATION_UPDATE — a different entitlement from everything else here.
/// * **Writing an offer.** Composing one means a full salary breakdown
///   (gross, basic, house rent, medical, transport). Recording what happened
///   to an offer — sent, accepted, declined, withdrawn — is here, because that
///   is the part that happens while somebody is on the phone.
/// * **The careers page and recruitment reports**, which are a CMS editor and
///   a wide table respectively.
class RecruitmentRepository {
  RecruitmentRepository(this._api);

  final ApiClient _api;

  static const _jobs = '/recruitment/jobs';
  static const _base = '/recruitment';
  static const _interviews = '/recruitment/interviews';
  static const _offers = '/recruitment/offers';

  // ── Postings ────────────────────────────────────────────────

  Future<PagedResponse<JobPosting>> jobs({int page = 0, int size = 20}) =>
      _api.getPaged(_jobs, JobPosting.fromJson, page: page, size: size);

  Future<JobPosting> publishJob(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('$_jobs/$id/publish');
    return JobPosting.fromJson(json);
  }

  Future<JobPosting> closeJob(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('$_jobs/$id/close');
    return JobPosting.fromJson(json);
  }

  // ── Applications ────────────────────────────────────────────

  Future<PagedResponse<JobApplication>> applications({
    String? status,
    int? jobPostingId,
    int page = 0,
    int size = 20,
  }) {
    // Two different endpoints rather than one with a filter: applications for
    // a posting live under the posting.
    final path = jobPostingId == null
        ? '$_base/applications'
        : '$_jobs/$jobPostingId/applications';
    return _api.getPaged(
      path,
      JobApplication.fromJson,
      page: page,
      size: size,
      query: {'status': status},
    );
  }

  Future<JobApplication> application(int id) async {
    final json =
        await _api.get<Map<String, dynamic>>('$_base/applications/$id');
    return JobApplication.fromJson(json);
  }

  Future<JobApplication> setApplicationStatus(int id, String status) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_base/applications/$id/status',
      {'status': status},
    );
    return JobApplication.fromJson(json);
  }

  /// Scores an applicant out of whatever scale the team uses; the backend
  /// averages whichever are present into `overallScore`.
  Future<JobApplication> evaluate(
    int id, {
    int? education,
    int? experience,
    int? technicalSkills,
    int? interview,
    int? communication,
  }) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_base/applications/$id/evaluate',
      {
        'scoreEducation': ?education,
        'scoreExperience': ?experience,
        'scoreTechnicalSkills': ?technicalSkills,
        'scoreInterview': ?interview,
        'scoreCommunication': ?communication,
      },
    );
    return JobApplication.fromJson(json);
  }

  // ── Interviews ──────────────────────────────────────────────

  /// Passing a status is not only a filter: the repository sorts **ascending**
  /// when one is given and descending when it is not. So the scheduled list
  /// arrives soonest-first, which is what an upcoming list wants, and the
  /// unfiltered list arrives newest-first, which is what a history wants.
  Future<PagedResponse<Interview>> interviews({
    String? status,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _interviews,
        Interview.fromJson,
        page: page,
        size: size,
        query: {'status': status},
      );

  Future<List<Interview>> interviewsForApplication(int applicationId) async {
    final list = await _api.get<List<dynamic>>(
      '$_interviews/application/$applicationId',
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(Interview.fromJson)
        .toList(growable: false);
  }

  Future<Interview> submitFeedback(
    int id, {
    int? rating,
    String? strengths,
    String? concerns,
    String? recommendation,
    bool noShow = false,
  }) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_interviews/$id/feedback',
      {
        'rating': ?rating,
        if (strengths != null && strengths.trim().isNotEmpty)
          'strengths': strengths.trim(),
        if (concerns != null && concerns.trim().isNotEmpty)
          'concerns': concerns.trim(),
        'recommendation': ?recommendation,
        'noShow': noShow,
      },
    );
    return Interview.fromJson(json);
  }

  Future<Interview> cancelInterview(int id) async {
    final json =
        await _api.patch<Map<String, dynamic>>('$_interviews/$id/cancel');
    return Interview.fromJson(json);
  }

  // ── Offers ──────────────────────────────────────────────────

  Future<List<JobOffer>> offersForApplication(int applicationId) async {
    final list = await _api.get<List<dynamic>>(
      '$_offers/application/$applicationId',
    );
    return list
        .whereType<Map<String, dynamic>>()
        .map(JobOffer.fromJson)
        .toList(growable: false);
  }

  Future<JobOffer> offerTransition(int id, String action, {String? reason}) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_offers/$id/$action',
      {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
    );
    return JobOffer.fromJson(json);
  }
}

final recruitmentRepositoryProvider = Provider<RecruitmentRepository>(
  (ref) => RecruitmentRepository(ref.watch(apiClientProvider)),
);

class JobsController extends AsyncNotifier<PagedState<JobPosting>>
    with PagedLoader<JobPosting> {
  @override
  Future<PagedState<JobPosting>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<JobPosting>> fetchPage(int page) =>
      ref.read(recruitmentRepositoryProvider).jobs(page: page);

  void apply(JobPosting updated) =>
      replaceItem((job) => job.id == updated.id, updated);
}

final jobsProvider =
    AsyncNotifierProvider<JobsController, PagedState<JobPosting>>(
  JobsController.new,
);

/// Which pipeline stage the applications list is narrowed to. Null is all.
class ApplicationFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) {
    if (state == status) return;
    state = status;
  }
}

final applicationFilterProvider =
    NotifierProvider<ApplicationFilterController, String?>(
  ApplicationFilterController.new,
);

class ApplicationsController extends AsyncNotifier<PagedState<JobApplication>>
    with PagedLoader<JobApplication> {
  @override
  Future<PagedState<JobApplication>> build() {
    ref.watch(currentUserProvider);
    ref.watch(applicationFilterProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<JobApplication>> fetchPage(int page) =>
      ref.read(recruitmentRepositoryProvider).applications(
            status: ref.read(applicationFilterProvider),
            page: page,
          );

  void apply(JobApplication updated) {
    final filter = ref.read(applicationFilterProvider);
    // A status change can move the row out of the stage being viewed.
    if (filter != null && updated.status != filter) {
      removeItem((application) => application.id == updated.id);
    } else {
      replaceItem((application) => application.id == updated.id, updated);
    }
  }
}

final applicationsProvider =
    AsyncNotifierProvider<ApplicationsController, PagedState<JobApplication>>(
  ApplicationsController.new,
);

/// Interviews still to happen, soonest first.
class UpcomingInterviewsController extends AsyncNotifier<PagedState<Interview>>
    with PagedLoader<Interview> {
  @override
  Future<PagedState<Interview>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Interview>> fetchPage(int page) =>
      ref.read(recruitmentRepositoryProvider).interviews(
            status: InterviewStatus.scheduled,
            page: page,
          );

  void apply(Interview updated) {
    // Feedback and cancellation both move an interview out of SCHEDULED, so
    // it leaves this list rather than sitting in it with the wrong state.
    if (updated.status != InterviewStatus.scheduled) {
      removeItem((interview) => interview.id == updated.id);
    } else {
      replaceItem((interview) => interview.id == updated.id, updated);
    }
  }
}

final upcomingInterviewsProvider =
    AsyncNotifierProvider<UpcomingInterviewsController, PagedState<Interview>>(
  UpcomingInterviewsController.new,
);

final applicationInterviewsProvider =
    FutureProvider.autoDispose.family<List<Interview>, int>(
  (ref, applicationId) => ref
      .read(recruitmentRepositoryProvider)
      .interviewsForApplication(applicationId),
);

final applicationOffersProvider =
    FutureProvider.autoDispose.family<List<JobOffer>, int>(
  (ref, applicationId) =>
      ref.read(recruitmentRepositoryProvider).offersForApplication(applicationId),
);
