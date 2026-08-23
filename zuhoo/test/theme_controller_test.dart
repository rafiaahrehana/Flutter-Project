import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuhoo/core/providers.dart';
import 'package:zuhoo/core/theme/accents.dart';
import 'package:zuhoo/core/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('ThemeController', () {
    test('follows the system until the user picks a side', () async {
      final container = await containerWith({});
      expect(container.read(themeControllerProvider).mode, ThemeMode.system);
      expect(container.read(themeControllerProvider).accent, AppAccent.emerald);
    });

    test('restores a stored choice on the next launch', () async {
      final container = await containerWith({
        'zuhoo.theme.mode': 'dark',
        'zuhoo.theme.accent': 'violet',
      });

      final settings = container.read(themeControllerProvider);
      expect(settings.mode, ThemeMode.dark);
      expect(settings.accent, AppAccent.violet);
    });

    test('persists an explicit mode', () async {
      final container = await containerWith({});
      await container.read(themeControllerProvider.notifier).setMode(ThemeMode.light);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString('zuhoo.theme.mode'), 'light');
      expect(container.read(themeControllerProvider).mode, ThemeMode.light);
    });

    test('going back to System clears the stored value', () async {
      // "Follow the system" is the absence of a choice, not a third value to
      // keep in sync — otherwise a future default change would not reach
      // anyone who had ever opened this screen.
      final container = await containerWith({'zuhoo.theme.mode': 'dark'});
      await container
          .read(themeControllerProvider.notifier)
          .setMode(ThemeMode.system);

      expect(container.read(sharedPreferencesProvider).getString('zuhoo.theme.mode'),
          isNull);
    });

    test('an unknown stored accent falls back rather than throwing', () async {
      // Ids are stable strings precisely so a removed accent degrades to the
      // default instead of crashing the app on launch.
      final container = await containerWith({'zuhoo.theme.accent': 'ultraviolet'});
      expect(container.read(themeControllerProvider).accent, AppAccent.emerald);
    });

    test('persists the accent', () async {
      final container = await containerWith({});
      await container.read(themeControllerProvider.notifier).setAccent(AppAccent.rose);

      expect(container.read(sharedPreferencesProvider).getString('zuhoo.theme.accent'),
          'rose');
      expect(container.read(themeControllerProvider).accent, AppAccent.rose);
    });

    test('toggle flips relative to what is on screen now', () async {
      final container = await containerWith({});
      final controller = container.read(themeControllerProvider.notifier);

      // On System, "toggle" has to mean "away from whatever the OS is doing".
      await controller.toggle(Brightness.dark);
      expect(container.read(themeControllerProvider).mode, ThemeMode.light);

      await controller.toggle(Brightness.light);
      expect(container.read(themeControllerProvider).mode, ThemeMode.dark);
    });
  });
}
