import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/data_sync_service.dart';
import 'core/services/local_cache_service.dart';
import 'core/services/offline_credential_service.dart';
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

  // Offline-support services, all registered before the first frame:
  // - LocalCacheService: on-device store for the party/price/quotation/
  //   estimation/receipt lists.
  // - ConnectivityService: online/offline + real internet-reachability
  //   checks, used to decide whether login can happen offline.
  // - OfflineCredentialService: salted-hash credential store that gates
  //   offline login (populated on online login, cleared on logout).
  // - DataSyncService: pulls the lists down into LocalCacheService right
  //   after a successful online login.
  await Get.putAsync<LocalCacheService>(
    () => LocalCacheService().init(),
    permanent: true,
  );
  await Get.putAsync<ConnectivityService>(
    () => ConnectivityService().init(),
    permanent: true,
  );
  Get.put<OfflineCredentialService>(OfflineCredentialService(),
      permanent: true);
  Get.put<DataSyncService>(DataSyncService(), permanent: true);

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