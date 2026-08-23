import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'employee_picker.dart';
import 'itam_models.dart';
import 'itam_repository.dart';

/// One machine: where it is, who has it, and the three things you can do to it
/// while standing next to it.
class AssetDetailScreen extends ConsumerStatefulWidget {
  const AssetDetailScreen({super.key, required this.asset});

  final Asset asset;

  static void open(BuildContext context, {required Asset asset}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AssetDetailScreen(asset: asset)),
    );
  }

  @override
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
  late Asset _asset = widget.asset;
  bool _busy = false;

  /// Every action returns the updated asset, so the screen and the list behind
  /// it both take the server's version rather than guessing at the new state.
  Future<void> _run(
    Future<Asset> Function() action,
    String success,
    String failure,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await action();
      ref.read(assetsProvider.notifier).apply(updated);
      if (!mounted) return;
      setState(() => _asset = updated);
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign() async {
    final person = await EmployeePicker.show(
      context,
      title: 'Give ${_asset.name} to',
    );
    if (person == null || !mounted) return;

    await _run(
      () => ref.read(itamRepositoryProvider).assignAsset(_asset.id, person.id),
      '${_asset.name} is now with ${person.fullName}.',
      'Could not assign that machine.',
    );
  }

  Future<void> _unassign() async {
    final holder = _asset.assignedToName ?? 'its current holder';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Take ${_asset.name} back?'),
        content: Text('It will be marked available again, and $holder will no '
            'longer be recorded as holding it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Take back'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _run(
      () => ref.read(itamRepositoryProvider).unassignAsset(_asset.id),
      '${_asset.name} is back in stock.',
      'Could not return that machine.',
    );
  }

  Future<void> _toggleMaintenance() async {
    final goingIn = !_asset.isUnderMaintenance;
    await _run(
      () => ref.read(itamRepositoryProvider).setMaintenance(_asset.id, goingIn),
      goingIn
          ? '${_asset.name} is marked for repair.'
          : '${_asset.name} is back in service.',
      'Could not change that.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(ItamPermissions.hardwareUpdate);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Asset')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Header(asset: _asset),
          if (_asset.warrantyExpiringSoon) ...[
            const SizedBox(height: 14),
            MessageBanner.warning(
              _asset.warrantyExpiry != null &&
                      DateTime.tryParse(_asset.warrantyExpiry!)
                              ?.isBefore(DateTime.now()) ==
                          true
                  ? 'Warranty expired on ${Fmt.date(_asset.warrantyExpiry)}.'
                  : 'Warranty ends ${Fmt.date(_asset.warrantyExpiry)}.',
            ),
          ],
          if (canUpdate && _asset.isActionable) ...[
            const SizedBox(height: 16),
            if (_busy) const Loader(padding: 8) else _Actions(
              asset: _asset,
              onAssign: _assign,
              onUnassign: _unassign,
              onMaintenance: _toggleMaintenance,
            ),
          ],
          if (_asset.isDisposed) ...[
            const SizedBox(height: 16),
            const MessageBanner.info(
              'This asset has been disposed of. It is kept for the record and '
              'cannot be assigned or serviced.',
            ),
          ],
          const SizedBox(height: 22),
          _Specs(asset: _asset),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (asset.makeModel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        asset.makeModel!,
                        style: TextStyle(
                          color: bos.textSecondary,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(asset.status),
            ],
          ),
          if (asset.identifier != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.qr_code_2_rounded, size: 15, color: bos.muted),
                const SizedBox(width: 6),
                Text(
                  asset.identifier!,
                  style: TextStyle(
                    color: bos.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: bos.borderLight),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                asset.isAssigned
                    ? Icons.person_rounded
                    : Icons.inventory_2_outlined,
                size: 17,
                color: asset.isAssigned ? bos.brand : bos.muted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  asset.isAssigned
                      ? 'With ${asset.assignedToName ?? 'someone'}'
                          '${asset.assignedAt != null ? ' since ${Fmt.date(asset.assignedAt)}' : ''}'
                      : 'Not assigned to anyone',
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.asset,
    required this.onAssign,
    required this.onUnassign,
    required this.onMaintenance,
  });

  final Asset asset;
  final VoidCallback onAssign;
  final VoidCallback onUnassign;
  final VoidCallback onMaintenance;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // A machine under repair should not be handed to anybody, so assigning
        // is offered only when it is actually available.
        if (asset.isAvailable)
          FilledButton.icon(
            onPressed: onAssign,
            icon: const Icon(Icons.person_add_alt_rounded, size: 17),
            label: const Text('Assign'),
          ),
        if (asset.isAssigned)
          OutlinedButton.icon(
            onPressed: onUnassign,
            icon: const Icon(Icons.assignment_return_outlined, size: 17),
            label: const Text('Take back'),
            style: OutlinedButton.styleFrom(
              foregroundColor: bos.brandInk,
              side: BorderSide(color: bos.brandInk.withValues(alpha: 0.4)),
            ),
          ),
        OutlinedButton.icon(
          onPressed: onMaintenance,
          icon: Icon(
            asset.isUnderMaintenance
                ? Icons.check_circle_outline_rounded
                : Icons.build_outlined,
            size: 17,
          ),
          label: Text(
            asset.isUnderMaintenance ? 'Back in service' : 'Send for repair',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: bos.warning,
            side: BorderSide(color: bos.warning.withValues(alpha: 0.4)),
          ),
        ),
      ],
    );
  }
}

class _Specs extends StatelessWidget {
  const _Specs({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final rows = <({String label, String? value, IconData icon})>[
      (
        label: 'Category',
        value: asset.category == null ? null : Fmt.label(asset.category),
        icon: Icons.category_outlined
      ),
      (
        label: 'Serial number',
        value: asset.serialNumber,
        icon: Icons.numbers_rounded
      ),
      (
        label: 'Operating system',
        value: asset.operatingSystem,
        icon: Icons.terminal_rounded
      ),
      (
        label: 'Processor',
        value: asset.processorModel,
        icon: Icons.memory_rounded
      ),
      (label: 'Memory', value: asset.ramSize, icon: Icons.sd_card_outlined),
      (label: 'Storage', value: asset.storageSize, icon: Icons.storage_rounded),
      (
        label: 'IP address',
        value: asset.ipAddress,
        icon: Icons.lan_outlined
      ),
      (
        label: 'MAC address',
        value: asset.macAddress,
        icon: Icons.settings_ethernet_rounded
      ),
      (
        label: 'Purchased',
        value: asset.purchaseDate == null ? null : Fmt.date(asset.purchaseDate),
        icon: Icons.receipt_long_outlined
      ),
      (
        label: 'Warranty until',
        value:
            asset.warrantyExpiry == null ? null : Fmt.date(asset.warrantyExpiry),
        icon: Icons.verified_user_outlined
      ),
    ].where((r) => r.value != null && r.value!.trim().isNotEmpty).toList();

    if (rows.isEmpty && (asset.notes?.trim().isEmpty ?? true)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Specification', icon: Icons.memory_rounded),
        if (rows.isNotEmpty)
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) ...[
                    const SizedBox(height: 10),
                    Divider(height: 1, color: bos.borderLight),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(rows[i].icon, size: 17, color: bos.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          rows[i].label,
                          style: TextStyle(color: bos.muted, fontSize: 13),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          rows[i].value!,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        if (asset.notes?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 14),
          AppCard(
            child: Text(
              asset.notes!.trim(),
              style: TextStyle(color: bos.text, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }
}
