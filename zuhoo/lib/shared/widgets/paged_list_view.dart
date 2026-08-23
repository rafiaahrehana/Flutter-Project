import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../paged_controller.dart';
import 'primitives.dart';

/// Renders a [PagedState] as a pull-to-refresh list with a "load older" footer.
///
/// Exists so the four states every list has — loading, failed, empty, and
/// populated-with-more-to-come — are drawn the same way everywhere, instead of
/// each screen inventing its own and getting one of them wrong.
class PagedListView<T> extends StatelessWidget {
  const PagedListView({
    super.key,
    required this.async,
    required this.itemBuilder,
    required this.onRefresh,
    required this.onLoadMore,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptyMessage,
    this.errorMessage = 'Could not load this list.',
    this.moreLabel = 'Load older',
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 90),
  });

  final AsyncValue<PagedState<T>> async;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;

  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;
  final String errorMessage;
  final String moreLabel;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return async.when(
      loading: () => const Loader(),
      error: (error, _) => ErrorState(
        message: error is ApiException ? error.message : errorMessage,
        onRetry: onRefresh,
      ),
      data: (state) {
        if (state.isEmpty) {
          // Still wrapped in a refreshable scrollable: an empty list is often
          // empty because something has not synced yet, and the first thing
          // anyone does is pull down on it.
          return RefreshIndicator(
            color: bos.brand,
            backgroundColor: bos.bgCard,
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 60),
                EmptyState(
                  icon: emptyIcon,
                  title: emptyTitle,
                  message: emptyMessage,
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: bos.brand,
          backgroundColor: bos.bgCard,
          onRefresh: onRefresh,
          child: ListView.separated(
            padding: padding,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: state.items.length + (state.hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index >= state.items.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: state.loadingMore
                      ? const Loader(padding: 8)
                      : OutlinedButton(
                          onPressed: onLoadMore,
                          child: Text(moreLabel),
                        ),
                );
              }
              return itemBuilder(context, state.items[index]);
            },
          ),
        );
      },
    );
  }
}

/// Runs a list action and reports failure without tearing the list down.
///
/// "Load older" failing should leave the pages already on screen alone and say
/// so in a snackbar — replacing the whole list with an error page because one
/// extra page did not arrive is a much worse trade.
Future<void> guardListAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not load any more.')),
    );
  }
}
