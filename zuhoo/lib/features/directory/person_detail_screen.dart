import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'directory_models.dart';
import 'directory_repository.dart';

/// One colleague.
///
/// Opened with the row that was tapped, so the name and photo are on screen
/// immediately and the fuller record fills in behind them. A directory lookup
/// is usually two seconds long — waiting on a spinner for the part the list
/// already knew would be most of that.
class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({super.key, required this.person});

  final Person person;

  static void open(BuildContext context, {required Person person}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PersonDetailScreen(person: person)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final full = ref.watch(personProvider(person.id));

    // The row we were opened with, upgraded to the full record once it lands.
    final shown = full.value ?? person;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Header(person: shown),
          const SizedBox(height: 18),
          _ContactActions(person: shown),
          if (full.hasError) ...[
            const SizedBox(height: 16),
            MessageBanner.info(
              full.error is ApiException
                  ? (full.error! as ApiException).message
                  : 'Could not load the rest of this profile.',
            ),
          ],
          const SizedBox(height: 20),
          _Details(person: shown, loading: full.isLoading),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      children: [
        Avatar(
          initials: person.initials,
          imageUrl: person.imageUrl,
          size: 88,
        ),
        const SizedBox(height: 12),
        Text(
          person.fullName,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: bos.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (person.roleLabel != null) ...[
          const SizedBox(height: 3),
          Text(
            person.roleLabel!,
            textAlign: TextAlign.center,
            style: TextStyle(color: bos.textSecondary, fontSize: 14),
          ),
        ],
        if (person.departmentName != null) ...[
          const SizedBox(height: 8),
          StatusChip(
            person.isFormer ? person.employmentStatus! : 'ACTIVE',
            label: person.departmentName,
            dense: true,
          ),
        ],
        if (person.isFormer) ...[
          const SizedBox(height: 12),
          MessageBanner.warning(
            'This person has left the company. Their contact details are kept '
            'for the record and may no longer reach them.',
          ),
        ],
      ],
    );
  }
}

/// Call and email, the two things a directory exists for.
class _ContactActions extends StatelessWidget {
  const _ContactActions({required this.person});

  final Person person;

  Future<void> _launch(BuildContext context, Uri uri, String failure) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final launched = await launchUrl(uri);
      if (!launched) {
        messenger.showSnackBar(SnackBar(content: Text(failure)));
      }
    } catch (_) {
      // A device with no dialer or no mail account configured — an emulator,
      // usually. Worth saying so rather than failing silently.
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = person.bestPhone;
    final email = person.bestEmail;

    if (phone == null && email == null) {
      return const AppCard(
        child: MessageBanner.info(
          'No contact details are recorded for this person.',
        ),
      );
    }

    return Row(
      children: [
        if (phone != null)
          Expanded(
            child: _ActionButton(
              icon: Icons.call_rounded,
              label: 'Call',
              onTap: () => _launch(
                context,
                Uri(scheme: 'tel', path: phone),
                'No app on this device can place a call.',
              ),
            ),
          ),
        if (phone != null && email != null) const SizedBox(width: 10),
        if (email != null)
          Expanded(
            child: _ActionButton(
              icon: Icons.mail_outline_rounded,
              label: 'Email',
              onTap: () => _launch(
                context,
                Uri(scheme: 'mailto', path: email),
                'No mail app is set up on this device.',
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.person, required this.loading});

  final Person person;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final rows = <({String label, String? value, IconData icon})>[
      (
        label: 'Work email',
        value: person.officialEmail,
        icon: Icons.alternate_email_rounded
      ),
      (
        label: 'Work phone',
        value: person.workPhone,
        icon: Icons.phone_outlined
      ),
      (
        label: 'Department',
        value: person.departmentName,
        icon: Icons.account_tree_outlined
      ),
      (
        label: 'Designation',
        value: person.designationName,
        icon: Icons.workspace_premium_outlined
      ),
      (
        label: 'Reporting to',
        value: person.reportingManagerName,
        icon: Icons.supervisor_account_outlined
      ),
      (
        label: 'Office',
        value: person.officeLocation,
        icon: Icons.location_on_outlined
      ),
      (label: 'Shift', value: person.shiftName, icon: Icons.schedule_outlined),
      (
        label: 'Employee number',
        value: person.employeeNumber,
        icon: Icons.badge_outlined
      ),
      (
        label: 'Employment',
        value: person.employmentType == null
            ? null
            : Fmt.label(person.employmentType),
        icon: Icons.work_outline_rounded
      ),
      (
        label: 'Joined',
        value: person.hireDate == null ? null : Fmt.date(person.hireDate),
        icon: Icons.event_outlined
      ),
    ].where((r) => r.value != null && r.value!.trim().isNotEmpty).toList();

    if (rows.isEmpty) {
      return loading ? const Loader() : const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Details', icon: Icons.badge_outlined),
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
        if (loading) ...[
          const SizedBox(height: 10),
          const Loader(padding: 4),
        ],
      ],
    );
  }
}
