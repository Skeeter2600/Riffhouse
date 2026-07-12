import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../audio/audio_handler.dart';
import '../audio/queue_notifier.dart';
import '../database/app_database.dart';
import '../main.dart'; // Import to access global singletons
import '../models/jellyfin_models.dart';
import '../services/cache_service.dart';
import '../services/jellyfin_service.dart';
import '../services/playlist_service.dart';
import 'database_provider.dart';

// ---------------------------------------------------------------------------
// AuthNotifier
// ---------------------------------------------------------------------------

class AuthNotifier extends StateNotifier<JellyfinUser?> {
  final Ref _ref;
  JellyfinService? _jellyfinService;

  AuthNotifier(this._ref) : super(null) {
    _restoreSession();
  }

  JellyfinService? get jellyfinService => _jellyfinService;

  /// Tries to restore a saved session from Drift on startup.
  Future<void> _restoreSession() async {
    final db = _ref.read(databaseProvider);
    final config = await db.getServerConfig();
    if (config == null) return;

    final service = JellyfinService(
      serverUrl: config.serverUrl,
      accessToken: config.accessToken,
      userId: config.userId,
    );

    // Update the global playlist service's connection config!
    globalPlaylistService.jellyfinService = service;

    _jellyfinService = service;
    state = JellyfinUser(
      id: config.userId,
      name: config.username,
      accessToken: config.accessToken,
      isAdmin: false,
    );
  }

  /// Authenticates against the Jellyfin server and saves the session.
  Future<bool> login(
      String serverUrl, String username, String password) async {
    final user =
        await JellyfinService.authenticate(serverUrl, username, password);
    if (user == null) return false;

    final service = JellyfinService(
      serverUrl: serverUrl,
      accessToken: user.accessToken,
      userId: user.id,
    );

    // Update the global playlist service's connection config!
    globalPlaylistService.jellyfinService = service;

    // Persist to Drift database.
    final db = _ref.read(databaseProvider);
    await db.saveServerConfig(ServerConfigsCompanion(
      serverUrl: Value(serverUrl),
      userId: Value(user.id),
      username: Value(user.name),
      accessToken: Value(user.accessToken),
    ));

    _jellyfinService = service;
    state = user;
    return true;
  }

  /// Clears the session and removes saved config from database.
  Future<void> logout() async {
    final db = _ref.read(databaseProvider);
    await db.clearServerConfig();

    // Reset the global playlist service to a stub connection
    final stub = JellyfinService(
      serverUrl: 'http://localhost',
      accessToken: '',
      userId: '',
    );
    globalPlaylistService.jellyfinService = stub;

    _jellyfinService = null;
    state = null;
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final authProvider =
    StateNotifierProvider<AuthNotifier, JellyfinUser?>((ref) {
  return AuthNotifier(ref);
});

/// Exposes the authenticated [JellyfinService], or throws if not logged in.
final jellyfinServiceProvider = Provider<JellyfinService?>((ref) {
  return ref.watch(authProvider.notifier).jellyfinService;
});

/// Exposes the [CacheService] singleton.
final cacheServiceProvider = Provider<CacheService>((ref) {
  return globalCacheService;
});

/// Exposes the [PlaylistService] singleton.
final playlistServiceProvider = Provider<PlaylistService>((ref) {
  ref.watch(authProvider); // trigger UI updates when auth changes
  return globalPlaylistService;
});

/// Re-export audio handler provider alias for convenience.
final audioHandlerProviderAlias = audioHandlerProvider;

/// Provider for [QueueState] — convenience alias.
final queueStateProvider = queueNotifierProvider;
