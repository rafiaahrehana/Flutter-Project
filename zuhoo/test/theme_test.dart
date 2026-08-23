import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/theme/accents.dart';
import 'package:zuhoo/core/theme/app_theme.dart';
import 'package:zuhoo/core/theme/bos_tokens.dart';
import 'package:zuhoo/shared/widgets/primitives.dart';

/// The palette is the one thing every screen depends on and nothing asserts at
/// runtime. A token that is accidentally the same colour as the surface it sits
/// on does not crash — it just makes text invisible in one theme, on one
/// accent, which is exactly the combination nobody opens before shipping.
void main() {
  group('AppTheme', () {
    test('every accent produces a usable palette in both modes', () {
      for (final accent in AppAccent.values) {
        for (final theme in [AppTheme.light(accent), AppTheme.dark(accent)]) {
          final bos = theme.extension<BosPalette>();
          expect(bos, isNotNull,
              reason: '${accent.label} is missing its palette extension');

          // Text has to be distinguishable from the surface behind it. Exact
          // ratios are a design call; being *identical* is always a bug.
          expect(bos!.text, isNot(bos.bgCard));
          expect(bos.text, isNot(bos.bgPage));
          expect(bos.muted, isNot(bos.bgCard));

          // A card must be separable from the page — that luminance step is
          // what carries the hierarchy in dark mode.
          expect(bos.bgCard, isNot(bos.bgPage));

          // The brand fills buttons under white text, so it must not be white.
          expect(bos.brand, isNot(Colors.white));
        }
      }
    });

    test('dark is not merely light with a different brightness flag', () {
      final light = AppTheme.light(AppAccent.emerald).extension<BosPalette>()!;
      final dark = AppTheme.dark(AppAccent.emerald).extension<BosPalette>()!;

      expect(dark.bgPage, isNot(light.bgPage));
      expect(dark.text, isNot(light.text));
      expect(dark.brand, isNot(light.brand));
      expect(dark.isDark, isTrue);
      expect(light.isDark, isFalse);
    });

    test('the default accent is the real BusinessOS brand', () {
      // The mobile app should be the same green as the product it belongs to,
      // so these two are pinned to the values in the web app's stylesheets.
      expect(AppAccent.defaultAccent, AppAccent.emerald);
      expect(AppAccent.emerald.fill, const Color(0xFF367C2B));
      expect(AppAccent.emerald.fillDark, const Color(0xFF047857));
    });

    test('every status that carries urgency is coloured, not left grey', () {
      final bos = AppTheme.light(AppAccent.emerald).extension<BosPalette>()!;

      // Leaving a real status unclassified fails silently: an overdue invoice
      // in the same grey as a draft is a warning nobody sees. These are the
      // ones where the colour is the message.
      for (final status in ['WON', 'RESOLVED', 'ACTIVE', 'PAID', 'APPROVED', 'AVAILABLE', 'HIRED', 'OFFER_ACCEPTED', 'SELECTED']) {
        expect(bos.statusColors(status).fg, bos.success, reason: status);
      }
      for (final status in ['LOST', 'OVERDUE', 'REJECTED', 'CANCELLED', 'BREACHED', 'REVOKED', 'OFFER_REJECTED', 'WITHDRAWN', 'NO_SHOW']) {
        expect(bos.statusColors(status).fg, bos.danger, reason: status);
      }
      for (final status in ['PENDING', 'WAITING', 'ON_HOLD', 'PARTIALLY_PAID', 'UNDER_MAINTENANCE', 'EXPIRING_SOON', 'OFFER_SENT', 'OFFER_PENDING']) {
        expect(bos.statusColors(status).fg, bos.warning, reason: status);
      }
      for (final status in ['ISSUED', 'IN_PROGRESS', 'ASSIGNED', 'OPEN', 'APPLIED', 'SCREENING', 'SHORTLISTED', 'INTERVIEWED', 'SELF_ASSESSMENT', 'MANAGER_REVIEW', 'HR_APPROVAL', 'FINAL_APPROVAL']) {
        expect(bos.statusColors(status).fg, bos.info, reason: status);
      }
    });

    test('an unrecognised status falls back to neutral, not to the brand', () {
      final bos = AppTheme.light(AppAccent.emerald).extension<BosPalette>()!;
      final unknown = bos.statusColors('SOME_NEW_BACKEND_STATUS');

      // Dressing an unknown value in the brand colour would make it read as a
      // normal, understood state.
      expect(unknown.fg, bos.muted);
      expect(unknown.fg, isNot(bos.success));
      expect(bos.statusColors('DELIVERED').fg, bos.success);
      expect(bos.statusColors('CANCELLED').fg, bos.danger);
    });
  });

  group('themed widgets', () {
    Widget host(ThemeData theme, Widget child) => MaterialApp(
          theme: theme,
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('a status chip renders in every accent and both modes',
        (tester) async {
      for (final accent in AppAccent.values) {
        for (final theme in [AppTheme.light(accent), AppTheme.dark(accent)]) {
          await tester.pumpWidget(host(theme, const StatusChip('APPROVED')));
          expect(find.text('Approved'), findsOneWidget);
        }
      }
    });

    testWidgets('switching theme repaints without rebuilding the app',
        (tester) async {
      var theme = AppTheme.light(AppAccent.emerald);
      late StateSetter setTheme;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setTheme = setState;
            return host(theme, LoadingButton(
              label: 'Check in',
              loading: false,
              // Enabled: a disabled button paints the brand at 45% alpha, which
              // is right but is not the colour this test is about.
              onPressed: () {},
            ));
          },
        ),
      );

      // Read the colour actually painted, not one declared on the widget:
      // LoadingButton sets no style of its own, which is the point — the fill
      // comes from the theme, so reading the theme back would prove nothing.
      Color buttonColour() {
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(ElevatedButton),
                matching: find.byType(Material),
              )
              .first,
        );
        return material.color!;
      }

      expect(buttonColour(), AppAccent.emerald.fill);

      setTheme(() => theme = AppTheme.dark(AppAccent.violet));
      await tester.pumpAndSettle();

      // Applies immediately: no restart, no reload, same widget instance.
      expect(buttonColour(), AppAccent.violet.fillDark);
    });
  });
}
