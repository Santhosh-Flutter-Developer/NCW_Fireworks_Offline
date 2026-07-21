import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/services/connectivity_service.dart';
import '../core/services/data_sync_service.dart';

class SyncActionButton extends StatelessWidget {
  final Future<void> Function() onSync;

  const SyncActionButton({super.key, required this.onSync});

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