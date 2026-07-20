/// Small helpers shared by every repository's offline (cache-backed) list
/// fallback. Online, filtering/sorting/paging all happen server-side;
/// offline, a repository loads the *entire* cached snapshot for the
/// relevant tab and has to reproduce that same filtering itself before
/// slicing out the requested page.
library offline_filter_utils;

/// Case-insensitive "does [haystack] contain [needle] anywhere" check.
/// An empty/blank [needle] always matches (mirrors the server treating a
/// blank `search_text` as "no filter").
bool matchesSearch(String needle, List<String> haystacks) {
  final q = needle.trim().toLowerCase();
  if (q.isEmpty) return true;
  return haystacks.any((h) => h.toLowerCase().contains(q));
}

/// Whether a `yyyy-MM-dd` [dateStr] falls within [fromDate]/[toDate]
/// (also `yyyy-MM-dd`, or blank for "no bound"), matching the server's
/// inclusive `BETWEEN`-style date filtering. Falls back to "match" if
/// [dateStr] can't be parsed, so a malformed cached date never silently
/// disappears from an offline list.
bool matchesDateRange(String dateStr, String fromDate, String toDate) {
  if (fromDate.isEmpty && toDate.isEmpty) return true;
  final date = DateTime.tryParse(dateStr);
  if (date == null) return true;

  if (fromDate.isNotEmpty) {
    final from = DateTime.tryParse(fromDate);
    if (from != null && date.isBefore(from)) return false;
  }
  if (toDate.isNotEmpty) {
    final to = DateTime.tryParse(toDate);
    if (to != null && date.isAfter(to)) return false;
  }
  return true;
}

/// Whether an [id] matches a `filter_*_id` value, where an empty filter
/// means "no filter" (matches everything).
bool matchesId(String id, String filterId) =>
    filterId.isEmpty || id == filterId;

/// Slices [items] the same way the server's `page_number`/`page_limit`
/// would, returning an empty list past the end rather than throwing.
/// If either [pageNumber] or [pageLimit] is omitted, no slicing happens
/// at all — the full list is returned, mirroring how the online request
/// behaves once `page_number`/`page_limit` aren't sent.
List<T> paginate<T>(List<T> items, int? pageNumber, int? pageLimit) {
  if (pageNumber == null || pageLimit == null) return items;
  if (pageLimit <= 0) return const [];
  final start = (pageNumber - 1) * pageLimit;
  if (start < 0 || start >= items.length) return const [];
  final end = (start + pageLimit).clamp(0, items.length);
  return items.sublist(start, end);
}