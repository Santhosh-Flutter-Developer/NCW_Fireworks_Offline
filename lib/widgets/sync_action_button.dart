import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/services/connectivity_service.dart';
import '../core/services/data_sync_service.dart';

/// AppBar action that lets the user manually trigger a single module's
/// sync — refreshing just that screen's slice of the offline cache (e.g.
/// tapping it on the Quotation screen only re-syncs quotations, not
/// Party/Price List/Estimation/Receipt too). The one-shot sync of
/// *everything* still only happens automatically right after login (see
/// `DataSyncService.syncAll`, called from `LoginController`).
///
/// Only ever visible while [ConnectivityService.isOnline] is true. There's
/// nothing a sync can do without a connection, and showing the button then
/// would just invite a tap that silently fails — so it's hidden entirely
/// (not just disabled/greyed out) the moment connectivity drops, and comes
/// back the instant the device reconnects.
///
/// Drop this into any screen's `AppScaffold(actions: [...])`, passing that
/// screen's own single-module sync method (e.g.
/// `SyncActionButton(onSync: dataSync.syncQuotations)`).
class SyncActionButton extends StatelessWidget {
  /// The single-module sync to run — one of `DataSyncService`'s
  /// `syncParty` / `syncPriceList` / `syncQuotations` / `syncEstimations` /
  /// `syncReceipts` methods.
  final Future<void> Function() onSync;

  /// Optional: called after the sync finishes (success or failure) — e.g.
  /// so the list screen can reload its current page from the freshly
  /// synced data. Safe to leave null.
  final VoidCallback? onSynced;

  const SyncActionButton({super.key, required this.onSync, this.onSynced});

  @override
  Widget build(BuildContext context) {
    final connectivity = Get.find<ConnectivityService>();
    final dataSync = Get.find<DataSyncService>();

    return Obx(() {
      // No connection → no button. Nothing useful a manual sync can do
      // offline, so it simply isn't shown rather than being disabled.
      if (!connectivity.isOnline.value) return const SizedBox.shrink();

      final syncing = dataSync.isSyncing.value;

      return IconButton(
        tooltip: 'Sync now',
        onPressed: syncing
            ? null
            : () async {
                await onSync();
                final error = dataSync.lastError.value;
                Get.snackbar(
                  error != null ? 'Sync incomplete' : 'Synced',
                  error != null
                      ? 'Some data may not have refreshed. Try again in a moment.'
                      : 'Your offline data is up to date.',
                  snackPosition: SnackPosition.BOTTOM,
                );
                onSynced?.call();
              },
        icon: syncing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.sync_rounded),
      );
    });
  }
}