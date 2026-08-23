import 'dart:io';

import 'package:flutter/foundation.dart';

/// Where the BusinessOS backend lives.
///
/// The Angular app hardcodes `http://localhost:8085/api` in its
/// `environment.ts`, which is correct for a browser on the dev machine and
/// wrong for every mobile target: on an Android emulator `localhost` is the
/// emulator itself, not the host, and on a physical device it is the phone.
/// So the default is resolved per-platform, and can always be overridden at
/// build time for a device on the same LAN:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.0.42:8085/api
class Env {
  Env._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Host the backend is reachable at, without the `/api` suffix.
  static String get host {
    if (_override.isNotEmpty) {
      return _override.replaceFirst(RegExp(r'/api/?$'), '');
    }
    // 10.0.2.2 is the Android emulator's alias for the host machine's
    // loopback. The iOS simulator shares the host's network, so localhost
    // is already right there.
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8085';
    return 'http://localhost:8085';
  }

  /// Base for every API call. Mirrors Angular's `environment.apiUrl`.
  static String get apiUrl => '$host/api';

  /// Base for served images (avatars, attachments). The Angular
  /// `resolveImageUrl()` strips `/api` off `apiUrl` for exactly this.
  static String get imgUrl => host;

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// Resolves a possibly-relative image path returned by the backend into
  /// something [Image.network] can load. Port of `AuthService.resolveImageUrl`.
  static String? resolveImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('data:')) {
      return url;
    }
    return url.startsWith('/') ? '$imgUrl$url' : '$imgUrl/$url';
  }
}
