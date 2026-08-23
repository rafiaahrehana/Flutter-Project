import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'asset_detail_screen.dart';
import 'employee_picker.dart';
import 'itam_models.dart';
import 'itam_repository.dart';
import 'offboarding_detail_screen.dart';

/// IT assets: what the company owns, who has it, and what has to come back
/// when somebody leaves.
///
/// Each tab is gated on the permission its own endpoints check, and the tab
/// disappears rather than erroring — the three are independent entitlements
/// and somebody may hold one and not the others.
class ItamScreen extends ConsumerWidget {
  const ItamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('IT assets')),
        body: const Loader(),
      );
    }

    // Listing hardware accepts either code — the service uses
    // checkAnyPermission(HARDWARE_VIEW, ASSET_VIEW).
    final canHardware = permissions.hasAny(
      const [ItamPermissions.hardwareView, ItamPermissions.assetView],
    );
    final canSoftware = permissions.has(ItamPermissions.softwareView);
    final canOffboarding = permissions.has(ItamPermissions.offboardingView);

    final tabs = <({String label, Widget view})>[
      if (canHardware) (label: 'Hardware', view: const _HardwareTab()),
      if (canSoftware) (label: 'Software', view: const _SoftwareTab()),
      if (canOffboarding) (label: 'Offboarding', view: const _OffboardingTab()),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('IT assets')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Hardware, licences and offboarding each need their own '
              'permission. Your HR or IT team can grant them.',
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('IT assets'),
          bottom: TabBar(
            tabs: [for (final tab in tabs) Tab(text: tab.label)],
          ),
        ),
        body: TabBarView(children: [for (final tab in tabs) tab.view]),
      ),
    );
  }
}

