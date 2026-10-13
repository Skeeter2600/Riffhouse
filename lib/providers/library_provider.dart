import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/daily_mix_config.dart';
import '../models/jellyfin_models.dart';
import '../services/jellyfin_service.dart';
import '../services/playlist_service.dart';
import '../services/podcast_service.dart';
import 'auth_provider.dart';
import 'database_provider.dart';
import 'podcast_provider.dart';
import '../audio/queue_notifier.dart';
import '../utils/log.dart';

part 'library/smart_mix_providers.dart';
part 'library/recently_played_providers.dart';
part 'library/home_providers.dart';
part 'library/android_auto_sync_provider.dart';

// ---------------------------------------------------------------------------
// Helpers for mapping between database models and network models
// ---------------------------------------------------------------------------

JellyfinTrack localTrackToJellyfin(LocalTrack local) {
  List<String> artists = [];
  List<String> genres = [];
  try {
    artists = List<String>.from(jsonDecode(local.artistsJson));
  } catch (_) {}
  try {
    genres = List<String>.from(jsonDecode(local.genresJson));
  } catch (_) {}
  return JellyfinTrack(
    id: local.jellyfinId,
    name: local.name,
    artists: artists,
    albumArtist: local.albumArtist,
    albumId: local.albumId,
    albumName: local.albumName,
    genres: genres,
    durationMs: local.durationMs,
    serverId: local.serverId,
    imageTag: local.imageTag,
    dateCreated: local.dateCreated,
  );
}

LocalTracksCompanion jellyfinTrackToCompanion(JellyfinTrack track) {
  return LocalTracksCompanion(
    jellyfinId: Value(track.id),
    name: Value(track.name),
    artistsJson: Value(jsonEncode(track.artists)),
    albumArtist: Value(track.albumArtist),
    albumId: Value(track.albumId),
    albumName: Value(track.albumName),
    genresJson: Value(jsonEncode(track.genres)),
    durationMs: Value(track.durationMs),
    serverId: Value(track.serverId),
    imageTag: Value(track.imageTag),
    dateCreated: Value(track.dateCreated),
  );
}

// ---------------------------------------------------------------------------
// Tracks
// ---------------------------------------------------------------------------

///
/// How the track list stays up to date:
///  * It is shown straight from the local database.
///  * Every launch does a cheap incremental sync that asks the server only
///    for tracks added since last time.
///  * A full sync, which downloads the whole library and is the only way to
///    notice tracks that were removed or retagged on the server, runs at most
///    once per [fullSyncInterval] and on pull-to-refresh.
class TracksNotifier extends AsyncNotifier<List<JellyfinTrack>> {
  static const _fullSyncPrefKey = 'library_full_sync_at';

  /// How often the whole library is downloaded again in the background.
  static const fullSyncInterval = Duration(hours: 24);

  /// Whether a full sync should run, given when the last one finished.
  static bool isFullSyncDue(DateTime? lastFullSync, DateTime now) =>
      lastFullSync == null || now.difference(lastFullSync) >= fullSyncInterval;

