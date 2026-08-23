import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';
import '../directory/directory_models.dart';
import '../directory/directory_repository.dart';

/// Picks a colleague, for handing them a laptop or a licence seat.
///
/// Talks to the directory repository directly rather than going through the
/// People screen's provider, because the entitlement here is different: the
/// permission that matters is HARDWARE_UPDATE or SOFTWARE_LICENSE_ASSIGN, and
/// somebody who can assign a machine plainly needs to see who to assign it to.
/// It shows names and departments only — [Person] maps nothing else.
class EmployeePicker extends ConsumerStatefulWidget {
  const EmployeePicker({super.key, required this.title});

  final String title;

  /// Returns the chosen colleague, or null if dismissed.
  static Future<Person?> show(BuildContext context, {required String title}) =>
      showModalBottomSheet<Person>(
        context: context,
        isScrollControlled: true,
        builder: (_) => EmployeePicker(title: title),
      );

  @override
  ConsumerState<EmployeePicker> createState() => _EmployeePickerState();
}

class _EmployeePickerState extends ConsumerState<EmployeePicker> {
  final _search = TextEditingController();
  Timer? _debounce;

  List<Person> _results = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final term = _search.text.trim();
      final page = await ref.read(directoryRepositoryProvider).people(
            search: term.isEmpty ? null : term,
            size: 30,
          );
      if (!mounted) return;
      setState(() {
        // Somebody who has left should not be handed a new machine.
        _results = page.content.where((p) => !p.isFormer).toList(growable: false);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the employee list.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              height: 4,
              width: 38,
              decoration: BoxDecoration(
                color: bos.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _search,
                    autofocus: true,
                    onChanged: _onChanged,
                    decoration: const InputDecoration(
                      labelText: 'Search by name',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_loading) return const Loader();
                  if (_error != null) {
                    return ErrorState(message: _error!, onRetry: _load);
                  }
                  if (_results.isEmpty) {
                    return const EmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'Nobody found',
                      message: 'No current employee matches that.',
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final person = _results[i];
                      return ListTile(
                        leading: Avatar(
                          initials: person.initials,
                          imageUrl: person.imageUrl,
                          size: 36,
                        ),
                        title: Text(person.fullName),
                        subtitle: Text(
                          [person.roleLabel, person.departmentName]
                              .where((s) => s != null && s.isNotEmpty)
                              .join(' · '),
                        ),
                        onTap: () => Navigator.pop(context, person),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
