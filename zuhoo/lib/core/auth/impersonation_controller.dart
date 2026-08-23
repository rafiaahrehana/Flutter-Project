import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'auth_models.dart';

/// The impersonation session that is running, if one is.
///
/// Separate from [AuthController] because the two answer different questions.
/// `AuthController` says who the app is acting as — during impersonation that
/// is the tenant, and every screen should treat it as such. This says that the
/// identity is borrowed, which is what the banner draws and what the HTTP layer
/// consults before it does anything clever with tokens.
///
/// It also owns the clock. An impersonation token expires on its own after
/// thirty minutes and there is no refresh for it, so something has to notice
/// and hand the admin back their own session — otherwise the app sits there
/// showing a tenant it can no longer talk to, 401ing on every tap.
class ImpersonationController extends Notifier<ImpersonationSession?> {
  Timer? _timer;

  @override
  ImpersonationSession? build() {
    ref.onDispose(_cancel);
    return null;
  }

  /// Installs [session] and arms the expiry timer. Null clears both.
  void set(ImpersonationSession? session) {
    _cancel();
    state = session;

    if (session == null) return;

    if (session.hasExpired) {
      // Restored from storage after the token had already died — for instance
      // the app was killed mid-session and reopened an hour later.
      scheduleMicrotask(_expire);
      return;
    }
    _timer = Timer(session.remaining, _expire);
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _expire() {
    _cancel();
    if (state == null) return;
    // Read, not watch: this fires long after construction, and the auth
    // controller is the thing that knows how to put the admin back.
    unawaited(
      ref.read(authControllerProvider.notifier).endImpersonation(expired: true),
    );
  }
}

final impersonationControllerProvider =
    NotifierProvider<ImpersonationController, ImpersonationSession?>(
  ImpersonationController.new,
);

/// True while the signed-in identity is borrowed. Cheap enough to watch from
/// anywhere that needs to draw differently during a session.
final isImpersonatingProvider = Provider<bool>(
  (ref) => ref.watch(impersonationControllerProvider) != null,
);
