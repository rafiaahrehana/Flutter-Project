import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import '../core/auth/auth_models.dart';
import '../core/auth/impersonation_controller.dart';
import '../core/theme/bos_tokens.dart';

/// Wraps the whole app and pins a bar to the top while a session is running.
///
/// App-wide rather than per-screen on purpose. The one thing that must never
/// happen is a member of staff forgetting which account they are in and typing
/// into a customer's live data believing it is a test tenant — so the reminder
/// has to survive navigation, deep links and every tab, which means living
/// above the router rather than inside any screen it renders.
class ImpersonationScope extends ConsumerWidget {
  const ImpersonationScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(impersonationControllerProvider);
    if (session == null) return child;

    return Material(
      color: Theme.of(context).bos.bgPage,
      child: Column(
        children: [
          _Banner(session: session),
          Expanded(
            // The bar has taken the status-bar inset; without this the Scaffold
            // below would inset for it a second time and leave a dead strip.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends ConsumerStatefulWidget {
  const _Banner({required this.session});

  final ImpersonationSession session;

  @override
  ConsumerState<_Banner> createState() => _BannerState();
}

class _BannerState extends ConsumerState<_Banner> {
  Timer? _ticker;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    // Redraws the countdown. The session's actual expiry is the controller's
    // job — this only has to keep the number honest.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _end() async {
    if (_ending) return;
    setState(() => _ending = true);
    final messenger = ScaffoldMessenger.of(context);
    final companyName = widget.session.companyName;
    try {
      await ref.read(authControllerProvider.notifier).endImpersonation();
      messenger.showSnackBar(
        SnackBar(content: Text('Left $companyName. You are yourself again.')),
      );
    } finally {
      // This widget is normally gone by now — the session it draws has ended.
      if (mounted) setState(() => _ending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final session = widget.session;

    // The amber is near-black in light mode and near-yellow in dark, so the
    // text colour is derived rather than picked — one of them would be
    // unreadable against a fixed choice.
    final background = bos.warning;
    final foreground = background.computeLuminance() > 0.5
        ? Colors.black.withValues(alpha: 0.87)
        : Colors.white;

    final expiringSoon = session.remaining.inMinutes < 2;

    return Container(
      width: double.infinity,
      color: background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
          child: Row(
            children: [
              Icon(Icons.visibility_rounded, size: 17, color: foreground),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Viewing as ${session.companyName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      // Names the real person, because the rest of the app is
                      // busy insisting they are somebody else.
                      'Platform session · ${session.adminEmail} · '
                      'ends in ${session.remainingLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground.withValues(
                          alpha: expiringSoon ? 1 : 0.82,
                        ),
                        fontSize: 11,
                        fontWeight:
                            expiringSoon ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (_ending)
                SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else
                TextButton(
                  onPressed: _end,
                  style: TextButton.styleFrom(
                    foregroundColor: foreground,
                    backgroundColor: foreground.withValues(alpha: 0.16),
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Leave'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