  Future<void> _recordFullSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _fullSyncPrefKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Ignore error
    }
  }

  /// Runs a full sync in the background if the last one is old enough,
  /// without replacing the list on screen by a spinner.
  Future<void> _fullSyncIfDue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_fullSyncPrefKey);
      final lastFullSync =
          last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
      if (!isFullSyncDue(lastFullSync, DateTime.now())) {
        logDebug('[TracksNotifier] Full sync not due (last: $lastFullSync)');
        return;
      }
      logDebug('[TracksNotifier] Full sync due (last: $lastFullSync)');
      await refresh(silent: true);
    } catch (e) {
      logDebug('[TracksNotifier._fullSyncIfDue] $e');
    }
  }

  @override
  Future<List<JellyfinTrack>> build() async {
    final db = ref.watch(databaseProvider);
    final service = ref.watch(musicServiceProvider);
    logDebug('[TracksNotifier.build] service=${service != null ? "READY (userId=${service.userId})" : "NULL"}');
    if (service == null) {
      logDebug('[TracksNotifier.build] service is null → returning []');
      return [];
    }

    // Eagerly load from database
    final localTracks = await db.getAllLocalTracks();
    final cachedTracks = localTracks.map(localTrackToJellyfin).toList();
    logDebug('[TracksNotifier.build] DB cache has ${cachedTracks.length} tracks');

    if (cachedTracks.isEmpty) {
      // Database is empty — first sync.
      logDebug('[TracksNotifier.build] DB empty → starting _syncInitial');
      return _syncInitial(db, service);
    } else {
      // Schedule background sync
      logDebug('[TracksNotifier.build] Returning ${cachedTracks.length} cached tracks, scheduling background sync');
      _syncBackground(db, service);
      _fullSyncIfDue();
      return cachedTracks;
    }
  }

  Future<List<JellyfinTrack>> _syncInitial(AppDatabase db, MusicService service) async {
    try {
      logDebug('[TracksNotifier._syncInitial] Fetching all tracks from server...');
      final remoteTracks = await service.getTracks();
      logDebug('[TracksNotifier._syncInitial] Got ${remoteTracks.length} tracks from server');
      final companions = remoteTracks.map(jellyfinTrackToCompanion).toList();
      await db.bulkInsertLocalTracks(companions);
      logDebug('[TracksNotifier._syncInitial] Saved ${remoteTracks.length} tracks to DB');
      if (remoteTracks.isNotEmpty) await _recordFullSync();
      return remoteTracks;
    } catch (e, st) {
      logDebug('[TracksNotifier._syncInitial] ERROR: $e\n$st');
      return [];
    }
  }

  Future<void> _syncBackground(AppDatabase db, MusicService service) async {
    try {
      logDebug('[TracksNotifier._syncBackground] Starting background sync...');
      final newTracks = await service
          .fetchNewTracks((id) async => await db.getLocalTrack(id) != null);

      logDebug('[TracksNotifier._syncBackground] Found ${newTracks.length} new tracks');
      if (newTracks.isNotEmpty) {
        final companions = newTracks.map(jellyfinTrackToCompanion).toList();
        await db.bulkInsertLocalTracks(companions);

        // Reload all tracks and update state
        final updatedLocal = await db.getAllLocalTracks();
        logDebug('[TracksNotifier._syncBackground] Updated state with ${updatedLocal.length} total tracks');
        state = AsyncData(updatedLocal.map(localTrackToJellyfin).toList());
      }
    } catch (e, st) {
      logDebug('[TracksNotifier._syncBackground] ERROR: $e\n$st');
    }
  }

  /// Downloads the whole library and reconciles the local copy with it.
  /// With [silent] the current list stays on screen while that happens.
  Future<void> refresh({bool silent = false}) async {
    final service = ref.read(musicServiceProvider);
    final db = ref.read(databaseProvider);
    logDebug('[TracksNotifier.refresh] Called. service=${service != null ? "READY" : "NULL"}');

    // If the service is not available yet, do NOT wipe the state. Just load
    // from the local database so existing cached songs remain visible.
    if (service == null) {
      final localTracks = await db.getAllLocalTracks();
      logDebug('[TracksNotifier.refresh] service null → DB has ${localTracks.length} tracks, keeping state');
      if (localTracks.isNotEmpty) {
        state = AsyncData(localTracks.map(localTrackToJellyfin).toList());
      }
      return;
    }

    logDebug('[TracksNotifier.refresh] Fetching from server (serverUrl=${service.serverUrl}, userId=${service.userId})...');
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      // The result is used below to drop local tracks that are gone from the
      // server, so it has to be the complete library. If the fetch fails
      // (offline, server down, expired sign-in) keep what is stored locally.
      final List<JellyfinTrack> remoteTracks;
      try {
        remoteTracks = await service.getTracks(throwOnError: true);
      } catch (e) {
        logDebug('[TracksNotifier.refresh] Fetch failed, keeping local library: $e');
        if (await service.checkSession() == SessionStatus.unauthorized) {
          ref.read(authProvider.notifier).logout401();
        }
        final cached = await db.getAllLocalTracks();
        return cached.map(localTrackToJellyfin).toList();
      }
      logDebug('[TracksNotifier.refresh] Got ${remoteTracks.length} tracks from server');
      await _recordFullSync();

      // Perform database reconciliation. A local write failure must not turn a
      // successful server fetch into an error state.
      try {
        final remoteIds = remoteTracks.map((t) => t.id).toSet();
        final localTracks = await db.getAllLocalTracks();
        logDebug('[TracksNotifier.refresh] DB has ${localTracks.length} local tracks before reconciliation');

        // Delete any tracks that are no longer on the server
        for (final local in localTracks) {
          if (!remoteIds.contains(local.jellyfinId)) {
            await db.deleteLocalTrack(local.jellyfinId);
          }
        }

        // Upsert all fetched tracks
        final companions = remoteTracks.map(jellyfinTrackToCompanion).toList();
        await db.bulkInsertLocalTracks(companions);
        logDebug('[TracksNotifier.refresh] Upserted ${companions.length} tracks to DB');
      } catch (e, st) {
        logDebug('[TracksNotifier.refresh] DB reconciliation ERROR: $e\n$st');
      }

      return remoteTracks;
    });
  }
}

