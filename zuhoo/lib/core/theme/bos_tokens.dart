import 'package:flutter/material.dart';

import 'accents.dart';

/// The `--bos-*` design tokens, ported from the web app's stylesheets.
///
/// Every colour the app draws comes from here. Nothing in a feature widget
/// should hardcode a hex, for the reason `global.scss` states plainly: a
/// second palette swaps these values *and only these values*, so a literal
/// anywhere else is a hole that dark mode falls through.
///
/// Attached to `ThemeData` as an extension and read with
/// `Theme.of(context).bos`.
@immutable
class BosPalette extends ThemeExtension<BosPalette> {
  const BosPalette({
    required this.brightness,
    required this.brand,
    required this.brandInk,
    required this.brandSoft,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
    required this.info,
    required this.infoSoft,
    required this.neutralSoft,
    required this.text,
    required this.textSecondary,
    required this.muted,
    required this.border,
    required this.borderLight,
    required this.bgPage,
    required this.bgCard,
    required this.bgHover,
    required this.bgSubtle,
  });

  final Brightness brightness;

  /// Brand as a *fill*: buttons, the active nav pill, badges. Carries white.
  final Color brand;

  /// Brand as *ink*: links, brand-coloured icons and labels on the page.
  final Color brandInk;

  /// Low-alpha brand tint for selected rows and icon tiles.
  final Color brandSoft;

  // Semantic pairs. The pair is the unit: `-soft` is the fill, the solid is
  // the text or icon drawn on top of it.
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color warning;
  final Color warningSoft;
  final Color info;
  final Color infoSoft;
  final Color neutralSoft;

  final Color text;
  final Color textSecondary;
  final Color muted;
  final Color border;
  final Color borderLight;
  final Color bgPage;
  final Color bgCard;
  final Color bgHover;
  final Color bgSubtle;

  bool get isDark => brightness == Brightness.dark;

  /// Light surfaces, from `_variables.scss` / `global.scss`.
  factory BosPalette.light(AppAccent accent) => BosPalette(
        brightness: Brightness.light,
        brand: accent.fill,
        brandInk: accent.ink,
        brandSoft: accent.softFor(Brightness.light),
        success: const Color(0xFF0B7B61),
        successSoft: const Color(0xFF0F9B7A).withValues(alpha: 0.13),
        danger: const Color(0xFFC2394C),
        dangerSoft: const Color(0xFFE05264).withValues(alpha: 0.13),
        warning: const Color(0xFF9A5B06),
        warningSoft: const Color(0xFFC87914).withValues(alpha: 0.14),
        info: const Color(0xFF077699),
        infoSoft: const Color(0xFF0C9DC8).withValues(alpha: 0.13),
        neutralSoft: const Color(0xFF687789).withValues(alpha: 0.12),
        text: const Color(0xFF111827),
        textSecondary: const Color(0xFF273447),
        muted: const Color(0xFF687789),
        border: const Color(0xFFDBE4EF),
        borderLight: const Color(0xFFEAF0F7),
        bgPage: const Color(0xFFF4F7FB),
        bgCard: const Color(0xFFFFFFFF),
        bgHover: const Color(0xFFEEF6E7),
        bgSubtle: const Color(0xFFF7F9FC),
      );

