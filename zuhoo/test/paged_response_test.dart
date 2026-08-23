import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/network/paged_response.dart';

/// Spring Data's `Page<T>` has been serialised three different ways across
/// Spring versions, and a page that silently parses as "page 0 of 0" turns
/// every paginated list in the app into a single page with no way to see the
/// rest — a bug that looks like missing data rather than a parsing failure.
void main() {
  Map<String, dynamic> item(int id) => {'id': id};
  int fromItem(Map<String, dynamic> json) => json['id'] as int;

  group('PagedResponse.fromJson', () {
    test('reads the flat shape the frontend normalises to', () {
      final page = PagedResponse.fromJson({
        'content': [item(1), item(2)],
        'totalElements': 12,
        'totalPages': 6,
        'currentPage': 1,
        'pageSize': 2,
      }, fromItem);

      expect(page.content, [1, 2]);
      expect(page.totalElements, 12);
      expect(page.totalPages, 6);
      expect(page.currentPage, 1);
      expect(page.pageSize, 2);
      expect(page.hasMore, isTrue);
    });

    test("reads Spring's own number/size spelling", () {
      final page = PagedResponse.fromJson({
        'content': [item(1)],
        'totalElements': 3,
        'totalPages': 3,
        'number': 2,
        'size': 1,
      }, fromItem);

      expect(page.currentPage, 2);
      expect(page.pageSize, 1);
      expect(page.hasMore, isFalse, reason: 'page 2 of 3 is the last one');
    });

    test('reads the newer nested page object', () {
      final page = PagedResponse.fromJson({
        'content': [item(1)],
        'page': {
          'totalElements': 9,
          'totalPages': 9,
          'number': 4,
          'size': 1,
        },
      }, fromItem);

      expect(page.totalElements, 9);
      expect(page.totalPages, 9);
      expect(page.currentPage, 4);
      expect(page.pageSize, 1);
    });

    test('treats a bare list as one complete page', () {
      final page = PagedResponse.fromJson([item(1), item(2), item(3)], fromItem);

      expect(page.content, [1, 2, 3]);
      expect(page.totalPages, 1);
      expect(page.hasMore, isFalse);
    });

    test('falls back to the requested page when the body omits it', () {
      final page = PagedResponse.fromJson(
        {'content': [item(1)]},
        fromItem,
        fallbackPage: 3,
        fallbackSize: 20,
      );

      // Reporting page 0 here would make an infinite-scroll list re-request
      // the first page forever.
      expect(page.currentPage, 3);
      expect(page.pageSize, 20);
    });

    test('survives a null or malformed body', () {
      expect(PagedResponse.fromJson(null, fromItem).content, isEmpty);
      expect(PagedResponse.fromJson('nonsense', fromItem).content, isEmpty);
      expect(
        PagedResponse.fromJson({'content': 'not a list'}, fromItem).content,
        isEmpty,
      );
    });
  });
}
