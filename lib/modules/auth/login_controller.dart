import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ncw_fireworks/data/respositories/auth_repository.dart';

import '../../core/network/api_exception.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/validators.dart';
import '../../data/models/auth/auth_session_model.dart';
import '../../routes/app_routes.dart';

class LoginController extends GetxController {
  LoginController({
    AuthRepository? authRepository,
    SessionService? sessionService,
  })  : _authRepository = authRepository ?? AuthRepository(),
        _sessionService = sessionService ?? Get.find<SessionService>();

  final AuthRepository _authRepository;
  final SessionService _sessionService;

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
      final result = await _authRepository.login(
        username: username,
        password: password,
      );

      _failedAttempts = 0;
      _lockedUntil = null;

      await _sessionService.saveSession(
        AuthSessionModel(
          userId: result.userId!,
          name: result.name ?? username,
          loggedInAt: DateTime.now(),
        ),
      );

      passwordCtrl.clear();
      Get.offAllNamed(AppRoutes.dashboard);
    } on InvalidCredentialsException catch (e) {
      _registerFailedAttempt();
      errorText.value = e.message;
    } on ApiException catch (e) {
      // Network/timeout/server/parsing failures — don't count these
      // against the lockout counter, they're not guessing attempts.
      errorText.value = e.message;
    } catch (_) {
      errorText.value = 'Something went wrong. Please try again.';
    } finally {
      isLoading.value = false;
    }
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