  /// Dark surfaces, from `_dark.scss`.
  ///
  /// The text ramp is deliberately below maximum contrast. Light text on a
  /// near-black field at 15:1 halates — the glyphs bloom and their edges
  /// shimmer, worst for astigmatic readers — so body text lands around 11:1 on
  /// a card, still far above the 4.5:1 floor but out of the glare zone. The
  /// hierarchy is carried by separating page from card in luminance instead.
  factory BosPalette.dark(AppAccent accent) => BosPalette(
        brightness: Brightness.dark,
        brand: accent.fillDark,
        brandInk: accent.inkDark,
        brandSoft: accent.softFor(Brightness.dark),
        success: const Color(0xFF34D399),
        successSoft: const Color(0xFF34D399).withValues(alpha: 0.18),
        danger: const Color(0xFFF87171),
        dangerSoft: const Color(0xFFF87171).withValues(alpha: 0.18),
        warning: const Color(0xFFFBBF24),
        warningSoft: const Color(0xFFFBBF24).withValues(alpha: 0.18),
        info: const Color(0xFF38BDF8),
        infoSoft: const Color(0xFF38BDF8).withValues(alpha: 0.18),
        neutralSoft: const Color(0xFF8DA0B8).withValues(alpha: 0.16),
        text: const Color(0xFFD6DFDA),
        textSecondary: const Color(0xFFB3C1BA),
        muted: const Color(0xFF94A39B),
        border: const Color(0xFF2C3B34),
        borderLight: const Color(0xFF232E29),
        bgPage: const Color(0xFF121915),
        bgCard: const Color(0xFF1B2620),
        bgHover: const Color(0xFF263329),
        bgSubtle: const Color(0xFF17201B),
      );

  /// Badge colours for a backend status string.
  ///
  /// One table for every module, because the same word should not mean green
  /// on one screen and grey on another. Anything unrecognised falls back to
  /// neutral rather than to the brand, so a value nobody has classified never
  /// masquerades as a normal, understood one — but the cost of *leaving* a
  /// real status unclassified is a silent one: an overdue invoice rendered in
  /// the same grey as a draft is a warning nobody sees.
  ({Color fg, Color bg}) statusColors(String status) {
    switch (status.toUpperCase()) {
      // Done, and done well.
      case 'PRESENT':
      case 'APPROVED':
      case 'PAID':
      case 'COMPLETED':
      case 'DELIVERED':
      case 'RESOLVED':
      case 'WON':
      case 'ACTIVE':
      case 'QUALIFIED':
      case 'CONFIRMED':
      // A machine nobody is using is ready to hand out, not idle waste.
      // The end of a good hiring pipeline.
      case 'SELECTED':
      case 'OFFER_ACCEPTED':
      case 'HIRED':
      case 'AVAILABLE':
      case 'ACCEPTED':
        return (fg: success, bg: successSoft);

      // Gone wrong, or gone away.
      case 'ABSENT':
      case 'REJECTED':
      case 'CANCELLED':
      case 'FAILED':
      case 'LOST':
      case 'OVERDUE':
      case 'DISQUALIFIED':
      case 'VOIDED':
      case 'BREACHED':
      case 'EXPIRED':
      case 'SUSPENDED':
      case 'OFFER_REJECTED':
      case 'DECLINED':
      case 'WITHDRAWN':
      case 'NO_SHOW':
      case 'REVOKED':
      case 'TERMINATED':
        return (fg: danger, bg: dangerSoft);

      // Waiting on someone.
      case 'LATE':
      case 'PENDING':
      case 'PARTIAL_DAY':
      case 'PARTIALLY_PAID':
      case 'WAITING':
      case 'WAITING_CLIENT':
      case 'ON_HOLD':
      case 'QUOTATION_PENDING':
      // Not broken yet, but somebody has to act before it is.
      // Waiting on the candidate.
      case 'OFFER_PENDING':
      case 'OFFER_SENT':
      case 'UNDER_MAINTENANCE':
      case 'EXPIRING_SOON':
      case 'PENDING_PAYMENT':
        return (fg: warning, bg: warningSoft);

      // Under way, or merely informational.
      case 'ON_LEAVE':
      case 'HALF_DAY':
      case 'WORK_FROM_HOME':
      case 'IN_PROGRESS':
      case 'ISSUED':
      case 'SENT':
      case 'ASSIGNED':
      // Moving through the hiring pipeline.
      // An appraisal working its way through sign-off.
      case 'SELF_ASSESSMENT':
      case 'MANAGER_REVIEW':
      case 'HR_APPROVAL':
      case 'FINAL_APPROVAL':

      case 'APPLIED':
      case 'SCREENING':
      case 'SHORTLISTED':
      case 'INTERVIEW_SCHEDULED':
      case 'INTERVIEWED':
      case 'SCHEDULED':
      case 'UNDER_REVIEW':
      case 'RESUBMITTED':
      case 'CONTACTED':
      case 'REFUNDED':
      case 'OPEN':
        return (fg: info, bg: infoSoft);

      case 'HOLIDAY':
      case 'WEEKEND':
      case 'NEGOTIATION':
      case 'PROPOSAL':
        return (fg: brandInk, bg: brandSoft);

      // NEW, DRAFT, CLOSED, QUALIFICATION, PRESENTATION and anything unknown:
      // real states that carry no urgency of their own.
      default:
        return (fg: muted, bg: neutralSoft);
    }
  }

