import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/jellyfin_models.dart';
import '../utils/formatters.dart';
import 'auth_provider.dart';
import 'library_provider.dart';

class DownloadState {
  /// Tracks being downloaded right now.
  final Set<String> activeDownloadingIds;

  /// Tracks waiting for a free download slot.
  final Set<String> queuedIds;
  final Map<String, double> progressMap;

  /// Progress of each playlist or album download, keyed by its id.
  final Map<String, ({int current, int total})> batchProgress;
  final Set<String> downloadedPlaylistIds;
  final Set<String> downloadedAlbumIds;

  /// Tracks the user downloaded on their own or as part of an album. Like
  /// the tracks of downloaded playlists, these are never pruned.
  final Set<String> pinnedTrackIds;

  /// Only download on Wi-Fi or a wired connection.
  final bool wifiOnly;

  /// Stop downloading once this much is stored. Zero means no limit.
  final int storageLimitBytes;

  /// Why downloads stopped, if they did (no Wi-Fi, limit reached).
  final String? message;

  const DownloadState({
    this.activeDownloadingIds = const {},
    this.queuedIds = const {},
    this.progressMap = const {},
    this.batchProgress = const {},
    this.downloadedPlaylistIds = const {},
    this.downloadedAlbumIds = const {},
    this.pinnedTrackIds = const {},
    this.wifiOnly = false,
    this.storageLimitBytes = 0,
    this.message,
  });

  /// Number of tracks downloading or waiting to.
  int get pendingCount => activeDownloadingIds.length + queuedIds.length;

