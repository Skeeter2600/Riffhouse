import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/jellyfin_models.dart';
import 'auth_provider.dart';
import 'library_provider.dart';

class DownloadState {
  final Set<String> activeDownloadingIds;
  final Map<String, double> progressMap;
  final Map<String, ({int current, int total})> batchProgress;
  final Set<String> downloadedPlaylistIds;

  const DownloadState({
    this.activeDownloadingIds = const {},
    this.progressMap = const {},
    this.batchProgress = const {},
    this.downloadedPlaylistIds = const {},
  });

  DownloadState copyWith({
    Set<String>? activeDownloadingIds,
    Map<String, double>? progressMap,
    Map<String, ({int current, int total})>? batchProgress,
    Set<String>? downloadedPlaylistIds,
  }) {
    return DownloadState(
      activeDownloadingIds: activeDownloadingIds ?? this.activeDownloadingIds,
      progressMap: progressMap ?? this.progressMap,
      batchProgress: batchProgress ?? this.batchProgress,
      downloadedPlaylistIds:
          downloadedPlaylistIds ?? this.downloadedPlaylistIds,
    );
  }
}

class DownloadNotifier extends Notifier<DownloadState> {
  static const _downloadedPlaylistsPrefKey = 'downloaded_playlist_ids_v1';

  @override
  DownloadState build() {
    _loadDownloadedPlaylists();
    return const DownloadState();
  }

  Future<void> _loadDownloadedPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_downloadedPlaylistsPrefKey) ?? [];
    state = state.copyWith(downloadedPlaylistIds: ids.toSet());
    // Auto-prune temporary / unpinned tracks on startup
    await pruneUnpinnedTracks();
  }

  Future<void> _persistDownloadedPlaylists(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_downloadedPlaylistsPrefKey, ids.toList());
  }

  bool isPlaylistDownloaded(String playlistId) =>
      state.downloadedPlaylistIds.contains(playlistId);

  bool isDownloading(String trackId) =>
      state.activeDownloadingIds.contains(trackId);

  double? getProgress(String trackId) => state.progressMap[trackId];

  ({int current, int total})? getBatchProgress(String batchId) =>
      state.batchProgress[batchId];

  Future<bool> downloadSingleTrack(JellyfinTrack track) async {
    if (state.activeDownloadingIds.contains(track.id)) return false;

    final cacheService = ref.read(cacheServiceProvider);
    if (cacheService.isTrackCachedSync(track.id)) return true;

    final service = ref.read(jellyfinServiceProvider);
    final streamUrl =
        track.streamUrl ?? service?.getStreamUrl(track.id);
    if (streamUrl == null) return false;

    state = state.copyWith(
      activeDownloadingIds: {...state.activeDownloadingIds, track.id},
      progressMap: {...state.progressMap, track.id: 0.0},
    );

    try {
      await cacheService.downloadTrack(
        track.id,
        streamUrl,
        onProgress: (p) {
          state = state.copyWith(
            progressMap: {...state.progressMap, track.id: p},
          );
        },
      );
      ref.read(cachedTracksProvider.notifier).refresh();
      return true;
    } catch (_) {
      return false;
    } finally {
      final updatedIds = Set<String>.from(state.activeDownloadingIds)..remove(track.id);
      final updatedProgress = Map<String, double>.from(state.progressMap)..remove(track.id);
      state = state.copyWith(
        activeDownloadingIds: updatedIds,
        progressMap: updatedProgress,
      );
    }
  }

  Future<void> downloadPlaylist(String playlistId, List<JellyfinTrack> tracks) async {
    final updated = {...state.downloadedPlaylistIds, playlistId};
    state = state.copyWith(downloadedPlaylistIds: updated);
    await _persistDownloadedPlaylists(updated);

    final cacheService = ref.read(cacheServiceProvider);
    final service = ref.read(jellyfinServiceProvider);
    if (service == null) return;

    final uncached =
        tracks.where((t) => !cacheService.isTrackCachedSync(t.id)).toList();
    if (uncached.isEmpty) return;

    state = state.copyWith(
      batchProgress: {
        ...state.batchProgress,
        playlistId: (current: 0, total: uncached.length),
      },
    );

    int done = 0;
    for (final track in uncached) {
      await downloadSingleTrack(track);
      done++;
      state = state.copyWith(
        batchProgress: {
          ...state.batchProgress,
          playlistId: (current: done, total: uncached.length),
        },
      );
    }

    final updatedBatches =
        Map<String, ({int current, int total})>.from(state.batchProgress)
          ..remove(playlistId);
    state = state.copyWith(batchProgress: updatedBatches);
  }

  /// Toggle download for a playlist.
  Future<void> togglePlaylistDownload({
    required String playlistId,
    required List<JellyfinTrack> tracks,
    required bool enable,
  }) async {
    if (enable) {
      await downloadPlaylist(playlistId, tracks);
    } else {
      final updated = Set<String>.from(state.downloadedPlaylistIds)..remove(playlistId);
      state = state.copyWith(downloadedPlaylistIds: updated);
      await _persistDownloadedPlaylists(updated);
      await pruneUnpinnedTracks();
    }
  }

  /// Called when a track is added to a playlist (via search or smart recommendations).
  /// If this playlist is marked as downloaded, automatically download the track.
  Future<void> onTrackAddedToPlaylist(String playlistId, JellyfinTrack track) async {
    if (isPlaylistDownloaded(playlistId)) {
      await downloadSingleTrack(track);
    }
  }

  Future<void> removeDownloadedTrack(String trackId) async {
    final cacheService = ref.read(cacheServiceProvider);
    await cacheService.deleteCachedTrack(trackId);
    ref.read(cachedTracksProvider.notifier).refresh();
  }

  Future<void> removePlaylistDownloads(String playlistId, List<JellyfinTrack> tracks) async {
    final updated = Set<String>.from(state.downloadedPlaylistIds)..remove(playlistId);
    state = state.copyWith(downloadedPlaylistIds: updated);
    await _persistDownloadedPlaylists(updated);
    await pruneUnpinnedTracks();
  }

  /// Removes cached tracks that do not belong to any currently downloaded playlist.
  /// Returns the number of files pruned.
  Future<int> pruneUnpinnedTracks() async {
    final cacheService = ref.read(cacheServiceProvider);
    final allCached = await cacheService.getAllCachedTracks();
    if (allCached.isEmpty) return 0;

    // Collect all valid track IDs across all downloaded playlists
    final downloadedIds = state.downloadedPlaylistIds;
    final Set<String> pinnedTrackIds = {};

    for (final plId in downloadedIds) {
      try {
        final plTracks = await ref.read(playlistTracksProvider(plId).future);
        pinnedTrackIds.addAll(plTracks.map((t) => t.id));
      } catch (_) {
        // If playlist tracks can't be fetched, keep existing pinned to be safe
      }
    }

    int prunedCount = 0;
    for (final cached in allCached) {
      if (!pinnedTrackIds.contains(cached.jellyfinId)) {
        await cacheService.deleteCachedTrack(cached.jellyfinId);
        prunedCount++;
      }
    }

    if (prunedCount > 0) {
      ref.read(cachedTracksProvider.notifier).refresh();
    }
    return prunedCount;
  }
}

final downloadProvider =
    NotifierProvider<DownloadNotifier, DownloadState>(DownloadNotifier.new);
