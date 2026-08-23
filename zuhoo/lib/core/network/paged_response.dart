/// A page of results from a Spring Data `Page<T>` endpoint.
///
/// The backend serialises Spring's own shape, which uses `number`/`size` for
/// the current page and page size — and, on newer Spring versions, nests them
/// under a `page` object. `ApiService.getPaged()` in the Angular app normalises
/// all three spellings into one flat shape so no list screen has to care; this
/// is the same normalisation.
class PagedResponse<T> {
  const PagedResponse({
    required this.content,
    required this.totalElements,
    required this.totalPages,
    required this.currentPage,
    required this.pageSize,
  });

  final List<T> content;
  final int totalElements;
  final int totalPages;
  final int currentPage;
  final int pageSize;

  bool get isEmpty => content.isEmpty;
  bool get hasMore => currentPage + 1 < totalPages;

  const PagedResponse.empty()
      : content = const [],
        totalElements = 0,
        totalPages = 0,
        currentPage = 0,
        pageSize = 0;

  factory PagedResponse.fromJson(
    Object? json,
    T Function(Map<String, dynamic>) fromItem, {
    int fallbackPage = 0,
    int fallbackSize = 20,
  }) {
    // A few endpoints return a bare list where a page was expected. Treat it
    // as a single complete page rather than failing the screen.
    if (json is List) {
      final items = json
          .whereType<Map<String, dynamic>>()
          .map(fromItem)
          .toList(growable: false);
      return PagedResponse<T>(
        content: items,
        totalElements: items.length,
        totalPages: items.isEmpty ? 0 : 1,
        currentPage: 0,
        pageSize: items.length,
      );
    }

    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final nested = map['page'];
    final page = nested is Map<String, dynamic> ? nested : const <String, dynamic>{};

    int pick(String flat, String springKey, int fallback) {
      final value = map[flat] ?? map[springKey] ?? page[springKey];
      if (value is num) return value.toInt();
      return fallback;
    }

    final rawContent = map['content'];
    final items = rawContent is List
        ? rawContent.whereType<Map<String, dynamic>>().map(fromItem).toList(growable: false)
        : <T>[];

    return PagedResponse<T>(
      content: items,
      totalElements: pick('totalElements', 'totalElements', items.length),
      totalPages: pick('totalPages', 'totalPages', items.isEmpty ? 0 : 1),
      currentPage: pick('currentPage', 'number', fallbackPage),
      pageSize: pick('pageSize', 'size', fallbackSize),
    );
  }
}
