import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';


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
  ///
  /// Verifies the stored token against the server before trusting it.
  /// If the token has been invalidated (401 — server restart, admin action, etc.),
  /// the stale credentials are cleared and the user is redirected to /login.
  /// All local listening data (play counts, history, etc.) is preserved.
  Future<void> _restoreSession() async {
    debugPrint('[AuthNotifier._restoreSession] Starting session restore...');
    final db = _ref.read(databaseProvider);
    final config = await db.getServerConfig();
    if (config == null) {
      debugPrint('[AuthNotifier._restoreSession] No saved config found → not logged in');
      return;
    }
    debugPrint('[AuthNotifier._restoreSession] Found config: serverUrl=${config.serverUrl}, userId=${config.userId}, username=${config.username}');

    final service = JellyfinService(
      serverUrl: config.serverUrl,
      accessToken: config.accessToken,
      userId: config.userId,
    );

    // Verify the stored token is still accepted by the server before trusting it.
    // A 401 here means the session was invalidated (server restart, admin logout, etc.).
    final valid = await service.verifySession();
    if (!valid) {
      debugPrint('[AuthNotifier._restoreSession] Token INVALID (401) — clearing stale credentials and redirecting to login');
      await db.clearServerConfig();
      return; // state stays null → GoRouter redirects to /login
    }

    // Update the global playlist service's connection config.
    globalPlaylistService.jellyfinService = service;

    _jellyfinService = service;
    state = JellyfinUser(
      id: config.userId,
      name: config.username,
      accessToken: config.accessToken,
      isAdmin: false,
    );
    debugPrint('[AuthNotifier._restoreSession] Session restored! userId=${config.userId}, state now non-null');
  }

  /// Authenticates against the Jellyfin server and saves the session.
  Future<bool> login(
      String serverUrl, String username, String password) async {
    debugPrint('[AuthNotifier.login] Attempting login to $serverUrl as $username');
    final user =
        await JellyfinService.authenticate(serverUrl, username, password);
    if (user == null) {
      debugPrint('[AuthNotifier.login] Authentication failed');
      return false;
    }
    debugPrint('[AuthNotifier.login] Login succeeded: userId=${user.id}');

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
  /// Called from the Settings screen on manual logout.
  Future<void> logout() async {
    debugPrint('[AuthNotifier.logout] Logging out...');
    final db = _ref.read(databaseProvider);
    await db.clearServerConfig();

    // Reset the global playlist service to a stub connection.
    final stub = JellyfinService(
      serverUrl: 'http://localhost',
      accessToken: '',
      userId: '',
    );
    globalPlaylistService.jellyfinService = stub;

    _jellyfinService = null;
    state = null;
  }

  /// Called when any API request receives a 401 mid-session (token invalidated).
  /// Clears stale credentials and redirects the user to /login without wiping
  /// any local listening data (play counts, history, smart mix caches, etc.).
  Future<void> logout401() async {
    if (state == null) return; // already logged out, nothing to do
    debugPrint('[AuthNotifier.logout401] Mid-session 401 — clearing stale token, redirecting to login');
    final db = _ref.read(databaseProvider);
    await db.clearServerConfig();

    final stub = JellyfinService(
      serverUrl: 'http://localhost',
      accessToken: '',
      userId: '',
    );
    globalPlaylistService.jellyfinService = stub;
    _jellyfinService = null;
    state = null; // triggers GoRouter redirect to /login
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final authProvider =
    StateNotifierProvider<AuthNotifier, JellyfinUser?>((ref) {
  return AuthNotifier(ref);
});

/// Exposes the authenticated [JellyfinService], or null if not logged in.
final jellyfinServiceProvider = Provider<JellyfinService?>((ref) {
  final user = ref.watch(authProvider);
  final service = ref.watch(authProvider.notifier).jellyfinService;
  debugPrint('[jellyfinServiceProvider] user=${user?.id ?? "null"}, service=${service != null ? "READY" : "NULL"}');
  if (user == null) return null;
  return service;
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
