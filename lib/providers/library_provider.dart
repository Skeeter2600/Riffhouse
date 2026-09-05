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
import 'auth_provider.dart';
import 'database_provider.dart';
import 'podcast_provider.dart';
import '../audio/queue_notifier.dart';

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

class TracksNotifier extends AsyncNotifier<List<JellyfinTrack>> {
  @override
  Future<List<JellyfinTrack>> build() async {
    final db = ref.watch(databaseProvider);
    final service = ref.watch(jellyfinServiceProvider);
    if (service == null) return [];

    // Eagerly load from database
    final localTracks = await db.getAllLocalTracks();
    final cachedTracks = localTracks.map(localTrackToJellyfin).toList();

    if (cachedTracks.isEmpty) {
      // Database is empty! This is the first sync.
      // We should perform a sync and return the results directly so the provider is in a loading state.
      return _syncInitial(db, service);
    } else {
      // Schedule background sync
      _syncBackground(db, service);
      return cachedTracks;
    }
  }

  Future<List<JellyfinTrack>> _syncInitial(AppDatabase db, JellyfinService service) async {
    try {
      final remoteTracks = await service.getTracks();
      final companions = remoteTracks.map(jellyfinTrackToCompanion).toList();
      await db.bulkInsertLocalTracks(companions);
      return remoteTracks;
    } catch (_) {
      return [];
    }
  }

  Future<void> _syncBackground(AppDatabase db, JellyfinService service) async {
    try {
      const batchSize = 200;
      int startIndex = 0;
      final newTracks = <JellyfinTrack>[];
      bool foundExisting = false;

      while (!foundExisting) {
        final page = await service.getTracksPaged(
          startIndex: startIndex,
          limit: batchSize,
          sortBy: 'DateCreated',
          sortOrder: 'Descending',
        );

        if (page.isEmpty) break;

        for (final track in page) {
          final exists = await db.getLocalTrack(track.id) != null;
          if (exists) {
            foundExisting = true;
            break;
          }
          newTracks.add(track);
        }

        if (page.length < batchSize) break;
        startIndex += page.length;
      }

      if (newTracks.isNotEmpty) {
        final companions = newTracks.map(jellyfinTrackToCompanion).toList();
        await db.bulkInsertLocalTracks(companions);

        // Reload all tracks and update state
        final updatedLocal = await db.getAllLocalTracks();
        state = AsyncData(updatedLocal.map(localTrackToJellyfin).toList());
      }
    } catch (_) {
      // Ignore background sync errors
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(jellyfinServiceProvider);
      final db = ref.read(databaseProvider);
      if (service == null) return [];

      final remoteTracks = await service.getTracks();

      // Perform database reconciliation
      final remoteIds = remoteTracks.map((t) => t.id).toSet();
      final localTracks = await db.getAllLocalTracks();

      // Delete any tracks that are no longer on the server
      for (final local in localTracks) {
        if (!remoteIds.contains(local.jellyfinId)) {
          await db.deleteLocalTrack(local.jellyfinId);
        }
      }

      // Upsert all fetched tracks
      final companions = remoteTracks.map(jellyfinTrackToCompanion).toList();
      await db.bulkInsertLocalTracks(companions);

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
    final service = ref.watch(jellyfinServiceProvider);
    if (service == null) return [];
    return service.getAlbums();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(jellyfinServiceProvider);
      if (service == null) return [];
      return service.getAlbums();
    });
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
    final service = ref.watch(jellyfinServiceProvider);
    if (service == null) return [];
    return service.getArtists();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(jellyfinServiceProvider);
      if (service == null) return [];
      return service.getArtists();
    });
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
    final service = ref.watch(jellyfinServiceProvider);
    if (service == null) return [];
    return service.getPlaylists();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(jellyfinServiceProvider);
      if (service == null) return [];
      return service.getPlaylists();
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
  final service = ref.watch(jellyfinServiceProvider);
  if (service == null) return const [];
  final tracks = await service.getAlbumTracks(albumId);
  return List<JellyfinTrack>.unmodifiable(tracks);
});

// ---------------------------------------------------------------------------
// Artist Albums (for artist detail view)
// ---------------------------------------------------------------------------

