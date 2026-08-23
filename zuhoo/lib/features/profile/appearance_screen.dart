import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/accents.dart';
import '../../core/theme/bos_tokens.dart';
import '../../core/theme/theme_controller.dart';
import '../../shared/widgets/primitives.dart';

/// Theme picker: light/dark/system, plus the accent colour.
///
/// Both settings apply the moment they are tapped rather than behind a Save
/// button — the preview *is* the whole app, and there is nothing to validate.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final settings = ref.watch(themeControllerProvider);
    final controller = ref.read(themeControllerProvider.notifier);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const SectionHeader('Theme', icon: Icons.brightness_6_outlined),
          AppCard(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                _ModeTile(
                  mode: ThemeMode.light,
                  selected: settings.mode == ThemeMode.light,
                  icon: Icons.light_mode_outlined,
                  title: 'Light',
                  subtitle: 'Always light, whatever the phone does',
                  onTap: () => controller.setMode(ThemeMode.light),
                ),
                _ModeTile(
                  mode: ThemeMode.dark,
                  selected: settings.mode == ThemeMode.dark,
                  icon: Icons.dark_mode_outlined,
                  title: 'Dark',
                  subtitle: 'Always dark, whatever the phone does',
                  onTap: () => controller.setMode(ThemeMode.dark),
                ),
                _ModeTile(
                  mode: ThemeMode.system,
                  selected: settings.mode == ThemeMode.system,
                  icon: Icons.phone_android_outlined,
                  title: 'System',
                  subtitle: 'Follow your phone, including its night schedule',
                  onTap: () => controller.setMode(ThemeMode.system),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader('Accent colour', icon: Icons.palette_outlined),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final accent in AppAccent.values)
                      _AccentSwatch(
                        accent: accent,
                        selected: settings.accent == accent,
                        onTap: () => controller.setAccent(accent),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'The accent colours buttons, links and the selected tab. '
                  'Page and card colours stay the same in every choice, so the '
                  'app stays as readable in one accent as in another.',
                  style: TextStyle(color: bos.muted, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader('Preview', icon: Icons.visibility_outlined),
          const _Preview(),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: bos.brandSoft,
      leading: Icon(icon, color: selected ? bos.brandInk : bos.muted),
      title: Text(
        title,
        style: TextStyle(
          color: bos.text,
          fontSize: 15,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: bos.muted, fontSize: 12.5),
      ),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: bos.brand, size: 21)
          : Icon(Icons.circle_outlined, color: bos.border, size: 21),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AppAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final swatch = accent.fillFor(bos.brightness);

    return Semantics(
      button: true,
      selected: selected,
      label: accent.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 62,
          child: Column(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? bos.text : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 20)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                accent.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? bos.text : bos.muted,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A miniature of the components the accent actually touches, so the choice
/// can be judged on something more representative than seven coloured circles.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: bos.brandSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.bolt_rounded, size: 19, color: bos.brandInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sample row',
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Secondary text sits here',
                      style: TextStyle(color: bos.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const StatusChip('APPROVED', dense: true),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 0.62,
              minHeight: 7,
              backgroundColor: bos.neutralSoft,
              valueColor: AlwaysStoppedAnimation(bos.brand),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Primary'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  child: const Text('Secondary'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
