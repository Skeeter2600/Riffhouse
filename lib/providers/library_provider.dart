import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/jellyfin_models.dart';
import '../services/cache_service.dart';
import 'auth_provider.dart';
import 'database_provider.dart';
import '../audio/queue_notifier.dart';

// ---------------------------------------------------------------------------
// Tracks
// ---------------------------------------------------------------------------

class TracksNotifier extends AsyncNotifier<List<JellyfinTrack>> {
  @override
  Future<List<JellyfinTrack>> build() async {
    final service = ref.watch(jellyfinServiceProvider);
    if (service == null) return [];
    return service.getTracks();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(jellyfinServiceProvider);
      if (service == null) return [];
      return service.getTracks();
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
  if (service == null) return [];
  
  print('albumTracksProvider: Fetching tracks directly from server for albumId="$albumId"');
  final tracks = await service.getAlbumTracks(albumId);
  print('albumTracksProvider: Fetched ${tracks.length} tracks.');
  return tracks;
});

// ---------------------------------------------------------------------------
// Artist Albums (for artist detail view)
// ---------------------------------------------------------------------------

final artistAlbumsProvider =
    FutureProvider.family<List<JellyfinAlbum>, String>((ref, artistId) async {
  final service = ref.watch(jellyfinServiceProvider);
  if (service == null) return [];
  return service.getArtistAlbums(artistId);
});

final artistTracksProvider =
    FutureProvider.family<List<JellyfinTrack>, String>((ref, artistId) async {
  final service = ref.watch(jellyfinServiceProvider);
  if (service == null) return [];
  return service.getArtistTracks(artistId);
});

// ---------------------------------------------------------------------------
// Playlist tracks
// ---------------------------------------------------------------------------

final playlistTracksProvider =
    FutureProvider.family<List<JellyfinTrack>, String>(
        (ref, playlistId) async {
  final service = ref.watch(jellyfinServiceProvider);
  if (service == null) return [];
  return service.getPlaylistTracks(playlistId);
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

/// Provider that resolves the tracks for a given smart mix type ('daily', 'heavy', 'undiscovered').
final smartMixTracksProvider = FutureProvider.family<List<JellyfinTrack>, String>((ref, mixType) async {
  final tracks = await ref.watch(tracksProvider.future);
  final playlistService = ref.read(playlistServiceProvider);
  
  if (mixType == 'daily') {
    return playlistService.getSmartMix(libraryTracks: tracks);
  } else if (mixType == 'heavy') {
    return playlistService.getHeavyRotation(libraryTracks: tracks);
  } else if (mixType == 'undiscovered') {
    return playlistService.getUndiscovered(libraryTracks: tracks);
  }
  return [];
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

  const RecentlyPlayedItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.imageTag,
    required this.type,
    required this.lastPlayedAt,
  });
}

enum RecentlyPlayedType { track, album, artist, playlist }

/// Model for a recorded selection in history
class RecentSelection {
  final String id;
  final String type; // 'album', 'artist', 'playlist'
  final DateTime timestamp;

  RecentSelection({
    required this.id,
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory RecentSelection.fromJson(Map<String, dynamic> json) => RecentSelection(
        id: json['id'] as String,
        type: json['type'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
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

  Future<void> addSelection(String id, String type) async {
    // Remove if already exists (to move it to top)
    final filtered = state.where((item) => !(item.id == id && item.type == type)).toList();
    
    final newItem = RecentSelection(
      id: id,
      type: type,
      timestamp: DateTime.now(),
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
    if (sel.type == 'album') {
      final album = albums.firstWhere((a) => a.id == sel.id, orElse: () => null as dynamic);
      if (album != null) {
        items.add(RecentlyPlayedItem(
          id: album.id,
          title: album.name,
          subtitle: album.artist,
          imageTag: album.imageTag,
          type: RecentlyPlayedType.album,
          lastPlayedAt: sel.timestamp,
        ));
      }
    } else if (sel.type == 'artist') {
      final artist = artists.firstWhere((a) => a.id == sel.id, orElse: () => null as dynamic);
      if (artist != null) {
        items.add(RecentlyPlayedItem(
          id: artist.id,
          title: artist.name,
          subtitle: 'Artist',
          imageTag: artist.imageTag,
          type: RecentlyPlayedType.artist,
          lastPlayedAt: sel.timestamp,
        ));
      }
    } else if (sel.type == 'playlist') {
      final playlist = playlists.firstWhere((p) => p.id == sel.id, orElse: () => null as dynamic);
      if (playlist != null) {
        items.add(RecentlyPlayedItem(
          id: playlist.id,
          title: playlist.name,
          subtitle: '${playlist.trackCount} tracks',
          imageTag: playlist.imageTag,
          type: RecentlyPlayedType.playlist,
          lastPlayedAt: sel.timestamp,
        ));
      }
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
// New For You (recently-added unplayed albums)
// ---------------------------------------------------------------------------

final newAlbumsProvider = FutureProvider<List<JellyfinAlbum>>((ref) async {
  final service = ref.watch(jellyfinServiceProvider);
  if (service == null) return [];
  return service.getNewAlbums();
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
  final newAlbums = ref.watch(newAlbumsProvider).valueOrNull ?? [];

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

