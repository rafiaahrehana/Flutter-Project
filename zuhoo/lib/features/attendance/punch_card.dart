import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'attendance_controller.dart';
import 'attendance_models.dart';

/// Today's clock: the state of the day plus the one action available on it.
///
/// Shared by the dashboard and the attendance tab, because both need to show
/// the same thing and there is no version of this that should differ between
/// the two.
class PunchCard extends ConsumerWidget {
  const PunchCard({super.key, this.compact = false});

  /// The dashboard shows a tighter version with no history hint.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(attendanceControllerProvider);

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: async.when(
        loading: () => const Loader(padding: 20),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load today’s attendance.',
          onRetry: () => ref.read(attendanceControllerProvider.notifier).refresh(),
        ),
        data: (state) => _Body(state: state, compact: compact),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.compact});

  final AttendanceState state;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final today = state.today;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.dayDate(Fmt.isoDate(DateTime.now())),
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statusLine(today),
                    style: TextStyle(color: bos.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (today != null) StatusChip(today.status),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _Stamp(
                label: 'Checked in',
                time: today?.checkInTime,
                icon: Icons.login_rounded,
                tone: bos.success,
              ),
            ),
            Container(width: 1, height: 34, color: bos.borderLight),
            Expanded(
              child: _Stamp(
                label: 'Checked out',
                time: today?.checkOutTime,
                icon: Icons.logout_rounded,
                tone: bos.info,
              ),
            ),
          ],
        ),
        if (today != null && today.isLate && today.lateMinutes > 0) ...[
          const SizedBox(height: 12),
          MessageBanner.info('Marked late by ${Fmt.minutes(today.lateMinutes)}.'),
        ],
        const SizedBox(height: 16),
        _Action(state: state),
        if (!compact && today != null && today.isComplete) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Worked ${Fmt.hours(today.totalWorkingHours)} today',
              style: TextStyle(color: bos.muted, fontSize: 12.5),
            ),
          ),
        ],
      ],
    );
  }

  static String _statusLine(AttendanceRecord? today) {
    if (today == null) return 'You have not checked in yet.';
    if (today.isComplete) return 'Your day is recorded.';
    if (today.isCheckedIn) return 'You are checked in.';
    return 'You have not checked in yet.';
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.label,
    required this.time,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String? time;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final has = time != null && time!.isNotEmpty;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: has ? tone : bos.muted),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: bos.muted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          has ? Fmt.clock(time) : Fmt.dash,
          style: TextStyle(
            color: has ? bos.text : bos.muted,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Action extends ConsumerWidget {
  const _Action({required this.state});

  final AttendanceState state;

  Future<void> _punch(BuildContext context, WidgetRef ref, bool checkingIn) async {
    final controller = ref.read(attendanceControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (checkingIn) {
        await controller.checkIn();
      } else {
        await controller.checkOut();
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(checkingIn ? 'Checked in.' : 'Checked out.'),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(checkingIn ? 'Check-in failed.' : 'Check-out failed.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    if (state.canCheckIn) {
      return LoadingButton(
        label: 'Check in',
        loading: state.busy,
        icon: Icons.login_rounded,
        onPressed: () => _punch(context, ref, true),
      );
    }

    if (state.canCheckOut) {
      return LoadingButton(
        label: 'Check out',
        loading: state.busy,
        icon: Icons.logout_rounded,
        onPressed: () => _punch(context, ref, false),
      );
    }

    // Both stamps present. Nothing left to do today, and a disabled button
    // would only invite tapping — say what happened instead.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bos.successSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: bos.success),
          const SizedBox(width: 8),
          Text(
            'All done for today',
            style: TextStyle(
              color: bos.success,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
