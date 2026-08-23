import 'package:flutter/material.dart';

import 'accents.dart';
import 'bos_tokens.dart';

/// Builds the Material theme from a palette.
///
/// The rule kept throughout: every colour comes from [BosPalette], and the
/// component themes below are the only place that translates a token into a
/// Material slot. A feature widget that needs a colour reads the palette, not
/// `Colors.something`.
class AppTheme {
  AppTheme._();

  static const _radius = 12.0;
  static const _radiusSm = 8.0;

  static ThemeData light(AppAccent accent) => _build(BosPalette.light(accent));

  static ThemeData dark(AppAccent accent) => _build(BosPalette.dark(accent));

  static ThemeData _build(BosPalette bos) {
    final isDark = bos.isDark;

    final scheme = ColorScheme(
      brightness: bos.brightness,
      primary: bos.brand,
      onPrimary: Colors.white,
      primaryContainer: bos.brandSoft,
      onPrimaryContainer: bos.brandInk,
      secondary: bos.info,
      onSecondary: Colors.white,
      error: bos.danger,
      onError: Colors.white,
      errorContainer: bos.dangerSoft,
      onErrorContainer: bos.danger,
      surface: bos.bgCard,
      onSurface: bos.text,
      surfaceContainerLowest: bos.bgPage,
      surfaceContainerLow: bos.bgSubtle,
      surfaceContainer: bos.bgCard,
      surfaceContainerHigh: bos.bgHover,
      surfaceContainerHighest: bos.bgHover,
      onSurfaceVariant: bos.textSecondary,
      outline: bos.border,
      outlineVariant: bos.borderLight,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isDark ? bos.text : bos.textSecondary,
      onInverseSurface: bos.bgCard,
      inversePrimary: bos.brandInk,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: bos.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bos.bgPage,
      canvasColor: bos.bgPage,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      extensions: [bos],
      textTheme: _textTheme(base.textTheme, bos),
      appBarTheme: AppBarTheme(
        backgroundColor: bos.bgCard,
        foregroundColor: bos.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: bos.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        // A hairline instead of a shadow: the page is tinted and a card is
        // white, so a shadow under the bar reads as a third surface.
        shape: Border(bottom: BorderSide(color: bos.border, width: 0.5)),
      ),
      cardTheme: CardThemeData(
        color: bos.bgCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: bos.border),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: bos.borderLight,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: bos.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: bos.brand.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
          elevation: 0,
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusSm),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: bos.brand,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusSm),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: bos.brandInk,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: bos.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusSm),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: bos.brandInk,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? bos.bgSubtle : bos.bgCard,
        hintStyle: TextStyle(color: bos.muted, fontSize: 15),
        labelStyle: TextStyle(color: bos.textSecondary, fontSize: 15),
        floatingLabelStyle: TextStyle(color: bos.brandInk, fontSize: 14),
        prefixIconColor: bos.muted,
        suffixIconColor: bos.muted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: _inputBorder(bos.border),
        enabledBorder: _inputBorder(bos.border),
        focusedBorder: _inputBorder(bos.brand, width: 2),
        errorBorder: _inputBorder(bos.danger),
        focusedErrorBorder: _inputBorder(bos.danger, width: 2),
        errorStyle: TextStyle(color: bos.danger, fontSize: 12.5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bos.neutralSoft,
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: bos.textSecondary,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bos.bgCard,
        surfaceTintColor: Colors.transparent,
        indicatorColor: bos.brandSoft,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? bos.brandInk : bos.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight:
                states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? bos.brandInk : bos.muted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bos.bgCard,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: bos.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bos.bgCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: TextStyle(
          color: bos.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(color: bos.textSecondary, fontSize: 15),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? bos.bgHover : bos.text,
        contentTextStyle: TextStyle(
          color: isDark ? bos.text : Colors.white,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusSm),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: bos.muted,
        textColor: bos.text,
        titleTextStyle: TextStyle(
          color: bos.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(color: bos.muted, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusSm),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : bos.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? bos.brand : bos.neutralSoft,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? bos.brand : bos.border,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: bos.brand,
        linearTrackColor: bos.neutralSoft,
        circularTrackColor: Colors.transparent,
      ),
      iconTheme: IconThemeData(color: bos.textSecondary, size: 22),
      tabBarTheme: TabBarThemeData(
        labelColor: bos.brandInk,
        unselectedLabelColor: bos.muted,
        indicatorColor: bos.brand,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: bos.borderLight,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusSm),
        borderSide: BorderSide(color: color, width: width),
      );

  static TextTheme _textTheme(TextTheme base, BosPalette bos) => base.copyWith(
        displaySmall: base.displaySmall?.copyWith(color: bos.text),
        headlineMedium: base.headlineMedium?.copyWith(
          color: bos.text,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        headlineSmall: base.headlineSmall?.copyWith(
          color: bos.text,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: base.titleLarge?.copyWith(
          color: bos.text,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: base.titleMedium?.copyWith(
          color: bos.text,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: base.titleSmall?.copyWith(
          color: bos.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.bodyLarge?.copyWith(color: bos.text),
        bodyMedium: base.bodyMedium?.copyWith(color: bos.textSecondary),
        bodySmall: base.bodySmall?.copyWith(color: bos.muted),
        labelLarge: base.labelLarge?.copyWith(
          color: bos.text,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: base.labelMedium?.copyWith(color: bos.muted),
        labelSmall: base.labelSmall?.copyWith(color: bos.muted),
      );
}
