import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../../data/models/auth/auth_session_model.dart';

/// Persists the logged-in session in the platform's secure storage
/// (Keystore-backed EncryptedSharedPreferences on Android, Keychain on
/// iOS/macOS, DPAPI on Windows) — never in plain SharedPreferences.
///
/// Registered once as a permanent [GetxService] in `main()` before the
/// app starts, so [isLoggedIn] is known before the first frame decides
/// whether to route to `/login` or `/dashboard`.
class SessionService extends GetxService {
  SessionService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  static const _sessionKey = 'ncw_auth_session_v1';

  final Rxn<AuthSessionModel> currentSession = Rxn<AuthSessionModel>();

  bool get isLoggedIn => currentSession.value != null;

  Future<SessionService> init() async {
    await _restoreSession();
    return this;
  }

  Future<void> _restoreSession() async {
    try {
      final raw = await _storage.read(key: _sessionKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Malformed session payload');
      }
      currentSession.value = AuthSessionModel.fromJson(decoded);
    } catch (_) {
      // Corrupted, tampered, or outdated-shape session data — fail safe
      // by treating it as logged out instead of crashing on startup.
      await _storage.delete(key: _sessionKey);
      currentSession.value = null;
    }
  }

  Future<void> saveSession(AuthSessionModel session) async {
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode(session.toJson()),
    );
    currentSession.value = session;
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _sessionKey);
    currentSession.value = null;
  }
}