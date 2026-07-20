import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../core/services/data_sync_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/theme_controller.dart';
import 'app_drawer.dart';

class AppScaffold extends StatelessWidget {
  final String routeName;
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const AppScaffold({
    super.key,
    required this.routeName,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (Get.key.currentState?.canPop() ?? false) {
          Get.back();
        } else {
          SystemNavigator.pop(); // nothing left → exit like a normal app
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.midnight,
        drawer: AppDrawer(currentRoute: routeName),
        appBar: AppBar(
          title: Text(title),
          actions: [
            ...?actions,
            Obx(
              () => IconButton(
                tooltip: themeController.isDarkMode.value
                    ? 'Switch to light mode'
                    : 'Switch to dark mode',
                onPressed: themeController.toggleTheme,
                icon: Icon(
                  themeController.isDarkMode.value
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: floatingActionButton,
        body: Container(
          decoration: BoxDecoration(
            gradient: AppColors.backgroundGradient,
          ),
          child: SafeArea(
            child: Column(
              children: [
                const _SyncStatusBanner(),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin status strip at the top of every screen (shared via
/// [AppScaffold]), showing exactly what [DataSyncService] is syncing
/// right now — e.g. "Syncing quotations — Draft, page 2". Only visible
/// while a sync is actually running; disappears the moment it finishes,
/// with nothing left behind.
class _SyncStatusBanner extends StatelessWidget {
  const _SyncStatusBanner();

  @override
  Widget build(BuildContext context) {
    final dataSync = Get.find<DataSyncService>();

    return Obx(() {
      if (!dataSync.isSyncing.value) return const SizedBox.shrink();

      final status = dataSync.statusMessage.value;
      final text = status.isNotEmpty ? status : 'Syncing your data…';

      return Container(
        width: double.infinity,
        color: AppColors.gold.withOpacity(0.16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    });
  }
}