  DownloadState copyWith({
    Set<String>? activeDownloadingIds,
    Set<String>? queuedIds,
    Map<String, double>? progressMap,
    Map<String, ({int current, int total})>? batchProgress,
    Set<String>? downloadedPlaylistIds,
    Set<String>? downloadedAlbumIds,
    Set<String>? pinnedTrackIds,
    bool? wifiOnly,
    int? storageLimitBytes,
    String? message,
    bool clearMessage = false,
  }) {
    return DownloadState(
      activeDownloadingIds: activeDownloadingIds ?? this.activeDownloadingIds,
      queuedIds: queuedIds ?? this.queuedIds,
      progressMap: progressMap ?? this.progressMap,
      batchProgress: batchProgress ?? this.batchProgress,
      downloadedPlaylistIds:
          downloadedPlaylistIds ?? this.downloadedPlaylistIds,
      downloadedAlbumIds: downloadedAlbumIds ?? this.downloadedAlbumIds,
      pinnedTrackIds: pinnedTrackIds ?? this.pinnedTrackIds,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      storageLimitBytes: storageLimitBytes ?? this.storageLimitBytes,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

/// One track waiting for, or in the middle of, its download.
class _Job {
  final JellyfinTrack track;
  final String? batchId;
  final CancelToken token = CancelToken();
  final Completer<bool> done = Completer<bool>();
  bool cancelled = false;

  _Job(this.track, this.batchId);

  void cancel() {
    cancelled = true;
    if (!token.isCancelled) token.cancel();
  }
}

class DownloadNotifier extends Notifier<DownloadState> {
  static const _downloadedPlaylistsPrefKey = 'downloaded_playlist_ids_v1';
  static const _downloadedAlbumsPrefKey = 'downloaded_album_ids_v1';
  static const _pinnedTracksPrefKey = 'pinned_track_ids_v1';
  static const _wifiOnlyPrefKey = 'downloads_wifi_only';
  static const _storageLimitPrefKey = 'downloads_storage_limit_bytes';

  /// How many tracks download at the same time.
  static const maxConcurrent = 3;

  final Queue<_Job> _waiting = Queue<_Job>();
  final Map<String, _Job> _jobs = {};
  int _running = 0;

  @override
  DownloadState build() {
    _load();
    return const DownloadState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      downloadedPlaylistIds:
          (prefs.getStringList(_downloadedPlaylistsPrefKey) ?? []).toSet(),
      downloadedAlbumIds:
          (prefs.getStringList(_downloadedAlbumsPrefKey) ?? []).toSet(),
      pinnedTrackIds:
          (prefs.getStringList(_pinnedTracksPrefKey) ?? []).toSet(),
      wifiOnly: prefs.getBool(_wifiOnlyPrefKey) ?? false,
      storageLimitBytes: prefs.getInt(_storageLimitPrefKey) ?? 0,
    );
    // Auto-prune temporary / unpinned tracks on startup
    await pruneUnpinnedTracks();
  }

  Future<void> _persistSets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _downloadedPlaylistsPrefKey, state.downloadedPlaylistIds.toList());
    await prefs.setStringList(
        _downloadedAlbumsPrefKey, state.downloadedAlbumIds.toList());
    await prefs.setStringList(
        _pinnedTracksPrefKey, state.pinnedTrackIds.toList());
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  Future<void> setWifiOnly(bool enabled) async {
    state = state.copyWith(wifiOnly: enabled, clearMessage: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wifiOnlyPrefKey, enabled);
  }

  Future<void> setStorageLimitBytes(int bytes) async {
    state = state.copyWith(storageLimitBytes: bytes, clearMessage: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storageLimitPrefKey, bytes);
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  bool isPlaylistDownloaded(String playlistId) =>
      state.downloadedPlaylistIds.contains(playlistId);

  bool isAlbumDownloaded(String albumId) =>
      state.downloadedAlbumIds.contains(albumId);

  bool isDownloading(String trackId) =>
      state.activeDownloadingIds.contains(trackId) ||
      state.queuedIds.contains(trackId);

  double? getProgress(String trackId) => state.progressMap[trackId];

  ({int current, int total})? getBatchProgress(String batchId) =>
      state.batchProgress[batchId];

  // ---------------------------------------------------------------------------
  // Queue
  // ---------------------------------------------------------------------------

  /// Adds [track] to the download queue and completes with whether it ended
  /// up on disk.
  Future<bool> _enqueue(JellyfinTrack track, {String? batchId}) {
    final existing = _jobs[track.id];
    if (existing != null) return existing.done.future;

    if (ref.read(cacheServiceProvider).isTrackCachedSync(track.id)) {
      return Future.value(true);
    }

    final job = _Job(track, batchId);
    _jobs[track.id] = job;
    _waiting.add(job);
    state = state.copyWith(
      queuedIds: {...state.queuedIds, track.id},
      clearMessage: true,
    );
    _pump();
    return job.done.future;
  }

  void _pump() {
    while (_running < maxConcurrent && _waiting.isNotEmpty) {
      final job = _waiting.removeFirst();
      _running++;
      _run(job).whenComplete(() {
        _running--;
        _jobs.remove(job.track.id);
        _pump();
      });
    }
  }

  Future<void> _run(_Job job) async {
    final id = job.track.id;
    state = state.copyWith(queuedIds: {...state.queuedIds}..remove(id));

    var ok = false;
    try {
      if (job.cancelled) return;

      final blocked = await _blockedReason();
      if (blocked != null) {
        // Nothing else in the queue can proceed either.
        _cancelWaiting();
        state = state.copyWith(message: blocked);
        return;
      }

      final cacheService = ref.read(cacheServiceProvider);
      final service = ref.read(musicServiceProvider);
      final streamUrl = job.track.streamUrl ?? service?.getStreamUrl(id);
      if (streamUrl == null) return;

      state = state.copyWith(
        activeDownloadingIds: {...state.activeDownloadingIds, id},
        progressMap: {...state.progressMap, id: 0.0},
      );

      var shown = 0.0;
      await cacheService.downloadTrack(
        id,
        streamUrl,
        cancelToken: job.token,
        onProgress: (p) {
          // Whole-percent steps are plenty and keep rebuilds down.
          if (p - shown >= 0.01 || p >= 1) {
            shown = p;
            state = state.copyWith(progressMap: {...state.progressMap, id: p});
          }
        },
      );
      ok = true;
      ref.read(cachedTracksProvider.notifier).refresh();
    } catch (_) {
      // Failed or cancelled. The partial file stays so a retry resumes.
    } finally {
      state = state.copyWith(
        activeDownloadingIds: {...state.activeDownloadingIds}..remove(id),
        progressMap: {...state.progressMap}..remove(id),
      );
      job.done.complete(ok);
    }
  }

  void _cancelWaiting() {
    final ids = <String>{};
    while (_waiting.isNotEmpty) {
      final job = _waiting.removeFirst();
      ids.add(job.track.id);
      _jobs.remove(job.track.id);
      job.cancelled = true;
      job.done.complete(false);
    }
    if (ids.isNotEmpty) {
      state = state.copyWith(queuedIds: state.queuedIds.difference(ids));
    }
  }

  /// Why downloads cannot run right now, or null if they can.
  Future<String?> _blockedReason() async {
    if (state.wifiOnly && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final connections = await Connectivity().checkConnectivity();
        final unmetered = connections.contains(ConnectivityResult.wifi) ||
            connections.contains(ConnectivityResult.ethernet);
        if (!unmetered) {
          return 'Downloads are set to Wi-Fi only. Connect to Wi-Fi and try again.';
        }
      } catch (_) {
        // If the connection type cannot be read, do not block.
      }
    }

    final limit = state.storageLimitBytes;
    if (limit > 0) {
      final used = await ref.read(cacheServiceProvider).getCacheSizeBytes();
      if (used >= limit) {
        return 'Download limit of ${formatBytes(limit)} reached. '
            'Raise it in Settings or remove some downloads.';
      }
    }
    return null;
  }

  Future<void> _downloadBatch(String batchId, List<JellyfinTrack> tracks) async {
    final cacheService = ref.read(cacheServiceProvider);
    final uncached =
        tracks.where((t) => !cacheService.isTrackCachedSync(t.id)).toList();
    if (uncached.isEmpty) return;

    state = state.copyWith(
      batchProgress: {
        ...state.batchProgress,
        batchId: (current: 0, total: uncached.length),
      },
    );

    var done = 0;
    await Future.wait(uncached.map((track) async {
      await _enqueue(track, batchId: batchId);
      done++;
      if (state.batchProgress.containsKey(batchId)) {
        state = state.copyWith(
          batchProgress: {
            ...state.batchProgress,
            batchId: (current: done, total: uncached.length),
          },
        );
      }
    }));

    state = state.copyWith(
      batchProgress: {...state.batchProgress}..remove(batchId),
    );
  }

  // ---------------------------------------------------------------------------
  // Cancelling
  // ---------------------------------------------------------------------------

  void _cancelWhere(bool Function(_Job job) test) {
    final ids = <String>{};
    for (final job in _jobs.values.where(test).toList()) {
      job.cancel();
      // Running jobs finish through their cancel token; waiting ones are
      // simply dropped.
      if (_waiting.remove(job)) {
        ids.add(job.track.id);
        _jobs.remove(job.track.id);
        job.done.complete(false);
      }
    }
    if (ids.isNotEmpty) {
      state = state.copyWith(queuedIds: state.queuedIds.difference(ids));
    }
  }

  /// Stops a playlist or album download. Finished tracks are kept, and a
  /// later download picks up where this one stopped.
  void cancelBatch(String batchId) =>
      _cancelWhere((job) => job.batchId == batchId);

  void cancelAll() => _cancelWhere((_) => true);

  // ---------------------------------------------------------------------------
  // Tracks
  // ---------------------------------------------------------------------------

  /// Downloads [track] and keeps it until the user removes it.
  Future<bool> downloadSingleTrack(JellyfinTrack track) async {
    state = state.copyWith(pinnedTrackIds: {...state.pinnedTrackIds, track.id});
    await _persistSets();
    return _enqueue(track);
  }

  Future<void> removeDownloadedTrack(String trackId) async {
    _cancelWhere((job) => job.track.id == trackId);
    state = state.copyWith(
        pinnedTrackIds: {...state.pinnedTrackIds}..remove(trackId));
    await _persistSets();
    await ref.read(cacheServiceProvider).deleteCachedTrack(trackId);
    ref.read(cachedTracksProvider.notifier).refresh();
  }

  // ---------------------------------------------------------------------------
  // Playlists
  // ---------------------------------------------------------------------------

  Future<void> downloadPlaylist(String playlistId, List<JellyfinTrack> tracks) async {
    state = state.copyWith(
        downloadedPlaylistIds: {...state.downloadedPlaylistIds, playlistId});
    await _persistSets();
    await _downloadBatch(playlistId, tracks);
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
      await removePlaylistDownloads(playlistId, tracks);
    }
  }

