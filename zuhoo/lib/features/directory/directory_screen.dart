import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'directory_models.dart';
import 'directory_repository.dart';
import 'person_detail_screen.dart';

/// Who works here.
///
/// Gated on EMPLOYEE_VIEW to match the web app. The API would serve any
/// employee — see [DirectoryPermissions.employeeView] for why that difference
/// is not taken as licence to open it up here.
class DirectoryScreen extends ConsumerWidget {
  const DirectoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('People')),
        body: const Loader(),
      );
    }

    if (!permissions.has(DirectoryPermissions.employeeView)) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('People')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Browsing colleagues needs the employee directory permission. '
              'Your HR team can grant it.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('People')),
      body: Column(
        children: [
          const _SearchField(),
          const _DepartmentFilter(),
          Expanded(
            child: PagedListView<Person>(
              async: ref.watch(directoryProvider),
              onRefresh: () => ref.read(directoryProvider.notifier).refresh(),
              onLoadMore: () => ref.read(directoryProvider.notifier).loadMore(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              emptyTitle: 'Nobody here',
              emptyMessage:
                  'No colleague matches that. Try a different name or clear '
                  'the filters.',
              emptyIcon: Icons.person_search_outlined,
              errorMessage: 'Could not load the directory.',
              itemBuilder: (context, person) => _PersonRow(person: person),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Debounced, because every change to the term restarts a paged request.
  /// Typing a six-letter name would otherwise fire six searches and let an
  /// earlier, slower one land last.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(directorySearchProvider.notifier).set(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onChanged: _onChanged,
        onSubmitted: (value) {
          _debounce?.cancel();
          ref.read(directorySearchProvider.notifier).set(value);
        },
        decoration: InputDecoration(
          hintText: 'Search by name',
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: bos.muted),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: bos.muted),
                  onPressed: () {
                    _controller.clear();
                    _debounce?.cancel();
                    ref.read(directorySearchProvider.notifier).set('');
                    setState(() {});
                  },
                  tooltip: 'Clear',
                ),
          isDense: true,
        ),
      ),
    );
  }
}

class _DepartmentFilter extends ConsumerWidget {
  const _DepartmentFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departments = ref.watch(departmentsProvider).value ?? const [];
    if (departments.isEmpty) return const SizedBox.shrink();

    final selected = ref.watch(departmentFilterProvider);

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: departments.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _Chip(
              label: 'Everyone',
              active: selected == null,
              onTap: () => ref.read(departmentFilterProvider.notifier).set(null),
            );
          }
          final department = departments[i - 1];
          final count = department.employeeCount;
          return _Chip(
            label: count == null || count == 0
                ? department.name
                : '${department.name} · $count',
            active: selected == department.id,
            onTap: () => ref
                .read(departmentFilterProvider.notifier)
                .set(selected == department.id ? null : department.id),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? bos.brand : bos.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? bos.brand : bos.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : bos.textSecondary,
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => PersonDetailScreen.open(context, person: person),
        child: AppCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Avatar(
                initials: person.initials,
                imageUrl: person.imageUrl,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            person.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (person.isFormer) ...[
                          const SizedBox(width: 6),
                          StatusChip(
                            person.employmentStatus!,
                            label: 'Left',
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                    if (person.roleLabel != null)
                      Text(
                        person.roleLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    if (person.departmentName != null)
                      Text(
                        person.departmentName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: bos.muted, fontSize: 11.5),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: bos.muted),
            ],
          ),
        ),
      ),
    );
  }
}
