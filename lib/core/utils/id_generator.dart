import 'dart:math';

/// Generates opaque, unique-enough id strings for records this app now
/// creates entirely offline (starting with Quotation, whose
/// `quotation_id` the server no longer assigns — the client sends one as
/// `edit_id` on create, and the server just stores whatever unique
/// string it's given).
///
/// The output deliberately looks like this API's existing server-issued
/// ids (a long lowercase hex string), even though the real encryption
/// scheme behind those doesn't matter here — the server only ever
/// compares this value for exact string equality, never decodes it.
class IdGenerator {
  static final Random _random = Random.secure();
  static const _hexChars = '0123456789abcdef';

  /// A fresh unique hex id, [length] characters long (default 90 —
  /// comfortably longer than any id this API hands out elsewhere, so
  /// collision odds are negligible).
  static String generate({int length = 90}) {
    return List.generate(
      length,
      (_) => _hexChars[_random.nextInt(_hexChars.length)],
    ).join();
  }
}