  /// Called when a track is added to a playlist (via search or smart recommendations).
  /// If this playlist is marked as downloaded, automatically download the track.
  Future<void> onTrackAddedToPlaylist(String playlistId, JellyfinTrack track) async {
    if (isPlaylistDownloaded(playlistId)) {
      await _enqueue(track);
    }
  }

  Future<void> removePlaylistDownloads(String playlistId, List<JellyfinTrack> tracks) async {
    cancelBatch(playlistId);
    state = state.copyWith(
        downloadedPlaylistIds: {...state.downloadedPlaylistIds}
          ..remove(playlistId));
    await _persistSets();
    await pruneUnpinnedTracks();
  }

  // ---------------------------------------------------------------------------
  // Albums
  // ---------------------------------------------------------------------------

  Future<void> downloadAlbum(String albumId, List<JellyfinTrack> tracks) async {
    state = state.copyWith(
      downloadedAlbumIds: {...state.downloadedAlbumIds, albumId},
      pinnedTrackIds: {...state.pinnedTrackIds, ...tracks.map((t) => t.id)},
    );
    await _persistSets();
    await _downloadBatch(albumId, tracks);
  }

  Future<void> removeAlbumDownloads(String albumId, List<JellyfinTrack> tracks) async {
    cancelBatch(albumId);
    state = state.copyWith(
      downloadedAlbumIds: {...state.downloadedAlbumIds}..remove(albumId),
      pinnedTrackIds:
          state.pinnedTrackIds.difference(tracks.map((t) => t.id).toSet()),
    );
    await _persistSets();
    // Tracks that are also in a downloaded playlist survive the prune.
    await pruneUnpinnedTracks();
  }

