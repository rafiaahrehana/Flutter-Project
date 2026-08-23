import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import 'attendance_models.dart';
import 'attendance_repository.dart';

@immutable
class AttendanceState {
  const AttendanceState({
    this.today,
    this.summary,
    this.history = const [],
    this.busy = false,
  });

  final AttendanceRecord? today;
  final MonthlySummary? summary;

  /// Recent days, one row per day. See [_consolidate].
  final List<AttendanceRecord> history;

  /// A check-in or check-out is in flight. Separate from the outer
  /// `AsyncValue` loading state so punching the clock does not blank the
  /// screen that shows what you are punching.
  final bool busy;

  bool get canCheckIn => today == null || !today!.isCheckedIn;
  bool get canCheckOut => today != null && today!.isCheckedIn && !today!.isCheckedOut;

  AttendanceState copyWith({
    AttendanceRecord? today,
    bool clearToday = false,
    MonthlySummary? summary,
    List<AttendanceRecord>? history,
    bool? busy,
  }) =>
      AttendanceState(
        today: clearToday ? null : (today ?? this.today),
        summary: summary ?? this.summary,
        history: history ?? this.history,
        busy: busy ?? this.busy,
      );
}

class AttendanceController extends AsyncNotifier<AttendanceState> {
  @override
  Future<AttendanceState> build() {
    // See LeaveController: bound to the signed-in user so a second sign-in on
    // the same device does not inherit the first person's attendance.
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<AttendanceState> _load() async {
    final repo = ref.read(attendanceRepositoryProvider);

    // Started together rather than awaited in sequence: three round trips at
    // 200ms each is most of a second of spinner on a phone connection.
    final todayCall = repo.myToday();
    final summaryCall = repo.myMonthlySummary();
    final historyCall = repo.myRecords(size: 30);

    return AttendanceState(
      today: await todayCall,
      summary: await summaryCall,
      history: _consolidate((await historyCall).content),
    );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  Future<void> checkIn({String? notes, String? location}) =>
      _punch((repo) => repo.checkIn(notes: notes, location: location));

  Future<void> checkOut({String? location}) {
    final record = state.value?.today;
    if (record == null) {
      throw StateError('Cannot check out before checking in');
    }
    return _punch((repo) => repo.checkOut(record.id, location: location));
  }

  /// Runs a punch, then re-reads the day and the month.
  ///
  /// The server owns lateness, overtime and the day's status — it decides them
  /// from the shift, not from what the phone sent — so the returned record is
  /// used as-is and the summary is refetched rather than adjusted locally.
  Future<void> _punch(
    Future<AttendanceRecord> Function(AttendanceRepository) action,
  ) async {
    final current = state.value ?? const AttendanceState();
    state = AsyncValue.data(current.copyWith(busy: true));

    final repo = ref.read(attendanceRepositoryProvider);
    try {
      final record = await action(repo);
      final summaryCall = repo.myMonthlySummary();
      final historyCall = repo.myRecords(size: 30);
      state = AsyncValue.data(
        AttendanceState(
          today: record,
          summary: await summaryCall,
          history: _consolidate((await historyCall).content),
        ),
      );
    } catch (_) {
      // Drop the busy flag and leave the previous data on screen; the caller
      // shows the message. Replacing the state with an error here would clear
      // a perfectly good record because one write failed.
      state = AsyncValue.data(current.copyWith(busy: false));
      rethrow;
    }
  }

  /// One row per day.
  ///
  /// A single day can arrive as several rows: the nightly scheduler writes an
  /// ABSENT placeholder, and a later punch adds its own. Rendered raw, the
  /// history shows the same date twice with contradictory statuses, so the
  /// rows for a day are folded together — real punches beating the
  /// placeholder, and lateness surviving from whichever row carried it.
  static List<AttendanceRecord> _consolidate(List<AttendanceRecord> records) {
    final byDay = <String, AttendanceRecord>{};
    for (final record in records) {
      final key = '${record.employeeId}_${record.attendanceDate}';
      final existing = byDay[key];
      byDay[key] = existing == null ? record : existing.mergedWith(record);
    }
    final merged = byDay.values.toList()
      ..sort((a, b) => b.attendanceDate.compareTo(a.attendanceDate));
    return merged;
  }
}

final attendanceControllerProvider =
    AsyncNotifierProvider<AttendanceController, AttendanceState>(
  AttendanceController.new,
);