class _HardwareTab extends ConsumerWidget {
  const _HardwareTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PagedListView<Asset>(
      async: ref.watch(assetsProvider),
      onRefresh: () => ref.read(assetsProvider.notifier).refresh(),
      onLoadMore: () => ref.read(assetsProvider.notifier).loadMore(),
      emptyTitle: 'No hardware yet',
      emptyMessage: 'Machines added by your IT team appear here.',
      emptyIcon: Icons.devices_outlined,
      errorMessage: 'Could not load the hardware list.',
      itemBuilder: (context, asset) => _AssetRow(asset: asset),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => AssetDetailScreen.open(context, asset: asset),
        child: AppCard(
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (asset.makeModel != null)
                          Text(
                            asset.makeModel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: bos.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(asset.status, dense: true),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Icon(
                    asset.isAssigned
                        ? Icons.person_outline_rounded
                        : Icons.inventory_2_outlined,
                    size: 14,
                    color: bos.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      asset.isAssigned
                          ? (asset.assignedToName ?? 'Assigned')
                          : 'Unassigned',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: bos.muted, fontSize: 12),
                    ),
                  ),
                  if (asset.identifier != null)
                    Text(
                      asset.identifier!,
                      style: TextStyle(
                        color: bos.muted,
                        fontSize: 11.5,
                        fontFeatures: const [],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftwareTab extends ConsumerWidget {
  const _SoftwareTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PagedListView<SoftwareLicense>(
      async: ref.watch(licensesProvider),
      onRefresh: () => ref.read(licensesProvider.notifier).refresh(),
      onLoadMore: () => ref.read(licensesProvider.notifier).loadMore(),
      emptyTitle: 'No licences yet',
      emptyMessage: 'Software your company pays for appears here.',
      emptyIcon: Icons.workspaces_outline,
      errorMessage: 'Could not load the licence list.',
      itemBuilder: (context, license) => _LicenseCard(license: license),
    );
  }
}

class _LicenseCard extends ConsumerStatefulWidget {
  const _LicenseCard({required this.license});

  final SoftwareLicense license;

  @override
  ConsumerState<_LicenseCard> createState() => _LicenseCardState();
}

class _LicenseCardState extends ConsumerState<_LicenseCard> {
  bool _busy = false;

  Future<void> _assignSeat() async {
    final license = widget.license;
    final person = await EmployeePicker.show(
      context,
      title: 'Give a ${license.softwareName} seat to',
    );
    if (person == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(itamRepositoryProvider)
          .assignSeat(license.id, person.id);
      // assign-seat returns no body, so the seat counts have to be refetched
      // rather than patched in place.
      await ref.read(licensesProvider.notifier).refresh();
      messenger.showSnackBar(
        SnackBar(
          content: Text('${person.fullName} now has a ${license.softwareName} seat.'),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not assign that seat.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final license = widget.license;
    final canAssign = ref
        .watch(permissionControllerProvider)
        .has(ItamPermissions.softwareAssign);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
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
                        license.softwareName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (license.publisher != null)
                        Text(
                          license.publisher!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: bos.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (license.licenseStatus != null)
                  StatusChip(license.licenseStatus!, dense: true),
              ],
            ),
            const SizedBox(height: 12),
            _SeatBar(license: license),
            if (license.expired || license.expiringSoon) ...[
              const SizedBox(height: 10),
              license.expired
                  ? MessageBanner.error(
                      'This licence expired'
                      '${license.licenseExpiryDate != null ? ' on ${Fmt.date(license.licenseExpiryDate)}' : ''}.',
                    )
                  : MessageBanner.warning(
                      'Expires in ${license.daysUntilExpiry} days'
                      '${license.autoRenew ? ' — auto-renew is on.' : '.'}',
                    ),
            ],
            if (license.isOverAllocated) ...[
              const SizedBox(height: 10),
              MessageBanner.warning(
                'More seats are in use than were bought. That is a compliance '
                'problem, not a rounding error.',
              ),
            ],
            if (canAssign) ...[
              const SizedBox(height: 12),
              if (_busy)
                const Loader(padding: 6)
              else
                OutlinedButton.icon(
                  onPressed: license.hasSeatsFree ? _assignSeat : null,
                  icon: const Icon(Icons.person_add_alt_rounded, size: 16),
                  label: Text(
                    license.hasSeatsFree
                        ? 'Assign a seat'
                        : 'No seats available',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: bos.brandInk,
                    side: BorderSide(
                      color: bos.brandInk.withValues(alpha: 0.4),
                    ),
                    minimumSize: const Size.fromHeight(40),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SeatBar extends StatelessWidget {
  const _SeatBar({required this.license});

  final SoftwareLicense license;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final tone = license.isOverAllocated
        ? bos.danger
        : license.isFull
            ? bos.warning
            : bos.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                license.seatsLabel,
                style: TextStyle(
                  color: bos.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              license.seatsAvailable > 0
                  ? '${license.seatsAvailable} free'
                  : 'Full',
              style: TextStyle(
                color: tone,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: license.seatFraction,
            minHeight: 6,
            backgroundColor: bos.neutralSoft,
            valueColor: AlwaysStoppedAnimation(tone),
          ),
        ),
      ],
    );
  }
}

class _OffboardingTab extends ConsumerWidget {
  const _OffboardingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(offboardingProvider);

    return RefreshIndicator(
      color: bos.brand,
      backgroundColor: bos.bgCard,
      onRefresh: () => ref.read(offboardingProvider.notifier).refresh(),
      child: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load offboarding checklists.',
          onRetry: () => ref.read(offboardingProvider.notifier).refresh(),
        ),
        data: (checklists) {
          if (checklists.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                EmptyState(
                  icon: Icons.checklist_rtl_rounded,
                  title: 'Nobody is leaving',
                  message:
                      'Offboarding checklists appear here when HR starts one.',
                ),
              ],
            );
          }

          // Unfinished first, and overdue above those: the list is a worklist,
          // not an archive.
          final sorted = [...checklists]..sort((a, b) {
              if (a.completed != b.completed) return a.completed ? 1 : -1;
              if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
              return a.completionPercentage.compareTo(b.completionPercentage);
            });

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: sorted.length,
            itemBuilder: (context, i) => _ChecklistRow(checklist: sorted[i]),
          );
        },
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.checklist});

  final OffboardingChecklist checklist;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () =>
            OffboardingDetailScreen.open(context, checklist: checklist),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      checklist.personLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (checklist.completed)
                    const StatusChip('COMPLETED', label: 'Done', dense: true)
                  else if (checklist.isOverdue)
                    const StatusChip('OVERDUE', label: 'Overdue', dense: true),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: checklist.stepsDone / checklist.steps.length,
                        minHeight: 6,
                        backgroundColor: bos.neutralSoft,
                        valueColor: AlwaysStoppedAnimation(
                          checklist.completed ? bos.success : bos.brand,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${checklist.stepsDone}/${checklist.steps.length}',
                    style: TextStyle(
                      color: bos.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (checklist.targetCompletionDate != null) ...[
                const SizedBox(height: 8),
                Text(
                  checklist.completed
                      ? 'Completed ${Fmt.date(checklist.completionDate)}'
                      : 'Due ${Fmt.date(checklist.targetCompletionDate)}',
                  style: TextStyle(
                    color: checklist.isOverdue ? bos.danger : bos.muted,
                    fontSize: 11.5,
                    fontWeight:
                        checklist.isOverdue ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
