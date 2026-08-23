import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import '../support/chat_thread.dart';
import '../support/support_models.dart';
import '../support/ticket_card.dart';
import 'portal_repository.dart';

class PortalTicketsScreen extends ConsumerWidget {
  const PortalTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final controller = ref.read(clientTicketsProvider.notifier);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Help')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _raise(context, ref),
        backgroundColor: bos.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ask'),
      ),
      body: PagedListView<SupportTicket>(
        async: ref.watch(clientTicketsProvider),
        onRefresh: controller.refresh,
        onLoadMore: () => guardListAction(context, controller.loadMore),
        emptyIcon: Icons.chat_bubble_outline_rounded,
        emptyTitle: 'Nothing open',
        emptyMessage:
            'Ask a question and the team will reply here. You will see their '
            'answers in the same conversation.',
        errorMessage: 'Could not load your conversations.',
        itemBuilder: (context, ticket) => TicketCard(
          ticket: ticket,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PortalTicketDetailScreen(ticket: ticket),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _raise(BuildContext context, WidgetRef ref) async {
    final request = await showModalBottomSheet<CreateTicketRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AskSheet(),
    );
    if (request == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(clientTicketsProvider.notifier).raise(request);
      messenger.showSnackBar(
        const SnackBar(content: Text('Sent. The team will reply here.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send that just now.')),
      );
    }
  }
}

class PortalTicketDetailScreen extends ConsumerStatefulWidget {
  const PortalTicketDetailScreen({super.key, required this.ticket});

  final SupportTicket ticket;

  @override
  ConsumerState<PortalTicketDetailScreen> createState() =>
      _PortalTicketDetailScreenState();
}

class _PortalTicketDetailScreenState
    extends ConsumerState<PortalTicketDetailScreen> {
  final _composer = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(portalRepositoryProvider)
          .replyToTicket(widget.ticket.id, text);
      _composer.clear();
      ref.invalidate(clientTicketMessagesProvider(widget.ticket.id));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send that message.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final ticket = widget.ticket;
    final messages = ref.watch(clientTicketMessagesProvider(ticket.id));
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: Text(ticket.ticketNumber)),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async =>
            ref.invalidate(clientTicketMessagesProvider(ticket.id)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          ticket.title,
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      StatusChip(ticket.status),
                    ],
                  ),
                  if (ticket.description != null &&
                      ticket.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      ticket.description!,
                      style: TextStyle(
                        color: bos.textSecondary,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Raised ${Fmt.relative(ticket.createdAt)}',
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            if (ticket.resolutionNotes != null &&
                ticket.resolutionNotes!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              MessageBanner.success(ticket.resolutionNotes!),
            ],
            const SizedBox(height: 20),
            AppCard(
              child: messages.when(
                loading: () => const Loader(padding: 16),
                error: (error, _) => Text(
                  error is ApiException
                      ? error.message
                      : 'Could not load this conversation.',
                  style: TextStyle(color: bos.muted, fontSize: 13),
                ),
                data: (list) => ChatThread(
                  messages: list,
                  currentUserId: me?.id,
                  controller: _composer,
                  onSend: _send,
                  sending: _sending,
                  disabled: !ticket.isOpen,
                  disabledNotice: 'This conversation has been closed. Start a '
                      'new one if you still need help.',
                  placeholder: 'Reply',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AskSheet extends StatefulWidget {
  const _AskSheet();

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _priority = 'MEDIUM';

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ask for help',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              // A client is talking to the firm they hired, not to Zuhoo.
              // Naming the audience avoids a message aimed at the wrong desk.
              Text(
                'This goes to your account team.',
                style: TextStyle(color: bos.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'What is this about?'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: 'How urgent is it?',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                items: [
                  for (final priority in ticketPriorities)
                    DropdownMenuItem(
                      value: priority,
                      child: Text(Fmt.label(priority)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _priority = value ?? _priority),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tell us more',
                  alignLabelWithHint: true,
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'A little detail helps them answer first time.'
                    : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  if (!(_formKey.currentState?.validate() ?? false)) return;
                  Navigator.pop(
                    context,
                    CreateTicketRequest(
                      title: _title.text,
                      description: _description.text,
                      priority: _priority,
                    ),
                  );
                },
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Send'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
