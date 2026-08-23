import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'accents.dart';

/// What the user has chosen in Appearance.
@immutable
class ThemeSettings {
  const ThemeSettings({
    this.mode = ThemeMode.system,
    this.accent = AppAccent.defaultAccent,
  });

  /// `system` means "follow the OS", and is the default until the user picks a
  /// side. Once they have picked, the choice sticks: someone who explicitly
  /// chose light does not want their app flipping at sunset because their
  /// phone's schedule fired.
  final ThemeMode mode;

  final AppAccent accent;

  ThemeSettings copyWith({ThemeMode? mode, AppAccent? accent}) => ThemeSettings(
        mode: mode ?? this.mode,
        accent: accent ?? this.accent,
      );
}

class ThemeController extends Notifier<ThemeSettings> {
  static const _modeKey = 'zuhoo.theme.mode';
  static const _accentKey = 'zuhoo.theme.accent';

  @override
  ThemeSettings build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return ThemeSettings(
      mode: _modeFromId(prefs.getString(_modeKey)),
      accent: AppAccent.fromId(prefs.getString(_accentKey)),
    );
  }

  Future<void> setMode(ThemeMode mode) async {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
    final prefs = ref.read(sharedPreferencesProvider);
    if (mode == ThemeMode.system) {
      // Removed rather than stored, so "follow the system" stays the absence
      // of a choice rather than a third value to keep in sync.
      await prefs.remove(_modeKey);
    } else {
      await prefs.setString(_modeKey, _idFromMode(mode));
    }
  }

  Future<void> setAccent(AppAccent accent) async {
    if (state.accent == accent) return;
    state = state.copyWith(accent: accent);
    await ref.read(sharedPreferencesProvider).setString(_accentKey, accent.id);
  }

  /// Flip between light and dark, treating "currently following the system" as
  /// whatever the system is showing right now.
  Future<void> toggle(Brightness current) => setMode(
        current == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
      );

  static ThemeMode _modeFromId(String? id) => switch (id) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _idFromMode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeSettings>(ThemeController.new);
