import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
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
          child: SafeArea(child: body),
        ),
      ),
    );
  }
}
