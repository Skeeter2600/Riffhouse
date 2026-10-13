import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'audio/audio_handler.dart';
import 'audio/queue_notifier.dart';
import 'database/app_database.dart';
import 'providers/auth_provider.dart';
import 'providers/database_provider.dart';
import 'router/app_router.dart';
import 'services/cache_service.dart';
import 'services/favorites_store.dart';
import 'services/jellyfin_service.dart';
import 'services/playlist_service.dart';
import 'theme/app_theme.dart';
import 'utils/app_paths.dart';
import 'services/local_cover_store.dart';

late final JellyfinAudioHandler globalAudioHandler;
late final PlaylistService globalPlaylistService;
late final CacheService globalCacheService;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop installs used to keep their data in the Documents folder.
  await migrateLegacyDesktopData();

  await LocalCoverStore.init();

  // 1. Open the Drift database.
  final db = AppDatabase();

  // 2. Bootstrap minimal services needed by the audio handler at startup.
  globalCacheService = CacheService(db);
  await globalCacheService.init();
  
  // Restore the saved sign-in up front, so the audio handler (which Android
  // Auto can start without the UI) and the first frame both have it.
  await AuthNotifier.loadDeviceId();
  try {
    JellyfinService.appVersion = (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    // Keep the default
  }
  final savedSession = await db.getServerConfig();
  final initialService = savedSession == null
      ? MusicService.signedOut()
      : MusicService.create(
          type: ServerType.fromId(savedSession.serverType),
          serverUrl: savedSession.serverUrl,
          accessToken: savedSession.accessToken,
          userId: savedSession.userId,
        );
  globalPlaylistService = PlaylistService(db, initialService);
  await FavoritesStore.load(initialService);

  // 3. Register the audio handler with AudioService.
  globalAudioHandler = await AudioService.init(
    builder: () => JellyfinAudioHandler(
      cacheService: globalCacheService,
      playlistService: globalPlaylistService,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.riffhouse.audio',
      androidNotificationChannelName: 'Riffhouse',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_notification',
    ),
  );

  // 4. Launch the app with provider overrides.
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        savedSessionProvider.overrideWithValue(savedSession),
        audioHandlerProvider.overrideWithValue(globalAudioHandler),
      ],
      child: const RiffhouseApp(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Root app widget
// ---------------------------------------------------------------------------

class RiffhouseApp extends ConsumerWidget {
  const RiffhouseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Riffhouse',
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
