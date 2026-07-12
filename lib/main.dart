import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'audio/audio_handler.dart';
import 'audio/queue_notifier.dart';
import 'providers/database_provider.dart';
import 'router/app_router.dart';
import 'services/cache_service.dart';
import 'services/database_service.dart';
import 'services/jellyfin_service.dart';
import 'services/playlist_service.dart';
import 'providers/auth_provider.dart';
import 'providers/library_provider.dart';
import 'models/jellyfin_models.dart';
import 'theme/app_theme.dart';

late final JellyfinAudioHandler globalAudioHandler;
late final PlaylistService globalPlaylistService;
late final CacheService globalCacheService;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Get Drift database instance.
  final db = DatabaseService.instance;

  // 2. Bootstrap minimal services needed by the audio handler at startup.
  globalCacheService = CacheService(db);
  await globalCacheService.init();
  
  final stubJellyfinService = JellyfinService(
    serverUrl: 'http://localhost',
    accessToken: '',
    userId: '',
  );
  globalPlaylistService = PlaylistService(db, stubJellyfinService);

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
