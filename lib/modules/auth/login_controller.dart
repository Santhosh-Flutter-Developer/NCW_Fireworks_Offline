import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ncw_fireworks/data/respositories/auth_repository.dart';

import '../../core/network/api_exception.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/data_sync_service.dart';
import '../../core/services/offline_credential_service.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/validators.dart';
import '../../data/models/auth/auth_session_model.dart';
import '../../routes/app_routes.dart';

class LoginController extends GetxController {
  LoginController({
    AuthRepository? authRepository,
    SessionService? sessionService,
    ConnectivityService? connectivityService,
    OfflineCredentialService? offlineCredentialService,
    DataSyncService? dataSyncService,
  })  : _authRepository = authRepository ?? AuthRepository(),
        _sessionService = sessionService ?? Get.find<SessionService>(),
        _connectivityService =
            connectivityService ?? Get.find<ConnectivityService>(),
        _offlineCredentialService =
            offlineCredentialService ?? Get.find<OfflineCredentialService>(),
        _dataSyncService = dataSyncService ?? Get.find<DataSyncService>();

  final AuthRepository _authRepository;
  final SessionService _sessionService;
  final ConnectivityService _connectivityService;
  final OfflineCredentialService _offlineCredentialService;
  final DataSyncService _dataSyncService;

  /// Mirrors [DataSyncService.statusMessage] so the login screen can show
  /// what's happening while the post-login sync runs, without the view
  /// needing to know about [DataSyncService] directly.
  RxString get syncStatus => _dataSyncService.statusMessage;

  final usernameCtrl = TextEditingController(text: '');
  final passwordCtrl = TextEditingController(text: '');

  final obscurePassword = true.obs;
  final isLoading = false.obs;
  final errorText = RxnString();

  /// Simple client-side brake against rapid-fire credential guessing.
  /// This is a UX/abuse-mitigation measure, not a substitute for
  /// server-side rate limiting, which the backend should also enforce.
  static const _maxAttempts = 5;
  static const _lockoutDuration = Duration(seconds: 30);
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  final lockoutSecondsLeft = 0.obs;
  Timer? _lockoutTimer;

  bool get isLockedOut => lockoutSecondsLeft.value > 0;

  void togglePasswordVisibility() {
    obscurePassword.value = !obscurePassword.value;
  }

  Future<void> login() async {
    if (isLoading.value) return;

    errorText.value = null;

    if (_isCurrentlyLockedOut) {
      errorText.value =
          'Too many failed attempts. Try again in ${lockoutSecondsLeft.value}s.';
      return;
    }

    final username = usernameCtrl.text.trim();
    final password = passwordCtrl.text;

    final usernameError = Validators.username(username);
    if (usernameError != null) {
      errorText.value = usernameError;
      return;
    }

    final passwordError = Validators.password(password);
    if (passwordError != null) {
      errorText.value = passwordError;
      return;
    }

    isLoading.value = true;
    try {
      // Real internet-reachability check (not just "a Wi-Fi/mobile
      // interface is up") decides which path we take. First-ever login
      // on a device always needs this to succeed, since there's no
      // offline credential yet to fall back on.
      final online = await _connectivityService.hasInternetAccess();
      if (online) {
        await _loginOnline(username: username, password: password);
      } else {
        await _loginOffline(username: username, password: password);
      }
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _loginOnline({
    required String username,
    required String password,
  }) async {
    try {
      final result = await _authRepository.login(
        username: username,
        password: password,
      );

      _failedAttempts = 0;
      _lockedUntil = null;

      final session = AuthSessionModel(
        userId: result.userId!,
        name: result.name ?? username,
        loggedInAt: DateTime.now(),
      );
      await _sessionService.saveSession(session);

      // Remember this login for offline use next time, and pull down
      // the party/price/quotation/estimation/receipt lists while we
      // still have a connection. syncAll() swallows its own errors —
      // it never blocks getting into the app.
      await _offlineCredentialService.save(
        username: username,
        password: password,
        userId: session.userId,
        name: session.name,
      );

      passwordCtrl.clear();
      await _dataSyncService.syncAll();
      Get.offAllNamed(AppRoutes.dashboard);
    } on InvalidCredentialsException catch (e) {
      _registerFailedAttempt();
      errorText.value = e.message;
    } on NetworkException {
      // Connectivity dropped between our pre-check and the actual
      // request — fall back to an offline login attempt instead of
      // just failing outright.
      await _loginOffline(
        username: username,
        password: password,
        connectionDroppedMidRequest: true,
      );
    } on ApiException catch (e) {
      // Timeout/server/parsing failures — don't count these against the
      // lockout counter, they're not guessing attempts.
      errorText.value = e.message;
    } catch (_) {
      errorText.value = 'Something went wrong. Please try again.';
    }
  }

  Future<void> _loginOffline({
    required String username,
    required String password,
    bool connectionDroppedMidRequest = false,
  }) async {
    final credential = await _offlineCredentialService.verify(
      username: username,
      password: password,
    );

    if (credential == null) {
      _registerFailedAttempt();
      errorText.value = connectionDroppedMidRequest
          ? 'Lost connection while signing in, and no offline account is '
              'saved on this device yet. Please reconnect and try again.'
          : 'No internet connection. Connect to the internet and sign in '
              'at least once before you can log in offline.';
      return;
    }

    _failedAttempts = 0;
    _lockedUntil = null;

    await _sessionService.saveSession(
      AuthSessionModel(
        userId: credential.userId,
        name: credential.name,
        loggedInAt: DateTime.now(),
      ),
    );

    passwordCtrl.clear();
    Get.offAllNamed(AppRoutes.dashboard);
  }

  bool get _isCurrentlyLockedOut =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  void _registerFailedAttempt() {
    _failedAttempts++;
    if (_failedAttempts >= _maxAttempts) {
      _lockedUntil = DateTime.now().add(_lockoutDuration);
      _startLockoutCountdown();
    }
  }

  void _startLockoutCountdown() {
    _lockoutTimer?.cancel();
    lockoutSecondsLeft.value = _lockoutDuration.inSeconds;
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining =
          _lockedUntil?.difference(DateTime.now()).inSeconds ?? 0;
      if (remaining <= 0) {
        lockoutSecondsLeft.value = 0;
        _failedAttempts = 0;
        _lockedUntil = null;
        timer.cancel();
      } else {
        lockoutSecondsLeft.value = remaining;
      }
    });
  }

  @override
  void onClose() {
    _lockoutTimer?.cancel();
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    super.onClose();
  }
}