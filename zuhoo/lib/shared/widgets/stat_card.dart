import 'package:flutter/material.dart';

import '../../core/theme/bos_tokens.dart';
import '../util/formatters.dart';

/// A single headline figure.
///
/// [value] is nullable and a null renders as an em dash, never as zero. That
/// distinction is the whole point of the widget: "we have no reading for this"
/// and "the reading is zero" mean different things to someone checking their
/// own attendance or leave balance, and collapsing them into `0` quietly tells
/// them something untrue.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.suffix,
    this.tone,
    this.onTap,
  });

  final String label;
  final String? value;
  final IconData icon;
  final String? suffix;

  /// Accent for the icon tile. Defaults to the brand.
  final Color? tone;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final accent = tone ?? bos.brandInk;
    final hasValue = value != null;

    return Material(
      color: bos.bgCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: bos.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 32,
                width: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: accent),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value ?? Fmt.dash,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasValue ? bos.text : bos.muted,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  if (suffix != null && hasValue) ...[
                    const SizedBox(width: 3),
                    Text(
                      suffix!,
                      style: TextStyle(
                        color: bos.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: bos.muted, fontSize: 12.5, height: 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