final artistAlbumsProvider =
    FutureProvider.family<List<JellyfinAlbum>, String>((ref, artistId) async {
  final service = ref.watch(jellyfinServiceProvider);
  if (service == null) return const [];
  return service.getArtistAlbums(artistId);
});

final artistTracksProvider =
    FutureProvider.family<List<JellyfinTrack>, String>((ref, artistId) async {
  final service = ref.watch(jellyfinServiceProvider);
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
  final service = ref.watch(jellyfinServiceProvider);
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
    state = const AsyncLoading();
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

// ---------------------------------------------------------------------------
// Smart mix caching (regenerates daily at 6 AM local time)
// ---------------------------------------------------------------------------

class _CachedMix {
  final List<JellyfinTrack> tracks;
  final DateTime generatedAt;
  _CachedMix(this.tracks, this.generatedAt);
}

DateTime _nextMidnight(DateTime from) {
  return DateTime(from.year, from.month, from.day + 1);
}

bool _isMixCacheValid(DateTime generatedAt) {
  return DateTime.now().isBefore(_nextMidnight(generatedAt));
}

final Map<String, _CachedMix> _mixMemoryCache = {};
const _smartMixStoragePrefix = 'smart_mix_persisted_cache_v2_';

Future<List<JellyfinTrack>?> _getPersistedMix(String mixType) async {
  // Check in-memory cache first
  final mem = _mixMemoryCache[mixType];
  if (mem != null && _isMixCacheValid(mem.generatedAt)) {
    return mem.tracks;
  }

  // Check persistent storage across app restarts
  try {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_smartMixStoragePrefix$mixType');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final generatedAtMs = data['generatedAt'] as int?;
      if (generatedAtMs != null) {
        final generatedAt = DateTime.fromMillisecondsSinceEpoch(generatedAtMs);
        if (_isMixCacheValid(generatedAt)) {
          final rawTracks = data['tracks'] as List? ?? [];
          final tracks = rawTracks
              .map((t) => JellyfinTrack.fromJson(t as Map<String, dynamic>))
              .toList();
          _mixMemoryCache[mixType] = _CachedMix(tracks, generatedAt);
          return tracks;
        }
      }
    }
  } catch (_) {
    // Ignore cache read error
  }
  return null;
}

Future<void> _persistMix(String mixType, List<JellyfinTrack> tracks) async {
  final now = DateTime.now();
  _mixMemoryCache[mixType] = _CachedMix(tracks, now);
  try {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'generatedAt': now.millisecondsSinceEpoch,
      'tracks': tracks.map((t) => t.toMap()).toList(),
    };
    await prefs.setString('$_smartMixStoragePrefix$mixType', jsonEncode(payload));
  } catch (_) {
    // Ignore cache write error
  }
}

