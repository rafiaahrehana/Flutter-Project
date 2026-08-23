import 'package:flutter/material.dart';

import '../../core/theme/bos_tokens.dart';

/// The small, repeated pieces every screen is assembled from — the Flutter
/// counterparts of the Angular app's `Loader`, `EmptyState`, banner blocks and
/// Bootstrap status badges.

/// Full-width submit button that swaps its label for a spinner while working
/// and refuses further taps. Mirrors the
/// `<button [disabled]="loading"><spinner/></button>` pattern used on every
/// form in the web app.
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19),
                  const SizedBox(width: 8),
                ],
                Text(label),
              ],
            ),
    );
  }
}

/// A message block in one of the semantic colours. One widget rather than four
/// near-identical ones, because the only thing that varies is the pair of
/// tokens and the icon.
class MessageBanner extends StatelessWidget {
  const MessageBanner._({
    super.key,
    required this.message,
    required this.icon,
    required this.tone,
    this.onDismiss,
  });

  const MessageBanner.error(String message, {Key? key, VoidCallback? onDismiss})
      : this._(
          key: key,
          message: message,
          icon: Icons.error_outline_rounded,
          tone: BannerTone.danger,
          onDismiss: onDismiss,
        );

  const MessageBanner.success(String message,
      {Key? key, VoidCallback? onDismiss})
      : this._(
          key: key,
          message: message,
          icon: Icons.check_circle_outline_rounded,
          tone: BannerTone.success,
          onDismiss: onDismiss,
        );

  /// For a consequence the reader should weigh before continuing — not
  /// something that has gone wrong, which is what .error would imply.
  const MessageBanner.warning(String message,
      {Key? key, VoidCallback? onDismiss})
      : this._(
          key: key,
          message: message,
          icon: Icons.warning_amber_rounded,
          tone: BannerTone.warning,
          onDismiss: onDismiss,
        );

  const MessageBanner.info(String message, {Key? key, VoidCallback? onDismiss})
      : this._(
          key: key,
          message: message,
          icon: Icons.info_outline_rounded,
          tone: BannerTone.info,
          onDismiss: onDismiss,
        );

  final String message;
  final IconData icon;
  final BannerTone tone;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final (fg, bg) = switch (tone) {
      BannerTone.danger => (bos.danger, bos.dangerSoft),
      BannerTone.success => (bos.success, bos.successSoft),
      BannerTone.warning => (bos.warning, bos.warningSoft),
      BannerTone.info => (bos.info, bos.infoSoft),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: fg, fontSize: 14, height: 1.35),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close_rounded, size: 18, color: fg),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Dismiss',
            )
          else
            const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// Which semantic pair a [MessageBanner] draws itself in.
enum BannerTone { danger, warning, success, info }

/// Coloured pill for a backend status enum. Colours come from
/// [BosPalette.statusColors] so the same status reads the same everywhere.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.label, this.dense = false});

  final String status;
  final String? label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).bos.statusColors(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label ?? _prettify(status),
        style: TextStyle(
          color: colors.fg,
          fontWeight: FontWeight.w600,
          fontSize: dense ? 11 : 12,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  static String _prettify(String status) => status
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

/// Small uppercase heading with a rule under it, matching the section headers
/// on the web app's multi-section forms.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.icon, this.trailing});

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: bos.brandInk),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: bos.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Bordered surface used everywhere a card would be. Kept as a widget rather
/// than a raw `Card` so padding and the border stay identical across screens.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final content = Padding(padding: padding, child: child);

    return Material(
      color: color ?? bos.bgCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: bos.border),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Centred spinner, sized for use inside a card or a whole page.
class Loader extends StatelessWidget {
  const Loader({super.key, this.message, this.padding = 32});

  final String? message;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 26,
            width: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: bos.brand),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, style: TextStyle(color: bos.muted, fontSize: 13.5)),
          ],
        ],
      ),
    );
  }
}

/// What a list shows when it has nothing in it — distinct from an error, which
/// means the data could not be fetched at all.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: bos.neutralSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: bos.muted),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: bos.text,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(color: bos.muted, fontSize: 13.5, height: 1.4),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

/// Failure state with a retry, for when a fetch did not come back.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 34, color: bos.muted),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: bos.textSecondary, fontSize: 14, height: 1.4),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(140, 44),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Circular avatar that falls back to initials. The backend serves images from
/// a path that has to be resolved against the host, and a broken or absent one
/// must never leave a grey hole in the header.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.initials,
    this.imageUrl,
    this.size = 44,
  });

  final String initials;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final fallback = Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bos.brandSoft, shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(
          color: bos.brandInk,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );

    final url = imageUrl;
    if (url == null || url.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        url,
        height: size,
        width: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}
