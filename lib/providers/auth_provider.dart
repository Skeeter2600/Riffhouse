import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';


import '../audio/queue_notifier.dart';
import '../database/app_database.dart';
import '../main.dart'; // Import to access global singletons
import '../models/jellyfin_models.dart';
import '../services/cache_service.dart';
import '../services/favorites_store.dart';
import '../services/jellyfin_service.dart';
import '../services/offline_cache_interceptor.dart';
import '../services/play_reporter.dart';
import '../services/playlist_service.dart';
import 'database_provider.dart';
import '../utils/log.dart';

// ---------------------------------------------------------------------------
// AuthNotifier
// ---------------------------------------------------------------------------

/// The session saved by an earlier run, read by `main()` before the first
/// frame so the app opens straight into the library instead of flashing the
/// login screen.
final savedSessionProvider = Provider<ServerConfig?>((ref) => null);

class AuthNotifier extends StateNotifier<JellyfinUser?> {
  static const _deviceIdKey = 'jellyfin_device_id';
  static const _libraryOwnerKey = 'library_owner';

  final Ref _ref;
  MusicService? _musicService;

  AuthNotifier(this._ref, ServerConfig? saved) : super(_userFrom(saved)) {
    if (saved == null) return;
    final service = MusicService.create(
      type: ServerType.fromId(saved.serverType),
      serverUrl: saved.serverUrl,
      accessToken: saved.accessToken,
      userId: saved.userId,
    );
    globalPlaylistService.musicService = service;
    _musicService = service;
    _verifySavedSession(service);
  }

  static JellyfinUser? _userFrom(ServerConfig? saved) {
    if (saved == null) return null;
    return JellyfinUser(
      id: saved.userId,
      name: saved.username,
      accessToken: saved.accessToken,
      isAdmin: false,
    );
  }

  MusicService? get musicService => _musicService;

  /// Loads this install's device id, if one was created by an earlier
  /// sign-in. Called from `main()` before any request is made.
  static Future<void> loadDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_deviceIdKey);
      if (id != null && id.isNotEmpty) JellyfinService.deviceId = id;
    } catch (_) {
      // Keep the default
    }
  }

  /// Checks the saved token in the background. The saved session is trusted
  /// until the server explicitly rejects it, so the app keeps working (with
  /// the local library and downloads) when it starts without a connection.
  /// All local listening data (play counts, history, etc.) is preserved
  /// either way.
  Future<void> _verifySavedSession(MusicService service) async {
    final status = await service.checkSession();
    logDebug('[AuthNotifier] Saved session is ${status.name}');
    if (status == SessionStatus.valid) {
      // Deliver plays that were made while the server was out of reach.
      unawaited(PlayReporter.flush(service));
      unawaited(FavoritesStore.sync(service));
    }
    if (status == SessionStatus.unauthorized &&
        identical(service, _musicService)) {
      await logout401();
    }
  }

  /// Signs in to a server of the given [type] and saves the session.
  /// Returns null on success, or the reason it failed.
  Future<LoginFailure?> login(
    ServerType type,
    String serverUrl,
    String username,
    String password,
  ) async {
    logDebug('[AuthNotifier.login] Attempting ${type.id} login to $serverUrl');

    // Give this install its own device id the first time someone signs in.
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_deviceIdKey);
      if (id == null || id.isEmpty) {
        id = const Uuid().v4();
        await prefs.setString(_deviceIdKey, id);
      }
      JellyfinService.deviceId = id;
    } catch (_) {
      // Keep the current id
    }

    OfflineCacheInterceptor.resetReachability();
    final MusicService service;
    final JellyfinUser user;
    try {
      final result =
          await MusicService.signIn(type, serverUrl, username, password);
      service = result.service;
      user = result.user;
    } on LoginException catch (e) {
      logDebug('[AuthNotifier.login] Failed: ${e.failure.name}');
      return e.failure;
    }

    await _forgetLibraryOfOtherAccount(service);

    // Update the global playlist service's connection config!
    globalPlaylistService.musicService = service;

    // Persist to Drift database.
    final db = _ref.read(databaseProvider);
    await db.saveServerConfig(ServerConfigsCompanion(
      serverUrl: Value(serverUrl),
      userId: Value(user.id),
      username: Value(user.name),
      accessToken: Value(user.accessToken),
      serverType: Value(type.id),
    ));

    _musicService = service;
    state = user;
    unawaited(PlayReporter.flush(service));
    unawaited(FavoritesStore.load(service)
        .then((_) => FavoritesStore.sync(service)));
    return null;
  }

  /// The local track index belongs to one account on one server. Signing in
  /// somewhere else must not show the previous library until the next full
  /// sync, so the index is dropped. Play history and settings are kept.
  Future<void> _forgetLibraryOfOtherAccount(MusicService service) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final owner = '${service.type.id}|'
          '${MusicService.normalizeUrl(service.serverUrl)}|${service.userId}';
      final previous = prefs.getString(_libraryOwnerKey);
      // No record yet: an install from before this was tracked, signing back
      // in to what is almost certainly the same account.
      if (previous != null && previous != owner) {
        await _ref.read(databaseProvider).clearLocalTracks();
      }
      await prefs.setString(_libraryOwnerKey, owner);
    } catch (e) {
      logDebug('[AuthNotifier] Could not record the library owner: $e');
    }
  }

  /// Clears the session and removes saved config from database.
  /// Called from the Settings screen on manual logout.
  Future<void> logout() async {
    logDebug('[AuthNotifier.logout] Logging out...');
    final db = _ref.read(databaseProvider);
    await db.clearServerConfig();

    // Reset the global playlist service to a stub connection.
    final stub = MusicService.signedOut();
    globalPlaylistService.musicService = stub;
    unawaited(FavoritesStore.load(null));

    _musicService = null;
    state = null;
  }

  /// Called when any API request receives a 401 mid-session (token invalidated).
  /// Clears stale credentials and redirects the user to /login without wiping
  /// any local listening data (play counts, history, smart mix caches, etc.).
  Future<void> logout401() async {
    if (state == null) return; // already logged out, nothing to do
    logDebug('[AuthNotifier.logout401] Mid-session 401 — clearing stale token, redirecting to login');
    final db = _ref.read(databaseProvider);
    await db.clearServerConfig();

    final stub = MusicService.signedOut();
    globalPlaylistService.musicService = stub;
    unawaited(FavoritesStore.load(null));
    _musicService = null;
    state = null; // triggers GoRouter redirect to /login
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final authProvider =
    StateNotifierProvider<AuthNotifier, JellyfinUser?>((ref) {
  return AuthNotifier(ref, ref.read(savedSessionProvider));
});

/// Exposes the authenticated [MusicService], or null if not logged in.
final musicServiceProvider = Provider<MusicService?>((ref) {
  final user = ref.watch(authProvider);
  final service = ref.watch(authProvider.notifier).musicService;
  logDebug('[musicServiceProvider] user=${user?.id ?? "null"}, service=${service != null ? "READY" : "NULL"}');
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
