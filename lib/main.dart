import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'core/services/session_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'routes/app_pages.dart';
import 'routes/app_routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  Get.put(ThemeController(), permanent: true);

  // Restore any existing secure session BEFORE the first frame, so we
  // can route straight to the dashboard for an already-logged-in user
  // instead of flashing the login screen.
  final sessionService = await Get.putAsync<SessionService>(
    () => SessionService().init(),
    permanent: true,
  );

  runApp(
    NcwFireworksApp(
      initialRoute:
          sessionService.isLoggedIn ? AppRoutes.dashboard : AppRoutes.login,
    ),
  );
}

class NcwFireworksApp extends StatelessWidget {
  const NcwFireworksApp({super.key, required this.initialRoute});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'NCW Fireworks',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.current,
      initialRoute: initialRoute,
      getPages: AppPages.pages,
      defaultTransition: Transition.cupertino,
    );
  }
}