  @override
  BosPalette copyWith({
    Brightness? brightness,
    Color? brand,
    Color? brandInk,
    Color? brandSoft,
    Color? success,
    Color? successSoft,
    Color? danger,
    Color? dangerSoft,
    Color? warning,
    Color? warningSoft,
    Color? info,
    Color? infoSoft,
    Color? neutralSoft,
    Color? text,
    Color? textSecondary,
    Color? muted,
    Color? border,
    Color? borderLight,
    Color? bgPage,
    Color? bgCard,
    Color? bgHover,
    Color? bgSubtle,
  }) =>
      BosPalette(
        brightness: brightness ?? this.brightness,
        brand: brand ?? this.brand,
        brandInk: brandInk ?? this.brandInk,
        brandSoft: brandSoft ?? this.brandSoft,
        success: success ?? this.success,
        successSoft: successSoft ?? this.successSoft,
        danger: danger ?? this.danger,
        dangerSoft: dangerSoft ?? this.dangerSoft,
        warning: warning ?? this.warning,
        warningSoft: warningSoft ?? this.warningSoft,
        info: info ?? this.info,
        infoSoft: infoSoft ?? this.infoSoft,
        neutralSoft: neutralSoft ?? this.neutralSoft,
        text: text ?? this.text,
        textSecondary: textSecondary ?? this.textSecondary,
        muted: muted ?? this.muted,
        border: border ?? this.border,
        borderLight: borderLight ?? this.borderLight,
        bgPage: bgPage ?? this.bgPage,
        bgCard: bgCard ?? this.bgCard,
        bgHover: bgHover ?? this.bgHover,
        bgSubtle: bgSubtle ?? this.bgSubtle,
      );

  @override
  BosPalette lerp(ThemeExtension<BosPalette>? other, double t) {
    if (other is! BosPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return BosPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      brand: mix(brand, other.brand),
      brandInk: mix(brandInk, other.brandInk),
      brandSoft: mix(brandSoft, other.brandSoft),
      success: mix(success, other.success),
      successSoft: mix(successSoft, other.successSoft),
      danger: mix(danger, other.danger),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      warning: mix(warning, other.warning),
      warningSoft: mix(warningSoft, other.warningSoft),
      info: mix(info, other.info),
      infoSoft: mix(infoSoft, other.infoSoft),
      neutralSoft: mix(neutralSoft, other.neutralSoft),
      text: mix(text, other.text),
      textSecondary: mix(textSecondary, other.textSecondary),
      muted: mix(muted, other.muted),
      border: mix(border, other.border),
      borderLight: mix(borderLight, other.borderLight),
      bgPage: mix(bgPage, other.bgPage),
      bgCard: mix(bgCard, other.bgCard),
      bgHover: mix(bgHover, other.bgHover),
      bgSubtle: mix(bgSubtle, other.bgSubtle),
    );
  }
}

extension BosThemeAccess on ThemeData {
  /// `Theme.of(context).bos.brand` — the single entry point to the palette.
  BosPalette get bos =>
      extension<BosPalette>() ?? BosPalette.light(AppAccent.defaultAccent);
}
