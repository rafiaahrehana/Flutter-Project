import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../profile/employee_repository.dart';

/// A company announcement, from GET /api/announcements/active.
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.priority = 0,
    this.publishedAt,
    this.createdAt,
    this.createdByName,
  });

  final int id;
  final String title;
  final String body;
  final int priority;
  final String? publishedAt;
  final String? createdAt;
  final String? createdByName;

  /// Published date if it has one, falling back to when it was written.
  String? get shownAt => publishedAt ?? createdAt;

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        priority: (json['priority'] as num?)?.toInt() ?? 0,
        publishedAt: json['publishedAt'] as String?,
        createdAt: json['createdAt'] as String?,
        createdByName: json['createdByName'] as String?,
      );
}

class Holiday {
  const Holiday({
    required this.id,
    required this.name,
    required this.holidayDate,
    this.holidayType,
  });

  final int id;
  final String name;
  final String holidayDate;
  final String? holidayType;

  /// Whole days from today. Negative once the date has passed.
  int get daysAway {
    final date = DateTime.tryParse(holidayDate);
    if (date == null) return 0;
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    return DateTime(date.year, date.month, date.day).difference(midnight).inDays;
  }

  String get countdownLabel => switch (daysAway) {
        0 => 'Today',
        1 => 'Tomorrow',
        final d when d < 0 => 'Passed',
        final d => 'in $d days',
      };

  factory Holiday.fromJson(Map<String, dynamic> json) => Holiday(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        holidayDate: json['holidayDate'] as String? ?? '',
        holidayType: json['holidayType'] as String?,
      );
}

/// The notice board and the two extra dashboard figures.
///
/// Every call here is optional. An employee without ANNOUNCEMENT_VIEW, or a
/// company that has not configured holidays, gets a 403 or an empty list — and
/// the right response to that is a shorter dashboard, not an error screen. So
/// each fetch swallows its own failure and returns nothing.
class HomeRepository {
  HomeRepository(this._api);

  final ApiClient _api;

  Future<List<Announcement>> activeAnnouncements() =>
      _optionalList('/announcements/active', Announcement.fromJson);

  Future<List<Holiday>> currentYearHolidays() =>
      _optionalList('/hr/holidays/current-year', Holiday.fromJson);

  /// Service requests assigned to this employee that are still open.
  Future<int?> openRequestCount() async {
    try {
      final json = await _api.get<dynamic>(
        '/service-requests/assigned-to-me',
        query: {'page': 0, 'size': 50},
      );
      final content = json is Map ? json['content'] : json;
      if (content is! List) return null;
      const closed = {'COMPLETED', 'CANCELLED', 'REJECTED'};
      return content
          .whereType<Map<String, dynamic>>()
          .where((r) => !closed.contains(r['status'] as String? ?? ''))
          .length;
    } on ApiException {
      return null;
    }
  }

  /// The score on this employee's most recent performance review.
  Future<double?> latestReviewScore(int employeeId) async {
    try {
      final json = await _api.get<dynamic>(
        '/hr/performance/employee/$employeeId',
        query: {'page': 0, 'size': 1},
      );
      final content = json is Map ? json['content'] : json;
      if (content is! List || content.isEmpty) return null;
      final first = content.first;
      if (first is! Map) return null;
      return (first['overallScore'] as num?)?.toDouble();
    } on ApiException {
      return null;
    }
  }

  Future<List<T>> _optionalList<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final list = await _api.get<List<dynamic>>(path);
      return list.whereType<Map<String, dynamic>>().map(fromJson).toList();
    } on ApiException {
      return const [];
    }
  }
}

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(ref.watch(apiClientProvider)),
);

@immutable
class NoticeBoard {
  const NoticeBoard({
    this.announcements = const [],
    this.holidays = const [],
    this.openRequests,
  });

  final List<Announcement> announcements;

  /// Upcoming only, soonest first.
  final List<Holiday> holidays;

  /// Null means "could not be determined", which renders as a dash. Zero is a
  /// real answer and renders as zero.
  final int? openRequests;
}

/// Kept separate from [noticeBoardProvider] because it is keyed on the
/// employee id, so it can only run once the employee record has arrived.
final latestReviewScoreProvider = FutureProvider<double?>((ref) async {
  final employee = await ref.watch(myEmployeeProvider.future);
  if (employee == null) return null;
  return ref.watch(homeRepositoryProvider).latestReviewScore(employee.id);
});

final noticeBoardProvider = FutureProvider<NoticeBoard>((ref) async {
  final repo = ref.watch(homeRepositoryProvider);

  final announcementsCall = repo.activeAnnouncements();
  final holidaysCall = repo.currentYearHolidays();
  final requestsCall = repo.openRequestCount();

  final announcements = await announcementsCall;
  final holidays = await holidaysCall;

  final upcoming = holidays.where((h) => h.daysAway >= 0).toList()
    ..sort((a, b) => a.daysAway.compareTo(b.daysAway));

  final sorted = [...announcements]..sort((a, b) {
      // Higher priority first, then most recent.
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      return (b.shownAt ?? '').compareTo(a.shownAt ?? '');
    });

  return NoticeBoard(
    announcements: sorted,
    holidays: upcoming,
    openRequests: await requestsCall,
  );
});
