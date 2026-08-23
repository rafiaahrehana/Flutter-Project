import 'package:intl/intl.dart';

/// Display formatting for the shapes the backend actually sends.
///
/// Dates arrive as `yyyy-MM-dd`, times as `HH:mm:ss`, and timestamps as ISO
/// strings — all as plain strings, never as numbers. Every helper here takes
/// the raw string and returns something safe to drop straight into a widget,
/// including when the value is null or malformed, because a list screen must
/// not blow up over one bad row.
class Fmt {
  Fmt._();

  static final _date = DateFormat('d MMM yyyy');
  static final _dateShort = DateFormat('d MMM');
  static final _dayDate = DateFormat('EEE, d MMM');
  static final _monthYear = DateFormat('MMMM yyyy');
  static final _time = DateFormat('h:mm a');
  static final _money = NumberFormat.currency(symbol: '\u09F3 ', decimalDigits: 2);

  /// Em dash: a placeholder that reads as "no value", where 0 or an empty
  /// string would read as a real measurement.
  static const dash = '\u2014';

  static DateTime? parse(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static String date(String? value) {
    final parsed = parse(value);
    return parsed == null ? dash : _date.format(parsed);
  }

  static String dateShort(String? value) {
    final parsed = parse(value);
    return parsed == null ? dash : _dateShort.format(parsed);
  }

  static String dayDate(String? value) {
    final parsed = parse(value);
    return parsed == null ? dash : _dayDate.format(parsed);
  }

  /// An ISO timestamp as date and time together — for records where
  /// "when exactly" is the point, such as an audit trail.
  static String dateTime(String? value) {
    final parsed = parse(value);
    return parsed == null
        ? dash
        : '${_date.format(parsed)}, ${_time.format(parsed)}';
  }

  /// Just the time from an ISO timestamp.
  static String time(String? value) {
    final parsed = parse(value);
    return parsed == null ? dash : _time.format(parsed);
  }

  static String monthYear(int month, int year) =>
      _monthYear.format(DateTime(year, month));

  static String monthName(int month) =>
      DateFormat('MMMM').format(DateTime(2000, month));

  /// `HH:mm:ss` from the attendance endpoints, shown as `9:05 AM`.
  static String clock(String? value) {
    if (value == null || value.isEmpty) return dash;
    final parts = value.split(':');
    if (parts.length < 2) return dash;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return dash;
    return _time.format(DateTime(2000, 1, 1, hour, minute));
  }

  /// The wall-clock string the check-in endpoint expects. Local time, not UTC
  /// and not an instant: the backend compares it against the shift's start
  /// time, which is also a local wall clock.
  static String wallClockNow([DateTime? now]) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// `yyyy-MM-dd`, the shape every date parameter and payload uses.
  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String money(num? value) => value == null ? dash : _money.format(value);

  static String hours(num? value) =>
      value == null ? dash : '${_trim(value)}h';

  /// "45 min" under an hour, "1h 15m" over it.
  static String minutes(num? value) {
    final total = (value ?? 0).round();
    if (total <= 0) return '';
    if (total < 60) return '$total min';
    final h = total ~/ 60;
    final m = total % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// "2 days ago" / "in 3 days", for notification lists and holiday counts.
  static String relative(String? value) {
    final parsed = parse(value);
    if (parsed == null) return dash;
    final diff = DateTime.now().difference(parsed);
    final days = diff.inDays;
    if (days.abs() >= 7) return _date.format(parsed);
    if (days > 0) return days == 1 ? 'Yesterday' : '$days days ago';
    if (days < 0) return days == -1 ? 'Tomorrow' : 'in ${-days} days';
    final hrs = diff.inHours;
    if (hrs > 0) return '${hrs}h ago';
    final mins = diff.inMinutes;
    if (mins > 0) return '${mins}m ago';
    return 'Just now';
  }

  /// Turns a backend SCREAMING_SNAKE enum into "Screaming Snake".
  static String label(String? value) {
    if (value == null || value.isEmpty) return dash;
    return value
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  static String _trim(num value) {
    final asDouble = value.toDouble();
    if (asDouble == asDouble.roundToDouble()) return asDouble.round().toString();
    return asDouble.toStringAsFixed(2);
  }
}
