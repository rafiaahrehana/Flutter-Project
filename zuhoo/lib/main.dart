import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Awaited here rather than inside a provider so that the theme is known
  // before the first frame. Resolving it lazily would paint one frame in the
  // default theme and then flip — a white flash on every cold start for anyone
  // using dark mode, which is exactly what the web app's pre-paint script in
  // index.html exists to avoid.
  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const ZuhooApp(),
    ),
  );
}
