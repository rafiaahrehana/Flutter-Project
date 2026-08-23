import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/paged_response.dart';

/// One screen's worth of a paginated list, plus where it is up to.
@immutable
class PagedState<T> {
  const PagedState({
    this.items = const [],
    this.page = 0,
    this.totalPages = 0,
    this.loadingMore = false,
  });

  final List<T> items;
  final int page;
  final int totalPages;

  /// A further page is being fetched. Kept separate from the outer
  /// `AsyncValue` loading state so appending to a list never blanks the list
  /// the user is already reading.
  final bool loadingMore;

  bool get hasMore => page + 1 < totalPages;
  bool get isEmpty => items.isEmpty;

  PagedState<T> copyWith({
    List<T>? items,
    int? page,
    int? totalPages,
    bool? loadingMore,
  }) =>
      PagedState<T>(
        items: items ?? this.items,
        page: page ?? this.page,
        totalPages: totalPages ?? this.totalPages,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Load / refresh / append for any endpoint that returns a Spring `Page<T>`.
///
/// Written once because the alternative is writing the same twenty lines in
/// every list screen and getting the edge cases subtly different each time —
/// the ones that matter being: a failed "load more" must not discard the pages
/// already on screen, and a second tap while one is in flight must do nothing.
mixin PagedLoader<T> on AsyncNotifier<PagedState<T>> {
  /// Fetch one page. The only thing a subclass has to supply.
  Future<PagedResponse<T>> fetchPage(int page);

  Future<PagedState<T>> loadFirstPage() async {
    final result = await fetchPage(0);
    return PagedState<T>(
      items: result.content,
      page: result.currentPage,
      totalPages: result.totalPages,
    );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(loadFirstPage);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncValue.data(current.copyWith(loadingMore: true));
    try {
      final next = await fetchPage(current.page + 1);
      state = AsyncValue.data(
        current.copyWith(
          items: [...current.items, ...next.content],
          page: next.currentPage,
          totalPages: next.totalPages,
          loadingMore: false,
        ),
      );
    } catch (_) {
      // Keep what is already on screen and let the caller report the failure.
      // Replacing the state with an error would throw away several pages the
      // user has scrolled through because the next one did not arrive.
      state = AsyncValue.data(current.copyWith(loadingMore: false));
      rethrow;
    }
  }

  /// Replaces one item in place — for an action that returns the updated row
  /// and should not cost a full reload.
  void replaceItem(bool Function(T) matches, T updated) {
    final current = state.value;
    if (current == null) return;
    final index = current.items.indexWhere(matches);
    if (index < 0) return;
    state = AsyncValue.data(
      current.copyWith(items: [...current.items]..[index] = updated),
    );
  }

  /// Drops one item — for an action that removes the row from this list, such
  /// as deciding an approval that was only here because it was pending.
  void removeItem(bool Function(T) matches) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        items: current.items.where((item) => !matches(item)).toList(),
      ),
    );
  }
}