final tracksProvider =
    AsyncNotifierProvider<TracksNotifier, List<JellyfinTrack>>(
        TracksNotifier.new);

// ---------------------------------------------------------------------------
// Albums
// ---------------------------------------------------------------------------

class AlbumsNotifier extends AsyncNotifier<List<JellyfinAlbum>> {
  @override
  Future<List<JellyfinAlbum>> build() async {
    final service = ref.watch(musicServiceProvider);
    if (service == null) return [];
    return service.getAlbums();
  }

  Future<void> refresh() async {
    final service = ref.read(musicServiceProvider);
    // Do not wipe state if service is not yet available.
    if (service == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => service.getAlbums());
  }
}

final albumsProvider =
    AsyncNotifierProvider<AlbumsNotifier, List<JellyfinAlbum>>(
        AlbumsNotifier.new);

// ---------------------------------------------------------------------------
// Artists
// ---------------------------------------------------------------------------

class ArtistsNotifier extends AsyncNotifier<List<JellyfinArtist>> {
  @override
  Future<List<JellyfinArtist>> build() async {
    final service = ref.watch(musicServiceProvider);
    if (service == null) return [];
    return service.getArtists();
  }

  Future<void> refresh() async {
    final service = ref.read(musicServiceProvider);
    // Do not wipe state if service is not yet available.
    if (service == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => service.getArtists());
  }
}

final artistsProvider =
    AsyncNotifierProvider<ArtistsNotifier, List<JellyfinArtist>>(
        ArtistsNotifier.new);

// ---------------------------------------------------------------------------
// Playlists
// ---------------------------------------------------------------------------

class PlaylistsNotifier extends AsyncNotifier<List<JellyfinPlaylist>> {
  @override
  Future<List<JellyfinPlaylist>> build() async {
    final service = ref.watch(musicServiceProvider);
    final db = ref.watch(databaseProvider);

    if (service == null) {
      final local = await db.getAllLocalPlaylists();
      return local.map((lp) {
        int count = 0;
        try {
          final List<dynamic> ids = jsonDecode(lp.trackIdsJson);
          count = ids.length;
        } catch (_) {}
        return JellyfinPlaylist(
          id: lp.jellyfinId,
          name: lp.name,
          trackCount: count,
        );
      }).toList();
    }

    try {
      final remote = await service.getPlaylists();
      if (remote.isNotEmpty) {
        for (final p in remote) {
          final existing = await db.getLocalPlaylist(p.id);
          await db.upsertLocalPlaylist(LocalPlaylistsCompanion(
            id: existing != null ? Value(existing.id) : const Value.absent(),
            jellyfinId: Value(p.id),
            name: Value(p.name),
            trackIdsJson: existing != null ? Value(existing.trackIdsJson) : const Value('[]'),
            lastSyncedAt: Value(DateTime.now()),
          ));
        }
        return remote;
      }
    } catch (_) {}

    // Fallback to local database if remote query returned empty/failed
    final local = await db.getAllLocalPlaylists();
    if (local.isNotEmpty) {
      return local.map((lp) {
        int count = 0;
        try {
          final List<dynamic> ids = jsonDecode(lp.trackIdsJson);
          count = ids.length;
        } catch (_) {}
        return JellyfinPlaylist(
          id: lp.jellyfinId,
          name: lp.name,
          trackCount: count,
        );
      }).toList();
    }
    return [];
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(musicServiceProvider);
      final db = ref.read(databaseProvider);
      if (service == null) {
        final local = await db.getAllLocalPlaylists();
        return local.map((lp) {
          int count = 0;
          try {
            final List<dynamic> ids = jsonDecode(lp.trackIdsJson);
            count = ids.length;
          } catch (_) {}
          return JellyfinPlaylist(
            id: lp.jellyfinId,
            name: lp.name,
            trackCount: count,
          );
        }).toList();
      }

      final remote = await service.getPlaylists();
      for (final p in remote) {
        final existing = await db.getLocalPlaylist(p.id);
        await db.upsertLocalPlaylist(LocalPlaylistsCompanion(
          id: existing != null ? Value(existing.id) : const Value.absent(),
          jellyfinId: Value(p.id),
          name: Value(p.name),
          trackIdsJson: existing != null ? Value(existing.trackIdsJson) : const Value('[]'),
          lastSyncedAt: Value(DateTime.now()),
        ));
      }
      return remote;
    });
  }
}

