import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'attendance_controller.dart';
import 'attendance_models.dart';
import 'punch_card.dart';

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(attendanceControllerProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Attendance')),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () =>
            ref.read(attendanceControllerProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const PunchCard(),
            const SizedBox(height: 22),
            if (async.value?.summary != null) ...[
              const SectionHeader('This month',
                  icon: Icons.calendar_month_rounded),
              _MonthSummary(summary: async.value!.summary!),
              const SizedBox(height: 22),
            ],
            const SectionHeader('Recent days', icon: Icons.history_rounded),
            _History(async: async),
          ],
        ),
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.summary});

  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final percent = summary.attendancePercent;

    final rows = <({String label, String value, Color color})>[
      (label: 'Present', value: '${summary.presentDays}', color: bos.success),
      (label: 'Absent', value: '${summary.absentDays}', color: bos.danger),
      (label: 'Half days', value: '${summary.halfDays}', color: bos.warning),
      (label: 'On leave', value: '${summary.onLeaveDays}', color: bos.info),
      (label: 'Holidays', value: '${summary.holidayDays}', color: bos.brandInk),
      (label: 'Week offs', value: '${summary.weekOffDays}', color: bos.muted),
    ];

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Fmt.monthYear(summary.month, summary.year),
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Fmt.hours(summary.workedHours)} worked',
                      style: TextStyle(color: bos.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    percent == null
                        ? Fmt.dash
                        : '${percent.toStringAsFixed(percent % 1 == 0 ? 0 : 1)}%',
                    style: TextStyle(
                      color: percent == null ? bos.muted : bos.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'attendance',
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: bos.borderLight),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 12,
            children: [
              for (final row in rows)
                SizedBox(
                  width: (MediaQuery.sizeOf(context).width - 32 - 32 - 20) / 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.value,
                        style: TextStyle(
                          color: row.color,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        row.label,
                        style: TextStyle(color: bos.muted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.async});

  final AsyncValue<AttendanceState> async;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    return async.when(
      loading: () => const Loader(),
      error: (error, _) => ErrorState(
        message: error is ApiException
            ? error.message
            : 'Could not load your attendance history.',
        onRetry: () => ref.read(attendanceControllerProvider.notifier).refresh(),
      ),
      data: (state) {
        if (state.history.isEmpty) {
          return const EmptyState(
            icon: Icons.event_busy_rounded,
            title: 'No attendance yet',
            message: 'Days appear here once you start checking in.',
          );
        }
        return AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < state.history.length; i++) ...[
                if (i > 0) Divider(height: 1, color: bos.borderLight),
                _HistoryRow(record: state.history[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Fmt.dayDate(record.attendanceDate),
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.login_rounded, size: 12, color: bos.muted),
                    const SizedBox(width: 4),
                    Text(
                      Fmt.clock(record.checkInTime),
                      style: TextStyle(color: bos.muted, fontSize: 12),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.logout_rounded, size: 12, color: bos.muted),
                    const SizedBox(width: 4),
                    Text(
                      Fmt.clock(record.checkOutTime),
                      style: TextStyle(color: bos.muted, fontSize: 12),
                    ),
                    if (record.isLate && record.lateMinutes > 0) ...[
                      const SizedBox(width: 10),
                      Text(
                        '${Fmt.minutes(record.lateMinutes)} late',
                        style: TextStyle(
                          color: bos.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusChip(record.status, dense: true),
              if (record.totalWorkingHours != null) ...[
                const SizedBox(height: 4),
                Text(
                  Fmt.hours(record.totalWorkingHours),
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