Future<void> clearSmartMixCache([String? mixType]) async {
  if (mixType != null) {
    _mixMemoryCache.remove(mixType);
  } else {
    _mixMemoryCache.clear();
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    if (mixType != null) {
      await prefs.remove('$_smartMixStoragePrefix$mixType');
    } else {
      final keys = prefs.getKeys().where((k) => k.startsWith(_smartMixStoragePrefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    }
  } catch (_) {
    // Ignore cache clear error
  }
}

class DailyMixConfigNotifier extends StateNotifier<AsyncValue<DailyMixConfig>> {
  final PlaylistService _playlistService;

  DailyMixConfigNotifier(this._playlistService) : super(const AsyncLoading()) {
    loadConfig();
  }

  Future<void> loadConfig() async {
    state = const AsyncLoading();
    try {
      final config = await _playlistService.getDailyMixConfig();
      state = AsyncData(config);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> saveConfig(DailyMixConfig config) async {
    await _playlistService.saveDailyMixConfig(config);
    state = AsyncData(config);
    await clearSmartMixCache('daily_drive');
  }

  Future<void> resetConfig() async {
    await _playlistService.resetDailyMixConfig();
    final defaultConfig = DailyMixConfig.defaultConfig();
    state = AsyncData(defaultConfig);
    await clearSmartMixCache('daily_drive');
  }
}

final dailyMixConfigProvider =
    StateNotifierProvider<DailyMixConfigNotifier, AsyncValue<DailyMixConfig>>((ref) {
  final playlistService = ref.watch(playlistServiceProvider);
  return DailyMixConfigNotifier(playlistService);
});

final topGenresProvider = FutureProvider<List<String>>((ref) async {
  final playlistService = ref.watch(playlistServiceProvider);
  return playlistService.getTopListenedGenres();
});

final recentGenresProvider = FutureProvider<List<String>>((ref) async {
  final playlistService = ref.watch(playlistServiceProvider);
  return playlistService.getRecentlyListenedGenres();
});

/// Provider that resolves the tracks for a given smart mix type
/// ('daily', 'heavy', 'undiscovered', 'daily_drive').
/// Results are persisted to disk and valid until midnight of each day.
final smartMixTracksProvider = FutureProvider.family<List<JellyfinTrack>, String>((ref, mixType) async {
  // Return persisted/cached result if still valid (before midnight).
  final cached = await _getPersistedMix(mixType);
  if (cached != null && cached.isNotEmpty) {
    return cached;
  }

  final tracks = await ref.watch(tracksProvider.future);
  final playlistService = ref.read(playlistServiceProvider);

  List<JellyfinTrack> result;
  if (mixType.startsWith('genre_')) {
    final genre = Uri.decodeComponent(mixType.substring('genre_'.length));
    result = await playlistService.getSmartMix(
      genreFilter: [genre],
      libraryTracks: tracks,
    );
  } else if (mixType == 'daily') {
    result = await playlistService.getSmartMix(libraryTracks: tracks);
  } else if (mixType == 'daily_drive') {
    final podcastService = ref.read(podcastServiceProvider);
    final customConfig = ref.watch(dailyMixConfigProvider).valueOrNull;
    result = await playlistService.getDailyDrive(
      libraryTracks: tracks,
      podcastService: podcastService,
      customConfig: customConfig,
    );
  } else if (mixType == 'heavy') {
    result = await playlistService.getHeavyRotation(libraryTracks: tracks);
  } else if (mixType == 'undiscovered') {
    result = await playlistService.getUndiscovered(libraryTracks: tracks);
  } else {
    result = [];
  }

  // Persist result until next midnight
  await _persistMix(mixType, result);
  return result;
});

// ---------------------------------------------------------------------------
// Recently played (local cache — fast, works offline)
// ---------------------------------------------------------------------------

/// Model for a single recently-played item shown in the home screen section.
class RecentlyPlayedItem {
  final String id;
  final String title;
  final String subtitle;
  final String? imageTag;
  final RecentlyPlayedType type;
  final DateTime lastPlayedAt;
  /// For [RecentlyPlayedType.mix] items — the mixType string used to navigate
  /// to SmartMixDetailScreen (e.g. 'daily', 'genre_Rock').
  final String? mixType;
  final int? colorValue;
  final int? secondaryColorValue;

  const RecentlyPlayedItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.imageTag,
    required this.type,
    required this.lastPlayedAt,
    this.mixType,
    this.colorValue,
    this.secondaryColorValue,
  });
}

enum RecentlyPlayedType { track, album, artist, playlist, mix }

/// Helper to get fallback gradient colors for mix types
List<Color> getMixPalette(String mixType) {
  if (mixType.startsWith('genre_')) {
    final genre = Uri.decodeComponent(mixType.replaceFirst('genre_', ''));
    const palettes = [
      [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
      [Color(0xFF10B981), Color(0xFF047857)],
      [Color(0xFFF97316), Color(0xFFC2410C)],
      [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
      [Color(0xFFEC4899), Color(0xFFBE185D)],
      [Color(0xFF14B8A6), Color(0xFF0F766E)],
      [Color(0xFFEAB308), Color(0xFFA16207)],
      [Color(0xFF6366F1), Color(0xFF4338CA)],
    ];
    return palettes[genre.hashCode.abs() % palettes.length];
  }
  if (mixType == 'daily') return const [Color(0xFF7C3AED), Color(0xFF4F46E5)];
  if (mixType == 'heavy') return const [Color(0xFFEC4899), Color(0xFFBE185D)];
  if (mixType == 'undiscovered') return const [Color(0xFF06B6D4), Color(0xFF0369A1)];
  if (mixType == 'daily_drive') return const [Color(0xFFF59E0B), Color(0xFFD97706)];
  return const [Color(0xFF8B5CF6), Color(0xFF7C3AED)];
}

/// Model for a recorded selection in history
class RecentSelection {
  final String id;
  final String type; // 'album', 'artist', 'playlist', 'mix'
  final DateTime timestamp;
  /// Stored title for 'mix' entries (no server lookup needed).
  final String? title;
  /// The mixType used to navigate to SmartMixDetailScreen for 'mix' entries.
  final String? mixType;
  final int? colorValue;
  final int? secondaryColorValue;

  RecentSelection({
    required this.id,
    required this.type,
    required this.timestamp,
    this.title,
    this.mixType,
    this.colorValue,
    this.secondaryColorValue,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'timestamp': timestamp.millisecondsSinceEpoch,
        if (title != null) 'title': title,
        if (mixType != null) 'mixType': mixType,
        if (colorValue != null) 'colorValue': colorValue,
        if (secondaryColorValue != null) 'secondaryColorValue': secondaryColorValue,
      };

  factory RecentSelection.fromJson(Map<String, dynamic> json) => RecentSelection(
        id: json['id'] as String,
        type: json['type'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        title: json['title'] as String?,
        mixType: json['mixType'] as String?,
        colorValue: json['colorValue'] as int?,
        secondaryColorValue: json['secondaryColorValue'] as int?,
      );
}

class RecentSelectionsNotifier extends StateNotifier<List<RecentSelection>> {
  RecentSelectionsNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('recent_selections');
      if (jsonStr != null) {
        final List<dynamic> list = jsonDecode(jsonStr);
        state = list.map((item) => RecentSelection.fromJson(item)).toList();
      }
    } catch (_) {}
  }

  Future<void> addSelection(
    String id,
    String type, {
    String? title,
    String? mixType,
    int? colorValue,
    int? secondaryColorValue,
  }) async {
    // Remove if already exists (to move it to top)
    final filtered = state.where((item) => !(item.id == id && item.type == type)).toList();

    final newItem = RecentSelection(
      id: id,
      type: type,
      timestamp: DateTime.now(),
      title: title,
      mixType: mixType,
      colorValue: colorValue,
      secondaryColorValue: secondaryColorValue,
    );

    final newState = [newItem, ...filtered].take(20).toList();
    state = newState;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(newState.map((item) => item.toJson()).toList());
      await prefs.setString('recent_selections', jsonStr);
    } catch (_) {}
  }
}

final recentSelectionsProvider = StateNotifierProvider<RecentSelectionsNotifier, List<RecentSelection>>((ref) {
  return RecentSelectionsNotifier();
});

/// Resolves actual models for recently played items by watching [recentSelectionsProvider]
/// and joining against active providers.
final recentlyPlayedProvider = FutureProvider<List<RecentlyPlayedItem>>((ref) async {
  final selections = ref.watch(recentSelectionsProvider);
  if (selections.isEmpty) return [];

  final albums = ref.watch(albumsProvider).valueOrNull ?? [];
  final artists = ref.watch(artistsProvider).valueOrNull ?? [];
  final playlists = ref.watch(playlistsProvider).valueOrNull ?? [];

  final List<RecentlyPlayedItem> items = [];

  for (final sel in selections) {
    try {
      if (sel.type == 'album') {
        final album = albums.firstWhere((a) => a.id == sel.id);
        items.add(RecentlyPlayedItem(
          id: album.id,
          title: album.name,
          subtitle: album.artist,
          imageTag: album.imageTag,
          type: RecentlyPlayedType.album,
          lastPlayedAt: sel.timestamp,
        ));
      } else if (sel.type == 'artist') {
        final artist = artists.firstWhere((a) => a.id == sel.id);
        items.add(RecentlyPlayedItem(
          id: artist.id,
          title: artist.name,
          subtitle: 'Artist',
          imageTag: artist.imageTag,
          type: RecentlyPlayedType.artist,
          lastPlayedAt: sel.timestamp,
        ));
      } else if (sel.type == 'playlist') {
        final playlist = playlists.firstWhere((p) => p.id == sel.id);
        items.add(RecentlyPlayedItem(
          id: playlist.id,
          title: playlist.name,
          subtitle: '${playlist.trackCount} tracks',
          imageTag: playlist.imageTag,
          type: RecentlyPlayedType.playlist,
          lastPlayedAt: sel.timestamp,
        ));
      } else if (sel.type == 'mix' && sel.mixType != null && sel.title != null) {
        // Mix items store title & mixType directly — no server lookup needed.
        final palette = sel.colorValue != null
            ? null
            : getMixPalette(sel.mixType!);
        items.add(RecentlyPlayedItem(
          id: sel.mixType!,
          title: sel.title!,
          subtitle: 'Mix',
          imageTag: null,
          type: RecentlyPlayedType.mix,
          lastPlayedAt: sel.timestamp,
          mixType: sel.mixType,
          colorValue: sel.colorValue ?? palette?[0].toARGB32(),
          secondaryColorValue: sel.secondaryColorValue ?? palette?[1].toARGB32(),
        ));
      }
    } catch (_) {
      // Item not found in current library — skip it.
    }
  }

  return items;
});

/// Old server-based providers kept for Android Auto use only.
final recentAlbumsProvider = FutureProvider<List<JellyfinAlbum>>((ref) async {
  final service = ref.watch(jellyfinServiceProvider);
  if (service == null) return [];
  return service.getRecentAlbums();
});

final recentArtistsProvider = FutureProvider<List<JellyfinArtist>>((ref) async {
  final service = ref.watch(jellyfinServiceProvider);
  if (service == null) return [];
  return service.getRecentArtists();
});

final recentPlaylistsProvider = FutureProvider<List<JellyfinPlaylist>>((ref) async {
  final service = ref.watch(jellyfinServiceProvider);
  if (service == null) return [];
  return service.getRecentPlaylists();
});

// ---------------------------------------------------------------------------
// New For You (recently-added unplayed albums with 14-day filter + fallback)
// ---------------------------------------------------------------------------

class NewForYouData {
  final List<JellyfinAlbum> albums;
  final bool isFallback;
  const NewForYouData({required this.albums, required this.isFallback});
}

final newAlbumsProvider = FutureProvider<NewForYouData>((ref) async {
  final service = ref.watch(jellyfinServiceProvider);
  if (service == null) return const NewForYouData(albums: [], isFallback: false);

  final rawNewAlbums = await service.getNewAlbums(limit: 20);
  final twoWeeksAgo = DateTime.now().subtract(const Duration(days: 14));

  final recentNewAlbums = rawNewAlbums.where((album) {
    if (album.dateCreated == null) return false;
    return album.dateCreated!.isAfter(twoWeeksAgo);
  }).toList();

  if (recentNewAlbums.isNotEmpty) {
    return NewForYouData(albums: recentNewAlbums, isFallback: false);
  }

  // Fallback: Albums related to recent listens and categories/genres
  final allAlbums = ref.watch(albumsProvider).valueOrNull ?? await service.getAlbums();
  final recentPlays = ref.watch(recentlyPlayedProvider).valueOrNull ?? [];

  // Preferred artists & genres
  final preferredArtists = <String>{};
  final preferredGenres = <String>{};

  for (final item in recentPlays) {
    if (item.type == RecentlyPlayedType.artist) {
      preferredArtists.add(item.title.toLowerCase());
    } else if (item.type == RecentlyPlayedType.album) {
      preferredArtists.add(item.subtitle.toLowerCase());
    }
  }

  for (final album in allAlbums) {
    if (preferredArtists.contains(album.artist.toLowerCase())) {
      preferredGenres.addAll(album.genres.map((g) => g.toLowerCase()));
    }
  }

  final scoredAlbums = <({JellyfinAlbum album, int score})>[];
  for (final album in allAlbums) {
    int score = 0;
    if (preferredArtists.contains(album.artist.toLowerCase())) {
      score += 3;
    }
    for (final g in album.genres) {
      if (preferredGenres.contains(g.toLowerCase())) {
        score += 2;
      }
    }
    if (score > 0) {
      scoredAlbums.add((album: album, score: score));
    }
  }

  scoredAlbums.sort((a, b) => b.score.compareTo(a.score));

  List<JellyfinAlbum> fallbackAlbums = scoredAlbums.map((s) => s.album).take(12).toList();
  if (fallbackAlbums.isEmpty) {
    fallbackAlbums = (List<JellyfinAlbum>.from(allAlbums)..shuffle()).take(12).toList();
  }

  return NewForYouData(albums: fallbackAlbums, isFallback: true);
});

// ---------------------------------------------------------------------------
// Shuffled Home Albums (biased / inspired by recent listens)
// ---------------------------------------------------------------------------

final homeAlbumsProvider = Provider<AsyncValue<List<JellyfinAlbum>>>((ref) {
  final albumsAsync = ref.watch(albumsProvider);
  return albumsAsync.whenData((albums) {
    if (albums.isEmpty) return [];

    final recentPlays = ref.watch(recentlyPlayedProvider).valueOrNull ?? [];

    final preferredArtists = <String>{};
    for (final item in recentPlays) {
      if (item.type == RecentlyPlayedType.artist) {
        preferredArtists.add(item.title.toLowerCase());
      } else if (item.type == RecentlyPlayedType.album) {
        preferredArtists.add(item.subtitle.toLowerCase());
      }
    }

    final inspired = <JellyfinAlbum>[];
    final others = <JellyfinAlbum>[];

    for (final album in albums) {
      if (preferredArtists.contains(album.artist.toLowerCase())) {
        inspired.add(album);
      } else {
        others.add(album);
      }
    }

    final rng = Random();
    final shuffledInspired = List<JellyfinAlbum>.from(inspired)..shuffle(rng);
    final shuffledOthers = List<JellyfinAlbum>.from(others)..shuffle(rng);

    return [...shuffledInspired, ...shuffledOthers];
  });
});

// ---------------------------------------------------------------------------
// Home Genre Mixes (top listened / library genres)
// ---------------------------------------------------------------------------

final homeGenreMixesProvider = FutureProvider<List<String>>((ref) async {
  final playlistService = ref.watch(playlistServiceProvider);
  final topListened = await playlistService.getTopListenedGenres(limit: 8);

  final tracks = ref.watch(tracksProvider).valueOrNull ?? [];
  final genreCounts = <String, int>{};
  for (final t in tracks) {
    for (final g in t.genres) {
      final clean = g.trim();
      if (clean.isNotEmpty) {
        genreCounts[clean] = (genreCounts[clean] ?? 0) + 1;
      }
    }
  }

  final libraryGenres = genreCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final result = <String>[];
  for (final g in topListened) {
    if (genreCounts.containsKey(g) && !result.contains(g)) {
      result.add(g);
    }
  }
  for (final entry in libraryGenres) {
    if (!result.contains(entry.key)) {
      result.add(entry.key);
    }
    if (result.length >= 8) break;
  }
  return result;
});

// ---------------------------------------------------------------------------
// Android Auto Background Library Sync
// ---------------------------------------------------------------------------

final androidAutoSyncProvider = Provider<void>((ref) {
  final service = ref.watch(jellyfinServiceProvider);
  final handler = ref.watch(audioHandlerProvider);

  if (service != null) {
    handler.updateAndroidAutoCredentials(
      service.serverUrl,
      service.accessToken,
    );
  }

  // Tracks are NOT watched here — Android Auto loads them on-demand per
  // container via getChildren(). Watching tracksProvider here caused a
  // notification storm that flooded the Binder IPC buffer.
  final albums = ref.watch(albumsProvider).valueOrNull ?? [];
  final artists = ref.watch(artistsProvider).valueOrNull ?? [];
  final playlists = ref.watch(playlistsProvider).valueOrNull ?? [];
  final recentlyPlayed = ref.watch(recentlyPlayedProvider).valueOrNull ?? [];
  final newAlbums = ref.watch(newAlbumsProvider).valueOrNull?.albums ?? [];

  if (service != null) {
    handler.updateAndroidAutoLibrary(
      playlists: playlists,
      albums: albums,
      artists: artists,
      tracksByContainer: const {},
      recentlyPlayed: recentlyPlayed,
      newAlbums: newAlbums,
    );
  }
});