final playlistsProvider =
    AsyncNotifierProvider<PlaylistsNotifier, List<JellyfinPlaylist>>(
        PlaylistsNotifier.new);

// ---------------------------------------------------------------------------
// Album Tracks (for album detail view)
// ---------------------------------------------------------------------------

final albumTracksProvider = FutureProvider.family<List<JellyfinTrack>, String>(
    (ref, albumId) async {
  final service = ref.watch(musicServiceProvider);
  if (service == null) return const [];
  final tracks = await service.getAlbumTracks(albumId);
  if (tracks.isNotEmpty) return List<JellyfinTrack>.unmodifiable(tracks);

  // Offline and never opened before: build the album from the local library.
  final local = await ref.read(databaseProvider).getAllLocalTracks();
  return List<JellyfinTrack>.unmodifiable(
    local.where((t) => t.albumId == albumId).map(localTrackToJellyfin),
  );
});

// ---------------------------------------------------------------------------
// Artist Albums (for artist detail view)
// ---------------------------------------------------------------------------

final artistAlbumsProvider =
    FutureProvider.family<List<JellyfinAlbum>, String>((ref, artistId) async {
  final service = ref.watch(musicServiceProvider);
  if (service == null) return const [];
  return service.getArtistAlbums(artistId);
});

final artistTracksProvider =
    FutureProvider.family<List<JellyfinTrack>, String>((ref, artistId) async {
  final service = ref.watch(musicServiceProvider);
  if (service == null) return const [];
  final tracks = await service.getArtistTracks(artistId);
  return List<JellyfinTrack>.unmodifiable(tracks);
});

// ---------------------------------------------------------------------------
// Playlist tracks
// ---------------------------------------------------------------------------

final playlistTracksProvider =
    FutureProvider.family<List<JellyfinTrack>, String>(
        (ref, playlistId) async {
  final service = ref.watch(musicServiceProvider);
  if (service == null) return const [];
  final tracks = await service.getPlaylistTracks(playlistId);
  return List<JellyfinTrack>.unmodifiable(tracks);
});

// ---------------------------------------------------------------------------
// Cached tracks
// ---------------------------------------------------------------------------

class CachedTracksNotifier extends AsyncNotifier<List<CachedTrack>> {
  @override
  Future<List<CachedTrack>> build() async {
    final cacheService = ref.watch(cacheServiceProvider);
    return cacheService.getAllCachedTracks();
  }

  Future<void> refresh() async {
    // Keeps showing the current list while reloading; this runs after every
    // finished download and must not flash a spinner each time.
    state = await AsyncValue.guard(() async {
      final cacheService = ref.read(cacheServiceProvider);
      return cacheService.getAllCachedTracks();
    });
  }

  Future<void> deleteTrack(String jellyfinId) async {
    final cacheService = ref.read(cacheServiceProvider);
    await cacheService.deleteCachedTrack(jellyfinId);
    await refresh();
  }

  Future<void> clearAll() async {
    final cacheService = ref.read(cacheServiceProvider);
    final tracks = state.valueOrNull ?? [];
    for (final t in tracks) {
      await cacheService.deleteCachedTrack(t.jellyfinId);
    }
    await refresh();
  }
}

final cachedTracksProvider =
    AsyncNotifierProvider<CachedTracksNotifier, List<CachedTrack>>(
        CachedTracksNotifier.new);
