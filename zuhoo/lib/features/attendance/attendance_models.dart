/// Statuses the backend can put on a day. Kept as plain strings rather than a
/// Dart enum because the source of truth is the Java enum — a value that
/// arrives here and is not in this list must still render, not crash.
abstract final class AttendanceStatus {
  static const present = 'PRESENT';
  static const late = 'LATE';
  static const absent = 'ABSENT';
  static const onLeave = 'ON_LEAVE';
  static const halfDay = 'HALF_DAY';
  static const workFromHome = 'WORK_FROM_HOME';
  static const weekend = 'WEEKEND';
  static const holiday = 'HOLIDAY';
  static const partialDay = 'PARTIAL_DAY';
  static const unmarked = 'UNMARKED';
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.attendanceDate,
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.checkInLocation,
    this.checkOutLocation,
    this.shiftType,
    this.isLate = false,
    this.lateMinutes = 0,
    this.isOvertime = false,
    this.overtimeHours,
    this.leftEarly = false,
    this.earlyMinutes,
    this.totalWorkingHours,
    this.approved = false,
    this.notes,
  });

  final int id;
  final int employeeId;
  final String employeeName;
  final String attendanceDate;
  final String status;

  /// `HH:mm:ss` wall clock, not an instant.
  final String? checkInTime;
  final String? checkOutTime;

  final String? checkInLocation;
  final String? checkOutLocation;
  final String? shiftType;
  final bool isLate;
  final int lateMinutes;
  final bool isOvertime;
  final double? overtimeHours;
  final bool leftEarly;
  final int? earlyMinutes;
  final double? totalWorkingHours;
  final bool approved;
  final String? notes;

  bool get isCheckedIn => checkInTime != null && checkInTime!.isNotEmpty;
  bool get isCheckedOut => checkOutTime != null && checkOutTime!.isNotEmpty;

  /// True once the day is finished — both stamps present, nothing left to do.
  bool get isComplete => isCheckedIn && isCheckedOut;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      AttendanceRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        employeeId: (json['employeeId'] as num?)?.toInt() ?? 0,
        employeeName: json['employeeName'] as String? ?? '',
        attendanceDate: json['attendanceDate'] as String? ?? '',
        status: json['status'] as String? ?? AttendanceStatus.unmarked,
        checkInTime: json['checkInTime'] as String?,
        checkOutTime: json['checkOutTime'] as String?,
        checkInLocation: json['checkInLocation'] as String?,
        checkOutLocation: json['checkOutLocation'] as String?,
        shiftType: json['shiftType'] as String?,
        isLate: json['isLate'] as bool? ?? false,
        lateMinutes: (json['lateMinutes'] as num?)?.toInt() ?? 0,
        isOvertime: json['isOvertime'] as bool? ?? false,
        overtimeHours: (json['overtimeHours'] as num?)?.toDouble(),
        leftEarly: json['leftEarly'] as bool? ?? false,
        earlyMinutes: (json['earlyMinutes'] as num?)?.toInt(),
        totalWorkingHours: (json['totalWorkingHours'] as num?)?.toDouble(),
        approved: json['approved'] as bool? ?? false,
        notes: json['notes'] as String?,
      );

  AttendanceRecord mergedWith(AttendanceRecord other) => AttendanceRecord(
        id: id,
        employeeId: employeeId,
        employeeName: employeeName,
        attendanceDate: attendanceDate,
        // An ABSENT row that also has a real punch is the scheduler's
        // placeholder being superseded, so the real status wins.
        status: status == AttendanceStatus.absent &&
                other.status != AttendanceStatus.absent
            ? other.status
            : status,
        checkInTime: checkInTime ?? other.checkInTime,
        checkOutTime: checkOutTime ?? other.checkOutTime,
        checkInLocation: checkInLocation ?? other.checkInLocation,
        checkOutLocation: checkOutLocation ?? other.checkOutLocation,
        shiftType: shiftType ?? other.shiftType,
        isLate: isLate || other.isLate,
        lateMinutes: other.isLate ? other.lateMinutes : lateMinutes,
        isOvertime: isOvertime || other.isOvertime,
        overtimeHours: overtimeHours ?? other.overtimeHours,
        leftEarly: leftEarly || other.leftEarly,
        earlyMinutes: earlyMinutes ?? other.earlyMinutes,
        totalWorkingHours: totalWorkingHours ?? other.totalWorkingHours,
        approved: approved || other.approved,
        notes: notes ?? other.notes,
      );
}

class MonthlySummary {
  const MonthlySummary({
    required this.year,
    required this.month,
    this.presentDays = 0,
    this.absentDays = 0,
    this.halfDays = 0,
    this.onLeaveDays = 0,
    this.holidayDays = 0,
    this.weekOffDays = 0,
    this.workedHours = 0,
  });

  final int year;
  final int month;
  final int presentDays;
  final int absentDays;
  final int halfDays;
  final int onLeaveDays;
  final int holidayDays;
  final int weekOffDays;
  final double workedHours;

  /// Share of recorded working days attended, or null when the month has no
  /// recorded working days yet.
  ///
  /// Null rather than 0 on purpose: a fresh month with nothing in it is not
  /// 0% attendance, and showing that figure to someone would be a small lie
  /// about their record. The UI renders a dash instead.
  double? get attendancePercent {
    final attended = presentDays + halfDays;
    final working = attended + absentDays + onLeaveDays;
    if (working == 0) return null;
    return (attended / working * 1000).round() / 10;
  }

  factory MonthlySummary.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return MonthlySummary(
      year: (json['year'] as num?)?.toInt() ?? now.year,
      month: (json['month'] as num?)?.toInt() ?? now.month,
      presentDays: (json['presentDays'] as num?)?.toInt() ?? 0,
      absentDays: (json['absentDays'] as num?)?.toInt() ?? 0,
      halfDays: (json['halfDays'] as num?)?.toInt() ?? 0,
      onLeaveDays: (json['onLeaveDays'] as num?)?.toInt() ?? 0,
      holidayDays: (json['holidayDays'] as num?)?.toInt() ?? 0,
      weekOffDays: (json['weekOffDays'] as num?)?.toInt() ?? 0,
      workedHours: (json['workedHours'] as num?)?.toDouble() ?? 0,
    );
  }
}
