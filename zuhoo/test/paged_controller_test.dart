import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/network/paged_response.dart';
import 'package:zuhoo/shared/paged_controller.dart';

/// `PagedLoader` backs every list in the app, so a bug in it is a bug in all of
/// them at once — and its failure modes are quiet ones: a list that silently
/// stops at page one, or one that throws away three screens of scrolled content
/// because the fourth page did not arrive.
void main() {
  late _FakeSource source;

  ProviderContainer makeContainer() {
    source = _FakeSource();
    final container = ProviderContainer(
      overrides: [_sourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('PagedLoader', () {
    test('loads the first page', () async {
      final container = makeContainer();
      final state = await container.read(_listProvider.future);

      expect(state.items, ['0-a', '0-b']);
      expect(state.page, 0);
      expect(state.totalPages, 3);
      expect(state.hasMore, isTrue);
      expect(state.isEmpty, isFalse);
    });

    test('appends the next page rather than replacing', () async {
      final container = makeContainer();
      await container.read(_listProvider.future);

      await container.read(_listProvider.notifier).loadMore();

      final state = container.read(_listProvider).value!;
      expect(state.items, ['0-a', '0-b', '1-a', '1-b']);
      expect(state.page, 1);
      expect(source.calls, [0, 1]);
    });

    test('does nothing once the last page is loaded', () async {
      final container = makeContainer();
      await container.read(_listProvider.future);
      final notifier = container.read(_listProvider.notifier);

      await notifier.loadMore();
      await notifier.loadMore();
      expect(container.read(_listProvider).value!.hasMore, isFalse);

      await notifier.loadMore();
      expect(source.calls, [0, 1, 2],
          reason: 'a request past the end is a wasted round trip');
    });

    test('a second tap while one page is in flight is ignored', () async {
      final container = makeContainer();
      await container.read(_listProvider.future);
      source.delay = true;

      final notifier = container.read(_listProvider.notifier);
      final first = notifier.loadMore();
      final second = notifier.loadMore();
      source.release();
      await Future.wait([first, second]);

      expect(source.calls, [0, 1],
          reason: 'the same page must not be fetched and appended twice');
      expect(container.read(_listProvider).value!.items,
          ['0-a', '0-b', '1-a', '1-b']);
    });

    test('a failed page keeps everything already on screen', () async {
      final container = makeContainer();
      await container.read(_listProvider.future);
      source.failNext = true;

      await expectLater(
        container.read(_listProvider.notifier).loadMore(),
        throwsA(isA<StateError>()),
      );

      final state = container.read(_listProvider).value!;
      expect(state.items, ['0-a', '0-b'],
          reason: 'losing page two must not lose page one');
      expect(state.loadingMore, isFalse,
          reason: 'a stuck spinner would make the list look permanently busy');
      expect(container.read(_listProvider).hasError, isFalse);
    });

    test('refresh goes back to the first page', () async {
      final container = makeContainer();
      await container.read(_listProvider.future);
      await container.read(_listProvider.notifier).loadMore();

      await container.read(_listProvider.notifier).refresh();

      final state = container.read(_listProvider).value!;
      expect(state.items, ['0-a', '0-b']);
      expect(state.page, 0);
    });

    test('removeItem drops a row without a round trip', () async {
      final container = makeContainer();
      await container.read(_listProvider.future);

      container.read(_listProvider.notifier).removeItem((item) => item == '0-a');

      expect(container.read(_listProvider).value!.items, ['0-b']);
      expect(source.calls, [0]);
    });

    test('replaceItem swaps a row in place', () async {
      final container = makeContainer();
      await container.read(_listProvider.future);

      container
          .read(_listProvider.notifier)
          .replaceItem((item) => item == '0-b', 'edited');

      expect(container.read(_listProvider).value!.items, ['0-a', 'edited']);
    });

    test('an empty result is empty, not broken', () async {
      final container = makeContainer();
      source.empty = true;
      final state = await container.read(_listProvider.future);

      expect(state.isEmpty, isTrue);
      expect(state.hasMore, isFalse);
    });
  });
}

/// Three pages of two items each.
class _FakeSource {
  final calls = <int>[];
  bool failNext = false;
  bool empty = false;
  bool delay = false;

  Completer<void>? _gate;

  void release() {
    _gate?.complete();
    _gate = null;
  }

  Future<PagedResponse<String>> fetch(int page) async {
    if (delay) {
      _gate ??= Completer<void>();
      await _gate!.future;
    }
    calls.add(page);
    if (failNext) {
      failNext = false;
      throw StateError('page $page unavailable');
    }
    if (empty) return const PagedResponse<String>.empty();
    return PagedResponse<String>(
      content: ['$page-a', '$page-b'],
      totalElements: 6,
      totalPages: 3,
      currentPage: page,
      pageSize: 2,
    );
  }
}

final _sourceProvider = Provider<_FakeSource>(
  (ref) => throw UnimplementedError('overridden in tests'),
);

class _ListController extends AsyncNotifier<PagedState<String>>
    with PagedLoader<String> {
  @override
  Future<PagedState<String>> build() => loadFirstPage();

  @override
  Future<PagedResponse<String>> fetchPage(int page) =>
      ref.read(_sourceProvider).fetch(page);
}

final _listProvider =
    AsyncNotifierProvider<_ListController, PagedState<String>>(
  _ListController.new,
);