  // ---------------------------------------------------------------------------
  // Housekeeping
  // ---------------------------------------------------------------------------

  /// Deletes every downloaded file and forgets what was marked for download.
  Future<void> clearAllDownloads() async {
    cancelAll();
    state = state.copyWith(
      downloadedPlaylistIds: const {},
      downloadedAlbumIds: const {},
      pinnedTrackIds: const {},
      clearMessage: true,
    );
    await _persistSets();
    await ref.read(cachedTracksProvider.notifier).clearAll();
  }

  /// Removes cached tracks that are neither pinned (downloaded on their own
  /// or with an album) nor part of a downloaded playlist: the songs the
  /// player cached while streaming. Returns the number of files pruned.
  Future<int> pruneUnpinnedTracks() async {
    final cacheService = ref.read(cacheServiceProvider);
    final allCached = await cacheService.getAllCachedTracks();
    if (allCached.isEmpty) return 0;

    // Collect all valid track IDs across all downloaded playlists. Pruning
    // deletes files, so it only goes ahead when every playlist could be read
    // from the server: offline, or with the server down, nothing is removed.
    final service = ref.read(musicServiceProvider);
    if (service == null) return 0;
    final Set<String> pinnedTrackIds = {...state.pinnedTrackIds};

    for (final plId in state.downloadedPlaylistIds) {
      try {
        final plTracks =
            await service.getPlaylistTracks(plId, throwOnError: true);
        pinnedTrackIds.addAll(plTracks.map((t) => t.id));
      } catch (_) {
        return 0;
      }
    }

    int prunedCount = 0;
    for (final cached in allCached) {
      if (!pinnedTrackIds.contains(cached.jellyfinId) &&
          !_jobs.containsKey(cached.jellyfinId)) {
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
