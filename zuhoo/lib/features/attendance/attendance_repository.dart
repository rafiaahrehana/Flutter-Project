import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/util/formatters.dart';
import 'attendance_models.dart';

class AttendanceRepository {
  AttendanceRepository(this._api);

  final ApiClient _api;

  static const _base = '/company/attendance';

  /// Today's record, or null when the day has not been opened yet.
  ///
  /// "Nothing yet" is the normal morning state for every employee who has not
  /// punched in, and the backend expresses it as `ResponseEntity.ok(null)` —
  /// a **200 with an empty body**, not a 404. Depending on the transformer
  /// that reaches Dio as either a null or an empty string, so both are read as
  /// "no record" rather than being allowed to fail a cast and surface as a
  /// mystery error on the check-in screen every morning.
  ///
  /// The status codes are still caught underneath, because the same endpoint
  /// 403s for a user with no employee record — also not an error worth showing.
  /// A genuine network failure still propagates: that is a different thing and
  /// the user should see it.
  Future<AttendanceRecord?> myToday() async {
    try {
      final data = await _api.get<dynamic>('$_base/my/today');
      if (data is! Map<String, dynamic> || data.isEmpty) return null;
      return AttendanceRecord.fromJson(data);
    } on ApiException catch (e) {
      if (e.isNotFound || e.isForbidden || e.statusCode == 204) return null;
      rethrow;
    }
  }

  Future<PagedResponse<AttendanceRecord>> myRecords({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_base/my',
        AttendanceRecord.fromJson,
        page: page,
        size: size,
      );

  Future<MonthlySummary> myMonthlySummary({int? year, int? month}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '$_base/my/monthly-summary',
      query: {'year': year, 'month': month},
    );
    return MonthlySummary.fromJson(json);
  }

  /// Opens today.
  ///
  /// `checkInTime` is the **local wall clock**, formatted `HH:mm:ss` — not an
  /// ISO instant and not UTC. The backend compares it against the assigned
  /// shift's start time, which is itself a local wall clock, so sending an
  /// instant would make everyone in a non-UTC timezone permanently late.
  Future<AttendanceRecord> checkIn({String? notes, String? location}) async {
    final json = await _api.post<Map<String, dynamic>>('$_base/check-in', {
      'checkInTime': Fmt.wallClockNow(),
      'method': 'MANUAL',
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (location != null && location.trim().isNotEmpty)
        'location': location.trim(),
    });
    return AttendanceRecord.fromJson(json);
  }

  Future<AttendanceRecord> checkOut(int id, {String? location}) async {
    final json = await _api.post<Map<String, dynamic>>('$_base/$id/check-out', {
      'checkOutTime': Fmt.wallClockNow(),
      'method': 'MANUAL',
      if (location != null && location.trim().isNotEmpty)
        'location': location.trim(),
    });
    return AttendanceRecord.fromJson(json);
  }
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(apiClientProvider)),
);
