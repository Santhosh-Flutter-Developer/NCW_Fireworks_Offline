import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';

import '../constants/api_endpoints.dart';

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
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      isOnline.value = _hasInterface(result);
    });
    return this;
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
