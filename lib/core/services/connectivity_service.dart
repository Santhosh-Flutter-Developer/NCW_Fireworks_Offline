import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../constants/api_endpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Tracks whether the device currently has network access.
///
/// Exposes two things, deliberately kept separate:
/// - [isOnline] — a cheap, reactive "is a Wi-Fi/mobile interface up"
///   signal, suitable for driving an "offline" banner in the UI.
/// - [hasInternetAccess] — a slower, authoritative check (a real DNS
///   lookup against the API host) used to actually gate anything that
///   needs the network, e.g. login and the post-login data sync. An
///   interface being "up" doesn't mean it has real internet (captive
///   portals, no data balance, DNS-only walled gardens, etc.), so login
///   should never trust [isOnline] alone.
///
/// Registered once as a permanent [GetxService] in `main()`.
class ConnectivityService extends GetxService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  final isOnline = true.obs;

  Future<ConnectivityService> init() async {
    final initial = await _connectivity.checkConnectivity();
    isOnline.value = _hasInterface(initial);
    if (!isOnline.value) {
      // App is launching without a connection — wait for the first
      // frame so GetMaterialApp's overlay actually exists before we try
      // to pop a snackbar on it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOfflineToast());
    }
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final nowOnline = _hasInterface(result);
      // Only toast on the actual online→offline transition — not on
      // every reconnect blip, and not repeatedly while already offline.
      if (isOnline.value && !nowOnline) {
        _showOfflineToast();
      }
      isOnline.value = nowOnline;
    });
    return this;
  }

  void _showOfflineToast() {
    Get.closeAllSnackbars();
    Get.snackbar(
      '',
      '',
      titleText: const SizedBox.shrink(),
      messageText: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.wifi_off_rounded,
              size: 18,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("You're offline", style: AppTextStyles.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  'Showing saved data until you reconnect',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.surfaceHigh,
      boxShadows: [
        BoxShadow(
          color: Colors.black.withOpacity(0.25),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
      borderRadius: 14,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
      isDismissible: true,
      forwardAnimationCurve: Curves.easeOutCubic,
      reverseAnimationCurve: Curves.easeInCubic,
    );
  }

  bool _hasInterface(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  /// Real internet-reachability check with a short timeout. Safe to call
  /// as often as needed (e.g. right before login) — it does nothing
  /// persistent, just a DNS lookup.
  Future<bool> hasInternetAccess({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final interfaceResult = await _connectivity.checkConnectivity();
    if (!_hasInterface(interfaceResult)) return false;

    // Browser sandboxes don't allow raw DNS/socket access — that's what
    // dart:io's InternetAddress.lookup needs — so it always throws on
    // Flutter Web and would otherwise make every web login look
    // "offline" even with a perfectly good connection. The interface
    // check above (backed by the browser's navigator.onLine) is as
    // authoritative a signal as a web app gets, so that's the answer.
    if (kIsWeb) return true;

    try {
      final host = Uri.parse(ApiEndpoints.baseUrl).host;
      final lookup = await InternetAddress.lookup(host).timeout(timeout);
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}