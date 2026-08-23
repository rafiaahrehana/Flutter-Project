import 'package:flutter/material.dart';

/// The selectable brand colours.
///
/// Only the *brand* varies with the accent — surfaces, text and the semantic
/// colours are fixed by [BosPalette]. That is a deliberate limit, and the same
/// one WhatsApp draws: a theme picker that repaints the whole chrome produces
/// six skins of wildly different quality, whereas one that repaints the accent
/// over a designed neutral ground stays legible in every choice.
///
/// Each accent carries four values rather than one, because a brand colour has
/// two jobs that pull in opposite directions:
///
///   fill — a background with white text on it, so it must stay dark
///   ink  — the colour used *as* text or an icon on the page background
///
/// In light mode those can be the same value. On a dark surface they cannot:
/// the fill still has to carry white text, while ink has to be light enough to
/// read against near-black. This is the split `_dark.scss` documents when it
/// keeps `--bos-brand` at #047857 for buttons but introduces `--bos-link` at
/// #6EE7B7 for text.
enum AppAccent {
  /// The BusinessOS brand. `fill` values are the real `--bos-brand` tokens
  /// from the web app's light and dark sheets, so the default install of the
  /// mobile app is the same green as the product it belongs to.
  emerald(
    id: 'emerald',
    label: 'Emerald',
    fill: Color(0xFF367C2B),
    ink: Color(0xFF2A6421),
    fillDark: Color(0xFF047857),
    inkDark: Color(0xFF6EE7B7),
  ),
  teal(
    id: 'teal',
    label: 'Teal',
    fill: Color(0xFF0F766E),
    ink: Color(0xFF0F766E),
    fillDark: Color(0xFF0F766E),
    inkDark: Color(0xFF5EEAD4),
  ),
  blue(
    id: 'blue',
    label: 'Blue',
    fill: Color(0xFF1D4ED8),
    ink: Color(0xFF1D4ED8),
    fillDark: Color(0xFF1D4ED8),
    inkDark: Color(0xFF93C5FD),
  ),
  indigo(
    id: 'indigo',
    label: 'Indigo',
    fill: Color(0xFF4338CA),
    ink: Color(0xFF4338CA),
    fillDark: Color(0xFF4338CA),
    inkDark: Color(0xFFA5B4FC),
  ),
  violet(
    id: 'violet',
    label: 'Violet',
    fill: Color(0xFF6D28D9),
    ink: Color(0xFF6D28D9),
    fillDark: Color(0xFF6D28D9),
    inkDark: Color(0xFFC4B5FD),
  ),
  rose(
    id: 'rose',
    label: 'Rose',
    fill: Color(0xFFBE123C),
    ink: Color(0xFFBE123C),
    fillDark: Color(0xFFBE123C),
    inkDark: Color(0xFFFDA4AF),
  ),
  amber(
    id: 'amber',
    label: 'Amber',
    fill: Color(0xFFB45309),
    ink: Color(0xFFB45309),
    fillDark: Color(0xFFB45309),
    inkDark: Color(0xFFFCD34D),
  );

  const AppAccent({
    required this.id,
    required this.label,
    required this.fill,
    required this.ink,
    required this.fillDark,
    required this.inkDark,
  });

  /// Stable key written to preferences. The enum's `name` would do until
  /// someone reorders or renames a case, at which point every user's stored
  /// choice would silently become something else.
  final String id;

  final String label;
  final Color fill;
  final Color ink;
  final Color fillDark;
  final Color inkDark;

  Color fillFor(Brightness brightness) =>
      brightness == Brightness.dark ? fillDark : fill;

  Color inkFor(Brightness brightness) =>
      brightness == Brightness.dark ? inkDark : ink;

  /// The tint used behind selected rows and icon tiles. Alpha rather than a
  /// flat hex so the same token works on a card and on an already-tinted row.
  /// Dark needs the stronger alpha: 0.10 over near-black is invisible.
  Color softFor(Brightness brightness) => brightness == Brightness.dark
      ? inkDark.withValues(alpha: 0.18)
      : fill.withValues(alpha: 0.10);

  static const defaultAccent = AppAccent.emerald;

  static AppAccent fromId(String? id) {
    if (id == null) return defaultAccent;
    for (final accent in AppAccent.values) {
      if (accent.id == id) return accent;
    }
    return defaultAccent;
  }
}
