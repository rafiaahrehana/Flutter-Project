import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/auth_controller.dart';
import 'auth/auth_repository.dart';
import 'network/api_client.dart';
import 'storage/secure_store.dart';

/// Cross-cutting singletons — the Flutter equivalent of the services Angular's
/// DI container provides app-wide.

/// Overridden in `main()` once the real instance has been awaited, so nothing
/// downstream has to deal with an async preferences handle.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope',
  ),
);

/// The defaults are the strong path. Since v11 the Android implementation
/// already wraps an AES-GCM data key with an RSA key held in the platform
/// KeyStore — which is what the old `encryptedSharedPreferences` flag used to
/// opt into — so there is no weaker mode left to steer away from.
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final secureStoreProvider = Provider<SecureStore>(
  (ref) => SecureStore(ref.watch(secureStorageProvider)),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    store: ref.watch(secureStoreProvider),
    // Read lazily rather than watched: this fires from inside a request, long
    // after construction, and watching the auth controller here would make the
    // HTTP client rebuild on every sign-in.
    onSessionExpired: () =>
        ref.read(authControllerProvider.notifier).handleSessionExpired(),
  );
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(secureStoreProvider),
  ),
);
