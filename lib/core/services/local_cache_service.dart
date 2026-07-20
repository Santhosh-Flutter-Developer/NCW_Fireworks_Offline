import 'dart:convert';

import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Thin on-device cache for everything the app needs to keep working
/// without internet: party / price / quotation / estimation / receipt
/// lists, keyed by the constants in [CacheKeys].
///
/// Backed by a single Hive box of JSON strings rather than typed Hive
/// objects — the response models already have `fromJson` parsers, so
/// storing plain JSON lets a future "read cache, fall back to API" layer
/// reuse those same parsers instead of maintaining a second set of Hive
/// adapters that would drift out of sync with the API shape.
///
/// Registered once as a permanent [GetxService] in `main()`, alongside
/// [SessionService], so it's ready before the first frame.
class LocalCacheService extends GetxService {
  static const _boxName = 'ncw_offline_cache_v1';

  late final Box<String> _box;

  Future<LocalCacheService> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
    return this;
  }

  /// Stores a list of already-`fromJson`-shaped rows under [key],
  /// completely replacing whatever was cached there before.
  Future<void> putJsonList(String key, List<Map<String, dynamic>> items) {
    return _box.put(key, jsonEncode(items));
  }

  /// Reads back a list stored via [putJsonList]. Returns an empty list —
  /// never throws — for a missing key or corrupted payload, so callers
  /// can treat "no cache yet" and "cache unreadable" the same way.
  List<Map<String, dynamic>> getJsonList(String key) {
    final raw = _box.get(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {
      // Corrupted/old-shape payload — treat as empty rather than crash.
    }
    return const [];
  }

  Future<void> putString(String key, String value) => _box.put(key, value);

  String? getString(String key) => _box.get(key);

  /// Whether *any* list data has ever been synced — used to tell "brand
  /// new install, never synced" apart from "synced before, just empty".
  bool get hasAnyCachedData => _box.isNotEmpty;

  /// Wipes every cached list. Not called on logout by default (cached
  /// reference data isn't sensitive and re-login just refreshes it), but
  /// available for a "clear offline data" setting later.
  Future<void> clearAll() => _box.clear();
}
