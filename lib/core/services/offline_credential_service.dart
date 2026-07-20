import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

/// The bits of a verified offline login we need to rebuild a real
/// [AuthSessionModel] without contacting the server.
class OfflineCredential {
  final String username;
  final String userId;
  final String name;

  const OfflineCredential({
    required this.username,
    required this.userId,
    required this.name,
  });
}

/// Lets the *same* device re-authenticate the *same* user without a
/// network round-trip, once they've logged in online at least once.
///
/// Stores only a salted hash of the password (never the password
/// itself) plus the `user_id`/`name` the login API returned, in the
/// platform's secure storage — same backing store as [SessionService].
///
/// The stored credential is the switch that decides whether offline
/// login is allowed at all:
/// - Saved on every successful *online* login.
/// - Cleared on logout — so, per the product requirement, logging out
///   always forces a live server login next time, while staying logged
///   in (even across app restarts, even if the login screen is somehow
///   reached again) keeps offline login available.
class OfflineCredentialService extends GetxService {
  OfflineCredentialService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  static const _key = 'ncw_offline_credential_v1';

  Future<void> save({
    required String username,
    required String password,
    required String userId,
    required String name,
  }) async {
    final salt = _generateSalt();
    final payload = {
      'username': username,
      'salt': salt,
      'hash': _hash(password, salt),
      'user_id': userId,
      'name': name,
    };
    await _storage.write(key: _key, value: jsonEncode(payload));
  }

  /// Checks [username]/[password] against whatever is stored, if
  /// anything. Returns `null` when there's no stored credential, the
  /// username doesn't match, or the password hash doesn't match — the
  /// caller can't tell which of those it was, by design, same as a
  /// normal "invalid username or password" response.
  Future<OfflineCredential?> verify({
    required String username,
    required String password,
  }) async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final storedUsername = decoded['username']?.toString() ?? '';
      final salt = decoded['salt']?.toString() ?? '';
      final storedHash = decoded['hash']?.toString() ?? '';

      if (storedUsername.trim().toLowerCase() !=
          username.trim().toLowerCase()) {
        return null;
      }
      if (_hash(password, salt) != storedHash) return null;

      return OfflineCredential(
        username: storedUsername,
        userId: decoded['user_id']?.toString() ?? '',
        name: decoded['name']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasStoredCredential() async {
    final raw = await _storage.read(key: _key);
    return raw != null && raw.isNotEmpty;
  }

  Future<void> clear() => _storage.delete(key: _key);

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  String _generateSalt() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }
}
