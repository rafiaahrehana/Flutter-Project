import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'notification_repository.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(notificationsControllerProvider);
    final hasUnread = async.value?.hasUnread ?? false;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () => _markAll(context, ref),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load your notifications.',
          onRetry: () =>
              ref.read(notificationsControllerProvider.notifier).refresh(),
        ),
        data: (state) {
          if (state.items.isEmpty) {
            return RefreshIndicator(
              color: bos.brand,
              onRefresh: () =>
                  ref.read(notificationsControllerProvider.notifier).refresh(),
              child: ListView(
                children: const [
                  SizedBox(height: 60),
                  EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'Nothing new',
                    message:
                        'Approvals, announcements and payroll updates will '
                        'appear here.',
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: bos.brand,
            backgroundColor: bos.bgCard,
            onRefresh: () =>
                ref.read(notificationsControllerProvider.notifier).refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemCount: state.items.length + (state.hasMore ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index >= state.items.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: state.loadingMore
                        ? const Loader(padding: 8)
                        : OutlinedButton(
                            onPressed: () => ref
                                .read(notificationsControllerProvider.notifier)
                                .loadMore(),
                            child: const Text('Load older'),
                          ),
                  );
                }
                return _NotificationTile(notification: state.items[index]);
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _markAll(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationsControllerProvider.notifier).markAllRead();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final unread = !notification.read;

    return AppCard(
      // Unread rows sit on the brand tint. A dot alone is easy to miss on a
      // phone held at arm's length; the whole row changing is not.
      color: unread ? bos.brandSoft : bos.bgCard,
      onTap: unread
          ? () => ref
              .read(notificationsControllerProvider.notifier)
              .markRead(notification.id)
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3),
            height: 8,
            width: 8,
            decoration: BoxDecoration(
              color: unread ? bos.brand : Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 14.5,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                if (notification.message.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    notification.message,
                    style: TextStyle(
                      color: bos.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  Fmt.relative(notification.createdAt),
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
