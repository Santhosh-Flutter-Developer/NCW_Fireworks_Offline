import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/responsive.dart';
import 'login_controller.dart';

class LoginView extends GetView<LoginController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    return Scaffold(
      backgroundColor: AppColors.midnightDeep,
      body: Stack(
        children: [
          _buildBackgroundBursts(),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: Obx(
                () => IconButton(
                  tooltip: themeController.isDarkMode.value
                      ? 'Switch to light mode'
                      : 'Switch to dark mode',
                  onPressed: themeController.toggleTheme,
                  icon: Icon(
                    themeController.isDarkMode.value
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.isTablet(context) ? 420 : 440,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLogo(),
                      const SizedBox(height: 28),
                      Text('NCW Fireworks', style: AppTextStyles.display),
                      const SizedBox(height: 6),
                      Text(
                        'Retail management, lit up right.',
                        style: AppTextStyles.body,
                      ),
                      const SizedBox(height: 36),
                      _buildLoginCard(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.4),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 40),
    );
  }

  Widget _buildLoginCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
      ),
      child: Obx(
        () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back', style: AppTextStyles.h2),
            const SizedBox(height: 4),
            Text('Sign in to continue', style: AppTextStyles.caption),
            const SizedBox(height: 24),
            Text('Username', style: AppTextStyles.caption),
            const SizedBox(height: 8),
            TextField(
              controller: controller.usernameCtrl,
              enabled: !controller.isLoading.value,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter your username',
                prefixIcon: Icon(Icons.person_outline_rounded,
                    color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 18),
            Text('Password', style: AppTextStyles.caption),
            const SizedBox(height: 8),
            TextField(
              controller: controller.passwordCtrl,
              enabled: !controller.isLoading.value,
              obscureText: controller.obscurePassword.value,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter your password',
                prefixIcon: Icon(Icons.lock_outline_rounded,
                    color: AppColors.textMuted),
                suffixIcon: IconButton(
                  onPressed: controller.togglePasswordVisibility,
                  icon: Icon(
                    controller.obscurePassword.value
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ),
              ),
              onSubmitted: (_) => controller.login(),
            ),
            if (controller.errorText.value != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: AppColors.danger, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      controller.isLockedOut
                          ? 'Too many failed attempts. Try again in ${controller.lockoutSecondsLeft.value}s.'
                          : controller.errorText.value!,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (controller.isLoading.value ||
                        controller.isLockedOut)
                    ? null
                    : controller.login,
                child: controller.isLoading.value
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.textOnGold,
                        ),
                      )
                    : const Text('Sign in'),
              ),
            ),
            if (controller.isLoading.value) ...[
              const SizedBox(height: 10),
              Obx(
                () => Center(
                  child: Text(
                    controller.syncStatus.value.isNotEmpty
                        ? controller.syncStatus.value
                        : 'Signing in…',
                    style: AppTextStyles.caption,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundBursts() {
    return Positioned.fill(
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
          ),
          Positioned(
            top: -60,
            left: -40,
            child: _burstCircle(180, AppColors.magenta.withOpacity(0.18)),
          ),
          Positioned(
            top: 120,
            right: -70,
            child: _burstCircle(220, AppColors.gold.withOpacity(0.15)),
          ),
          Positioned(
            bottom: -80,
            left: -50,
            child: _burstCircle(240, AppColors.ember.withOpacity(0.14)),
          ),
          Positioned(
            bottom: 40,
            right: -40,
            child: _burstCircle(150, AppColors.teal.withOpacity(0.12)),
          ),
        ],
      ),
    );
  }

  Widget _burstCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
        ),
      ),
    );
  }
}