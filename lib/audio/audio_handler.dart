import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/jellyfin_models.dart';
import '../services/cache_service.dart';
import '../services/jellyfin_service.dart';
import '../services/playlist_service.dart';
import '../providers/library_provider.dart';
import 'android_auto_handler.dart';
import '../services/podcast_service.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_feed.dart';

/// Audio handler that integrates just_audio with audio_service, providing
/// background playback, media notifications, and Android Auto support.
class JellyfinAudioHandler extends BaseAudioHandler with QueueHandler {
  final AudioPlayer _player;
  final CacheService _cacheService;
  final PlaylistService _playlistService;
  late final AndroidAutoHandler _autoHandler;

  List<JellyfinTrack> _queue = [];
  int _currentIndex = 0;
  List<JellyfinTrack> _allTracksCache = [];
  String? _lastBrowsedContainerId;
  Future<List<JellyfinTrack>>? _inFlightAllTracksFetch;

  String? _currentSourceType;
  String? _currentSourceId;
  String? _currentSourceTitle;
  int? _originalSourceLength;
  bool _currentTrackCountedAsListen = false;

  List<JellyfinTrack> get currentQueue => List<JellyfinTrack>.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  String? get currentSourceType => _currentSourceType;
  String? get currentSourceId => _currentSourceId;
  String? get currentSourceTitle => _currentSourceTitle;

  /// Maps an artwork URL → local file path so we only download each image once.
  final Map<String, String> _artCache = {};
  final _dio = Dio();

  /// Subject map for active Android Auto browse nodes. Required to implement
  /// subscribeToChildren cleanly and avoid options null exceptions on Android.
  final Map<String, BehaviorSubject<Map<String, dynamic>>> _childrenSubjects = {};

  /// Set of URLs that are currently being downloaded to avoid duplicate requests.
  final Set<String> _pendingDownloads = {};

  /// Set of URLs that failed to download to avoid retrying them infinitely.
  final Set<String> _failedDownloads = {};

  JellyfinAudioHandler({
    required CacheService cacheService,
    required PlaylistService playlistService,
  })  : _player = AudioPlayer(),
        _cacheService = cacheService,
        _playlistService = playlistService {
    final svc = playlistService.jellyfinService;
    _autoHandler = AndroidAutoHandler(
      serverUrl: svc.serverUrl,
      accessToken: svc.accessToken,
      getCachedArtPath: (url) => _artCache[url],
      requestArtDownload: (url, parentId) => _requestArtDownload(url, parentId),
      toContentUri: (path) => _toContentUri(path),
    );
    _setupListeners();
    _loadSavedCredentials();
    _initAudioSession();
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  // ---------------------------------------------------------------------------
  // Listener wiring
  // ---------------------------------------------------------------------------

  void _setupListeners() {
    // Forward raw playback events → playbackState stream.
    _player.playbackEventStream.listen(
      _handlePlaybackEvent,
      onError: (Object e, StackTrace st) {
        // Surface errors without crashing the handler.
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
        ));
      },
    );

    // Keep mediaItem in sync with the currently active track.
    _player.currentIndexStream.listen((index) async {
      if (index != null && index < _queue.length) {
        _currentIndex = index;
        _currentTrackCountedAsListen = false;

        // If we advanced beyond the original album/playlist/search, clear source so UI shows "Now Playing"
        if (_originalSourceLength != null && index >= _originalSourceLength!) {
          _currentSourceType = 'queue';
          _currentSourceId = null;
          _currentSourceTitle = null;
        }

        // Publish immediately with the HTTPS art URL so UI shows something fast
        mediaItem.add(_trackToMediaItem(_queue[index]));
        _emitPlaybackState();

        // Pre-fetch the next track asynchronously.
        _prefetchNext(index);
        // Then asynchronously download art to a local file and republish
        // so Android Auto / notification shade can display it without auth headers.
        unawaited(_pushArtFromFile(_queue[index]));

        // Save state immediately on track change!
        unawaited(_savePlaybackState());
        unawaited(_savePlaybackPositionImmediately(Duration.zero));

        // If we are reaching the end of the queue, proactively queue smart continue tracks
        if (_queue.isNotEmpty && index >= _queue.length - 1) {
          unawaited(_handleSmartContinue(autoPlay: false));
        }
      }
    });

    // Re-emit playback state whenever the player state changes (play/pause/
    // buffering transitions).
    _player.playerStateStream.listen((state) {
      _emitPlaybackState();
      // Save state immediately on play/pause transition!
      unawaited(_savePlaybackState());

      // On track completion:
      if (state.processingState == ProcessingState.completed) {
        if (_queue.isNotEmpty && _currentIndex < _queue.length) {
          final currentTrack = _queue[_currentIndex];
          if (currentTrack.id.startsWith('podcast_')) {
            final guid = currentTrack.id.substring('podcast_'.length);
            final podcastService = PodcastService();
            unawaited(podcastService.markAsListened(guid, true));
          } else if (!_currentTrackCountedAsListen) {
            _currentTrackCountedAsListen = true;
            unawaited(_playlistService.recordPlay(currentTrack.jellyfinId));
          }
        }

        // Trigger smart continue on playback finish
        unawaited(_handleSmartContinue(autoPlay: true));
      }
    });

    // Save position periodically and count listen if threshold is met
    _player.positionStream.listen((pos) {
      _savePlaybackPosition(pos);

      // Check listen threshold for music tracks:
      // Counted if listened to by at least half (or 30 seconds, whichever is longer).
      if (!_currentTrackCountedAsListen &&
          _queue.isNotEmpty &&
          _currentIndex < _queue.length) {
        final currentTrack = _queue[_currentIndex];
        if (!currentTrack.id.startsWith('podcast_')) {
          final totalDuration = _player.duration ?? currentTrack.duration;
          if (totalDuration > Duration.zero) {
            Duration threshold;
            if (totalDuration <= const Duration(seconds: 30)) {
              threshold = Duration(milliseconds: totalDuration.inMilliseconds ~/ 2);
            } else {
              final half = Duration(milliseconds: totalDuration.inMilliseconds ~/ 2);
              threshold = half > const Duration(seconds: 30)
                  ? half
                  : const Duration(seconds: 30);
            }

            if (pos >= threshold) {
              _currentTrackCountedAsListen = true;
              unawaited(_playlistService.recordPlay(currentTrack.jellyfinId));
            }
          }
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Play a single [track], optionally with a surrounding [queue] starting at
  /// [queueIndex]. Replaces any existing queue.
  Future<void> playTrack(
    JellyfinTrack track, {
    List<JellyfinTrack>? queue,
    int queueIndex = 0,
    String? fromType,
    String? fromId,
    String? fromTitle,
  }) async {
    _queue = queue != null ? List<JellyfinTrack>.from(queue) : [track];
    _currentIndex = queueIndex;
    _originalSourceLength = queue != null ? queue.length : 1;
    _currentTrackCountedAsListen = false;
    _currentSourceType = fromType ?? 'track';
    _currentSourceId = fromId ?? track.id;
    _currentSourceTitle = fromTitle ?? track.title;

    // Publish the updated queue to audio_service.
    this.queue.add(_queue.map(_trackToMediaItem).toList());
    mediaItem.add(_trackToMediaItem(track));

    // Save state immediately
    unawaited(_savePlaybackState());
    unawaited(_savePlaybackPositionImmediately(Duration.zero));

    final sources = _queue.map(_buildAudioSource).toList();
    final concatenating = ConcatenatingAudioSource(children: sources);
    await _player.setAudioSource(concatenating, initialIndex: _currentIndex);
    await _player.play();
  }

  /// Build a [ConcatenatingAudioSource] from [tracks] and start playback at
  /// [startIndex]. Kicks off background pre-fetch for the next track.
  Future<void> playQueue(
    List<JellyfinTrack> tracks,
    int startIndex, {
    String? fromType,
    String? fromId,
    String? fromTitle,
  }) async {
    _queue = List<JellyfinTrack>.from(tracks);
    _currentIndex = startIndex;
    _originalSourceLength = tracks.length;
    _currentTrackCountedAsListen = false;
    _currentSourceType = fromType ?? 'queue';
    _currentSourceId = fromId;
    _currentSourceTitle = fromTitle;

    // Publish queue to audio_service.
    queue.add(tracks.map(_trackToMediaItem).toList());
    mediaItem.add(_trackToMediaItem(tracks[startIndex]));

    // Save state immediately
    unawaited(_savePlaybackState());
    unawaited(_savePlaybackPositionImmediately(Duration.zero));

    final sources = tracks.map(_buildAudioSource).toList();
    final concatenating = ConcatenatingAudioSource(children: sources);

    await _player.setAudioSource(
      concatenating,
      initialIndex: startIndex,
    );
    await _player.play();

    _prefetchNext(startIndex);
  }

  // ---------------------------------------------------------------------------
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    final currentMedia = mediaItem.value;
    if (currentMedia != null && currentMedia.id.startsWith('podcast_')) {
      final currentPos = _player.position;
      final duration = _player.duration ?? Duration.zero;
      final target = currentPos + const Duration(seconds: 15);
      if (duration > Duration.zero && target >= duration) {
        await _handleSmartContinue(autoPlay: true);
      } else {
        await seek(target < duration ? target : duration);
      }
    } else {
      if (!_player.hasNext || _currentIndex >= _queue.length - 1) {
        await _handleSmartContinue(autoPlay: true);
      } else {
        await _player.seekToNext();
      }
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final currentMedia = mediaItem.value;
    if (currentMedia != null && currentMedia.id.startsWith('podcast_')) {
      final currentPos = _player.position;
      final target = currentPos - const Duration(seconds: 15);
      await seek(target > Duration.zero ? target : Duration.zero);
    } else {
      // If we are more than 5 seconds into the song, rewind to beginning
      if (_player.position > const Duration(seconds: 5)) {
        await seek(Duration.zero);
      } else {
        await _player.seekToPrevious();
      }
    }
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    await _savePlaybackPositionImmediately(position);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  void updateAndroidAutoCredentials(String url, String token) {
    _autoHandler.updateCredentials(url, token);
  }

  void updateAndroidAutoLibrary({
    required List<JellyfinPlaylist> playlists,
    required List<JellyfinAlbum> albums,
    required List<JellyfinArtist> artists,
    required Map<String, List<JellyfinTrack>> tracksByContainer,
    List<RecentlyPlayedItem> recentlyPlayed = const [],
    List<JellyfinAlbum> newAlbums = const [],
  }) {
    _autoHandler.updateLibrary(
      playlists,
      albums,
      artists,
      tracksByContainer,
      recentlyPlayed: recentlyPlayed,
      newAlbums: newAlbums,
    );
    _notifyChildrenChanged(AudioService.browsableRootId);
    _notifyChildrenChanged(kRootHome);
    _notifyChildrenChanged(kRootPlaylists);
    _notifyChildrenChanged(kRootAlbums);
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    // Record last browsed container
    if (parentMediaId.startsWith(kPrefixPlaylist) ||
        parentMediaId.startsWith(kPrefixAlbum) ||
        parentMediaId.startsWith('smart_mix_')) {
      _lastBrowsedContainerId = parentMediaId;
    }

    // Dynamic background loading for playlist/album tracks if not cached
    if (parentMediaId.startsWith(kPrefixPlaylist)) {
      final playlistId = parentMediaId.substring(kPrefixPlaylist.length);
      if (!_autoHandler.hasContainer(parentMediaId)) {
        try {
          final tracks = await _playlistService.jellyfinService.getPlaylistTracks(playlistId);
          _autoHandler.updateContainer(parentMediaId, tracks);
          _notifyChildrenChanged(parentMediaId);
        } catch (_) {
          // Ignore error
        }
      }
    } else if (parentMediaId.startsWith(kPrefixAlbum)) {
      final albumId = parentMediaId.substring(kPrefixAlbum.length);
      if (!_autoHandler.hasContainer(parentMediaId)) {
        try {
          final tracks = await _playlistService.jellyfinService.getAlbumTracks(albumId);
          _autoHandler.updateContainer(parentMediaId, tracks);
          _notifyChildrenChanged(parentMediaId);
        } catch (_) {
          // Ignore error
        }
      }
    } else if (parentMediaId.startsWith('smart_mix_')) {
      if (!_autoHandler.hasContainer(parentMediaId)) {
        unawaited(() async {
          try {
            List<JellyfinTrack> libraryTracks;
            if (_allTracksCache.isNotEmpty) {
              libraryTracks = _allTracksCache;
            } else if (_inFlightAllTracksFetch != null) {
              libraryTracks = await _inFlightAllTracksFetch!;
            } else {
              _inFlightAllTracksFetch = _playlistService.jellyfinService.getTracks();
              libraryTracks = await _inFlightAllTracksFetch!;
              _allTracksCache = libraryTracks;
              _inFlightAllTracksFetch = null;
            }

            List<JellyfinTrack> mixTracks = [];
            if (parentMediaId == 'smart_mix_daily') {
              mixTracks = await _playlistService.getSmartMix(libraryTracks: libraryTracks);
            } else if (parentMediaId == 'smart_mix_heavy_rotation') {
              mixTracks = await _playlistService.getHeavyRotation(libraryTracks: libraryTracks);
            } else if (parentMediaId == 'smart_mix_undiscovered') {
              mixTracks = await _playlistService.getUndiscovered(libraryTracks: libraryTracks);
            }
            _autoHandler.updateContainer(parentMediaId, mixTracks);
            _notifyChildrenChanged(parentMediaId);
          } catch (_) {
            // Ignore error
          }
        }());
      }
    }
    return _autoHandler.getChildren(parentMediaId, options);
  }

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    return _autoHandler.searchLocal(query);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.group:
      case AudioServiceRepeatMode.all:
        await _player.setLoopMode(LoopMode.all);
        break;
    }
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    await _savePlaybackState();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    await _player.setShuffleModeEnabled(enabled);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    await _savePlaybackState();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Pre-fetch the track after [currentIndex] so it is ready for gapless
  /// playback. Runs entirely in the background – callers must NOT await this.
  Future<void> _prefetchNext(int currentIndex) async {
    final nextIndex = currentIndex + 1;
    if (nextIndex >= _queue.length) return;

    // Delay pre-fetch to prevent network saturation while the current track buffers.
    await Future.delayed(const Duration(seconds: 5));

    // Ensure the track hasn't changed or skipped during the delay.
    if (_player.currentIndex != currentIndex || nextIndex >= _queue.length) return;

    final nextTrack = _queue[nextIndex];
    if (nextTrack.id.startsWith('podcast_')) return; // Skip prefetching for podcast episodes
    final isCached = _cacheService.isTrackCachedSync(nextTrack.jellyfinId);
    if (!isCached) {
      final streamUrl = _playlistService.jellyfinService.getStreamUrl(nextTrack.jellyfinId);
      // Fire-and-forget: start downloading without blocking playback.
      unawaited(_cacheService.downloadTrack(nextTrack.jellyfinId, streamUrl));
    }
  }

  /// Returns a standard [AudioSource.uri] for streaming or
  /// an [AudioSource.file] when the track is already fully cached.
  AudioSource _buildAudioSource(JellyfinTrack track) {
    if (track.streamUrl != null) {
      return AudioSource.uri(Uri.parse(track.streamUrl!), tag: _trackToMediaItem(track));
    }
    final cachedPath = _cacheService.getCachedPathSync(track.jellyfinId);
    if (cachedPath != null) {
      return AudioSource.file(cachedPath, tag: _trackToMediaItem(track));
    }

    final streamUrl = _playlistService.jellyfinService.getStreamUrl(track.jellyfinId);
    final streamUri = Uri.parse(streamUrl);
    return AudioSource.uri(
      streamUri,
      tag: _trackToMediaItem(track),
    );
  }

  MediaItem _trackToMediaItem(JellyfinTrack track) {
    final svc = _playlistService.jellyfinService;
    final streamUrl = track.streamUrl ?? svc.getStreamUrl(track.jellyfinId);

    // Build the most reliable art URL:
    // 1. Use the track's own imageTag (best — direct image reference)
    // 2. Fall back to the album art URL (album-level image)
    // 3. No art if albumId is also empty
    Uri? artUri;
    if (track.id.startsWith('podcast_')) {
      artUri = track.imageTag != null ? Uri.parse(track.imageTag!) : null;
    } else {
      if (track.imageTag != null && track.imageTag!.isNotEmpty) {
        artUri = Uri.parse(svc.getImageUrl(track.id, track.imageTag!));
      } else if (track.albumId.isNotEmpty) {
        artUri = Uri.parse(svc.getAlbumArtUrl(track.albumId));
      }
    }

    // If we've already cached the artwork as a local file, use that URI instead
    // so Android Auto can load it without auth headers
    final cachedArtKey = artUri?.toString();
    if (cachedArtKey != null && _artCache.containsKey(cachedArtKey)) {
      final contentUriStr = _toContentUri(_artCache[cachedArtKey]!);
      artUri = Uri.parse(contentUriStr);
    }

    return MediaItem(
      id: track.jellyfinId,
      title: track.title,
      album: track.album,
      artist: track.artist,
      duration: track.duration,
      artUri: artUri,
      extras: {'streamUrl': streamUrl},
    );
  }

  /// Downloads artwork for [track] to a local temp file and re-publishes the
  /// [mediaItem] with a `file://` URI so Android Auto and the system notification
  /// shade can load it without needing HTTP auth headers in the request.
  Future<void> _pushArtFromFile(JellyfinTrack track) async {
    final svc = _playlistService.jellyfinService;
    Uri? remoteUri;
    if (track.id.startsWith('podcast_')) {
      remoteUri = track.imageTag != null ? Uri.parse(track.imageTag!) : null;
    } else {
      if (track.imageTag != null && track.imageTag!.isNotEmpty) {
        remoteUri = Uri.parse(svc.getImageUrl(track.id, track.imageTag!));
      } else if (track.albumId.isNotEmpty) {
        remoteUri = Uri.parse(svc.getAlbumArtUrl(track.albumId));
      }
    }
    if (remoteUri == null) return;

    final remoteUrl = remoteUri.toString();

    // Return early if already cached
    if (_artCache.containsKey(remoteUrl)) {
      _republishMediaItemWithFileArt(track, _artCache[remoteUrl]!);
      return;
    }

    try {
      // First try to check the mobile view's CachedNetworkImage cache!
      final fileInfo = await DefaultCacheManager().getFileFromCache(remoteUrl);
      if (fileInfo != null && await fileInfo.file.exists()) {
        _artCache[remoteUrl] = fileInfo.file.path;
        if (_queue.isNotEmpty &&
            _currentIndex < _queue.length &&
            _queue[_currentIndex].id == track.id) {
          _republishMediaItemWithFileArt(track, fileInfo.file.path);
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final filename = 'art_${remoteUrl.hashCode.abs()}.jpg';
      final file = File('${dir.path}/$filename');

      if (!await file.exists()) {
        final response = await _dio.get<List<int>>(
          remoteUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        await file.writeAsBytes(response.data!);
      }

      _artCache[remoteUrl] = file.path;

      // Only re-publish if this track is still the active one
      if (_queue.isNotEmpty &&
          _currentIndex < _queue.length &&
          _queue[_currentIndex].id == track.id) {
        _republishMediaItemWithFileArt(track, file.path);
      }
    } catch (_) {
      // Ignore error
    }
  }

  void _republishMediaItemWithFileArt(JellyfinTrack track, String filePath) {
    final svc = _playlistService.jellyfinService;
    final streamUrl = track.streamUrl ?? svc.getStreamUrl(track.jellyfinId);
    final contentUriStr = _toContentUri(filePath);
    mediaItem.add(MediaItem(
      id: track.jellyfinId,
      title: track.title,
      album: track.album,
      artist: track.artist,
      duration: track.duration,
      artUri: Uri.parse(contentUriStr),
      extras: {'streamUrl': streamUrl},
    ));
  }

  /// Translates a just_audio [PlaybackEvent] into an audio_service
  /// [PlaybackState] and pushes it to the [playbackState] stream.
  void _handlePlaybackEvent(PlaybackEvent event) {
    _emitPlaybackState();
  }

  /// Builds and emits the current [PlaybackState] from [_player]'s state.
  void _emitPlaybackState() {
    final playerState = _player.playerState;
    final processingState = _mapProcessingState(playerState.processingState);

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playerState.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToQueueItem,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: playerState.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex,
    ));
  }

  /// Maps just_audio's [ProcessingState] to audio_service's
  /// [AudioProcessingState].
  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  // ---------------------------------------------------------------------------
  // Background Isolate Credentials & Library Loader
  // ---------------------------------------------------------------------------

  Future<void> _loadSavedCredentials() async {
    try {
      final config = await _playlistService.db.getServerConfig();
      if (config != null && config.serverUrl.isNotEmpty && config.accessToken.isNotEmpty) {
        _playlistService.jellyfinService = JellyfinService(
          serverUrl: config.serverUrl,
          accessToken: config.accessToken,
          userId: config.userId,
        );
        _autoHandler.updateCredentials(config.serverUrl, config.accessToken);
        await _loadLibraryFromDb();
        await _restorePlaybackState();
      }
    } catch (_) {
      // Ignore error
    }
  }

  Future<void> _loadLibraryFromDb() async {
    try {
      final svc = _playlistService.jellyfinService;
      if (svc.serverUrl == 'http://localhost' || svc.accessToken.isEmpty) return;

      // Load local playlists
      final localPlaylists = await _playlistService.db.getAllLocalPlaylists();
      final playlists = localPlaylists.map((lp) {
        int count = 0;
        try {
          final List<dynamic> ids = jsonDecode(lp.trackIdsJson);
          count = ids.length;
        } catch (_) {}
        return JellyfinPlaylist(
          id: lp.jellyfinId,
          name: lp.name,
          trackCount: count,
          imageTag: null,
        );
      }).toList();

      // Fetch albums & artists in the background
      final albums = await svc.getAlbums();
      final artists = await svc.getArtists();

      // Fetch new albums
      List<JellyfinAlbum> newAlbums = [];
      try {
        newAlbums = await svc.getNewAlbums();
      } catch (_) {
        // Ignore error
      }

      // Load recently played from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('recent_selections');
      final List<RecentlyPlayedItem> recentlyPlayed = [];
      if (jsonStr != null) {
        try {
          final List<dynamic> list = jsonDecode(jsonStr);
          for (final item in list) {
            final id = item['id'] as String;
            final type = item['type'] as String;
            if (type == 'album') {
              final album = albums.cast<JellyfinAlbum?>().firstWhere((a) => a?.id == id, orElse: () => null);
              if (album != null) {
                recentlyPlayed.add(RecentlyPlayedItem(
                  id: album.id,
                  title: album.name,
                  subtitle: album.artist,
                  imageTag: album.imageTag,
                  type: RecentlyPlayedType.album,
                  lastPlayedAt: DateTime.fromMillisecondsSinceEpoch(item['timestamp'] as int),
                ));
              }
            } else if (type == 'artist') {
              final artist = artists.cast<JellyfinArtist?>().firstWhere((a) => a?.id == id, orElse: () => null);
              if (artist != null) {
                recentlyPlayed.add(RecentlyPlayedItem(
                  id: artist.id,
                  title: artist.name,
                  subtitle: 'Artist',
                  imageTag: artist.imageTag,
                  type: RecentlyPlayedType.artist,
                  lastPlayedAt: DateTime.fromMillisecondsSinceEpoch(item['timestamp'] as int),
                ));
              }
            } else if (type == 'playlist') {
              final playlist = playlists.cast<JellyfinPlaylist?>().firstWhere((p) => p?.id == id, orElse: () => null);
              if (playlist != null) {
                recentlyPlayed.add(RecentlyPlayedItem(
                  id: playlist.id,
                  title: playlist.name,
                  subtitle: 'Playlist',
                  imageTag: playlist.imageTag,
                  type: RecentlyPlayedType.playlist,
                  lastPlayedAt: DateTime.fromMillisecondsSinceEpoch(item['timestamp'] as int),
                ));
              }
            }
          }
        } catch (_) {
          // Ignore error
        }
      }

      // Load cached tracks from database to populate background cache
      final localTracks = await _playlistService.db.getAllLocalTracks();
      _allTracksCache = localTracks.map((local) {
        List<String> artistsList = [];
        List<String> genresList = [];
        try {
          artistsList = List<String>.from(jsonDecode(local.artistsJson));
        } catch (_) {}
        try {
          genresList = List<String>.from(jsonDecode(local.genresJson));
        } catch (_) {}
        return JellyfinTrack(
          id: local.jellyfinId,
          name: local.name,
          artists: artistsList,
          albumArtist: local.albumArtist,
          albumId: local.albumId,
          albumName: local.albumName,
          genres: genresList,
          durationMs: local.durationMs,
          serverId: local.serverId,
          imageTag: local.imageTag,
          dateCreated: local.dateCreated,
        );
      }).toList();

      _autoHandler.updateLibrary(
        playlists,
        albums,
        artists,
        {},
        recentlyPlayed: recentlyPlayed,
        newAlbums: newAlbums,
      );
      _notifyChildrenChanged(AudioService.browsableRootId);
      _notifyChildrenChanged(kRootHome);
      _notifyChildrenChanged(kRootPlaylists);
      _notifyChildrenChanged(kRootAlbums);

      // If local cache is empty, eagerly fetch from server and populate DB
      if (_allTracksCache.isEmpty) {
        _inFlightAllTracksFetch = svc.getTracks();
        unawaited(() async {
          try {
            final tracks = await _inFlightAllTracksFetch!;
            _allTracksCache = tracks;

            final companions = tracks.map((track) => LocalTracksCompanion(
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
            )).toList();
            await _playlistService.db.bulkInsertLocalTracks(companions);

          } catch (_) {
            // Ignore error
          } finally {
            _inFlightAllTracksFetch = null;
          }
        }());
      }
    } catch (_) {
      // Ignore error
    }
  }

  /// Records a selection to SharedPreferences directly from the background service context
  Future<void> _recordSelection(String id, String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('recent_selections');
      List<dynamic> list = [];
      if (jsonStr != null) {
        try {
          list = jsonDecode(jsonStr);
        } catch (_) {}
      }
      list.removeWhere((item) => item['id'] == id && item['type'] == type);
      list.insert(0, {
        'id': id,
        'type': type,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      await prefs.setString('recent_selections', jsonEncode(list.take(20).toList()));
    } catch (_) {
      // Ignore error
    }
  }

  // ---------------------------------------------------------------------------
  // Playback overrides for Android Auto
  // ---------------------------------------------------------------------------

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    // Handle artist play all
    if (mediaId.startsWith('artist_play_all_')) {
      final artistId = mediaId.substring('artist_play_all_'.length);
      try {
        final artistTracks = await _playlistService.jellyfinService.getArtistTracks(artistId);
        if (artistTracks.isNotEmpty) {
          unawaited(_recordSelection(artistId, 'artist'));
          final artistName = artistTracks.first.artists.firstOrNull ?? 'Artist';
          await playQueue(
            artistTracks,
            0,
            fromType: 'artist',
            fromId: artistId,
            fromTitle: artistName,
          );
        }
      } catch (_) {
        // Ignore error
      }
      return;
    }

    // 1. Handle smart mixes
    if (mediaId == 'smart_mix_daily' || mediaId == 'smart_mix_heavy_rotation' || mediaId == 'smart_mix_undiscovered') {
      try {
        List<JellyfinTrack> libraryTracks;
        if (_allTracksCache.isNotEmpty) {
          libraryTracks = _allTracksCache;
        } else if (_inFlightAllTracksFetch != null) {
          libraryTracks = await _inFlightAllTracksFetch!;
        } else {
          _inFlightAllTracksFetch = _playlistService.jellyfinService.getTracks();
          libraryTracks = await _inFlightAllTracksFetch!;
          _allTracksCache = libraryTracks;
          _inFlightAllTracksFetch = null;
        }
        List<JellyfinTrack> mixTracks = [];
        if (mediaId == 'smart_mix_daily') {
          mixTracks = await _playlistService.getSmartMix(libraryTracks: libraryTracks);
        } else if (mediaId == 'smart_mix_heavy_rotation') {
          mixTracks = await _playlistService.getHeavyRotation(libraryTracks: libraryTracks);
        } else if (mediaId == 'smart_mix_undiscovered') {
          mixTracks = await _playlistService.getUndiscovered(libraryTracks: libraryTracks);
        }
        if (mixTracks.isNotEmpty) {
          final mixName = mediaId == 'smart_mix_daily'
              ? 'Daily Mix'
              : mediaId == 'smart_mix_heavy_rotation'
                  ? 'Heavy Rotation'
                  : 'Undiscovered';
          await playQueue(
            mixTracks,
            0,
            fromType: 'smart_mix',
            fromId: mediaId,
            fromTitle: mixName,
          );
        }
      } catch (_) {
        // Ignore error
      }
      return;
    }

    // 2. Resolve container ID
    String? containerId = extras?.containsKey('containerId') == true ? extras!['containerId'] as String? : null;

    if (containerId == null) {
      // Heuristic 1: check if the track is in the container the user is currently browsing
      if (_lastBrowsedContainerId != null) {
        final tracks = _autoHandler.getTracksForContainer(_lastBrowsedContainerId!);
        if (tracks.any((t) => t.id == mediaId)) {
          containerId = _lastBrowsedContainerId;
        }
      }
      
      // Heuristic 2: fall back to mapping scan
      containerId ??= _autoHandler.findContainerForTrack(mediaId);
    }

    if (containerId != null) {
      final tracks = _autoHandler.getTracksForContainer(containerId);
      if (tracks.isNotEmpty) {
        final index = tracks.indexWhere((t) => t.id == mediaId);
        if (index != -1) {
          // Record selection
          String? fromType;
          String? fromId;
          String? fromTitle;

          if (containerId.startsWith(kPrefixAlbum)) {
            fromId = containerId.substring(kPrefixAlbum.length);
            unawaited(_recordSelection(fromId, 'album'));
            fromType = 'album';
            fromTitle = tracks[index].albumName;
          } else if (containerId.startsWith(kPrefixPlaylist)) {
            fromId = containerId.substring(kPrefixPlaylist.length);
            unawaited(_recordSelection(fromId, 'playlist'));
            fromType = 'playlist';
            final lp = await _playlistService.db.getLocalPlaylist(fromId);
            fromTitle = lp?.name ?? 'Playlist';
          } else if (containerId.startsWith(kPrefixArtist)) {
            fromId = containerId.substring(kPrefixArtist.length);
            unawaited(_recordSelection(fromId, 'artist'));
            fromType = 'artist';
            fromTitle = tracks[index].artists.firstOrNull ?? tracks[index].albumArtist;
          }

          try {
            await playQueue(
              tracks,
              index,
              fromType: fromType,
              fromId: fromId,
              fromTitle: fromTitle,
            );
          } catch (_) {
            // Ignore error
          }
          return;
        }
      }
    }

    // 3. Fallback: play single track
    try {
      var track = _autoHandler.findTrackById(mediaId);
      track ??= await _playlistService.jellyfinService.getTrack(mediaId);

      if (track != null) {
        if (track.albumId.isNotEmpty) {
          unawaited(_recordSelection(track.albumId, 'album'));
        }
        await playTrack(
          track,
          fromType: 'track',
          fromId: track.id,
          fromTitle: track.title,
        );
      }
    } catch (_) {
      // Ignore error
    }
  }

  // ---------------------------------------------------------------------------
  // Custom Browse Tree Notifications (Workaround for audio_service Android bug)
  // ---------------------------------------------------------------------------

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
    return _childrenSubjects.putIfAbsent(
      parentMediaId,
      () => BehaviorSubject.seeded(<String, dynamic>{}),
    );
  }

  void _notifyChildrenChanged(String parentMediaId) {
    final subject = _childrenSubjects[parentMediaId];
    if (subject != null) {
      subject.add(<String, dynamic>{});
    }
  }

  /// Downloads artwork in the background for browse list items and notifies the
  /// corresponding browse node to refresh once the image is ready.
  void _requestArtDownload(String remoteUrl, String parentId) {
    if (_artCache.containsKey(remoteUrl)) return;
    if (_pendingDownloads.contains(remoteUrl)) return;
    if (_failedDownloads.contains(remoteUrl)) return;

    _pendingDownloads.add(remoteUrl);

    unawaited(() async {
      try {
        // Try to load the file from the mobile view's cache manager first!
        final fileInfo = await DefaultCacheManager().getFileFromCache(remoteUrl);
        if (fileInfo != null && await fileInfo.file.exists()) {
          _artCache[remoteUrl] = fileInfo.file.path;
          _pendingDownloads.remove(remoteUrl);
          _notifyChildrenChanged(parentId);
          return;
        }

        final dir = await getTemporaryDirectory();
        final filename = 'art_${remoteUrl.hashCode.abs()}.jpg';
        final file = File('${dir.path}/$filename');

        if (!await file.exists()) {
          final response = await _dio.get<List<int>>(
            remoteUrl,
            options: Options(responseType: ResponseType.bytes),
          );
          await file.writeAsBytes(response.data!);
        }
        
        _artCache[remoteUrl] = file.path;
        _pendingDownloads.remove(remoteUrl);
        _notifyChildrenChanged(parentId);
      } catch (_) {
        _pendingDownloads.remove(remoteUrl);
        _failedDownloads.add(remoteUrl);
      }
    }());
  }

  /// Maps a local filesystem file path to a ContentProvider content:// URI
  /// exposed by com.riffhouse.mobile_music_player.publicfileprovider.
  String _toContentUri(String filePath) {
    if (filePath.startsWith('content://')) return filePath;
    
    if (filePath.contains('/cache/')) {
      final parts = filePath.split('/cache/');
      final relativePath = parts.sublist(1).join('/cache/');
      return 'content://com.riffhouse.mobile_music_player.publicfileprovider/cache/$relativePath';
    }
    
    if (filePath.contains('/app_flutter/')) {
      final parts = filePath.split('/app_flutter/');
      final relativePath = parts.sublist(1).join('/app_flutter/');
      return 'content://com.riffhouse.mobile_music_player.publicfileprovider/files/$relativePath';
    }

    if (filePath.contains('/files/')) {
      final parts = filePath.split('/files/');
      final relativePath = parts.sublist(1).join('/files/');
      return 'content://com.riffhouse.mobile_music_player.publicfileprovider/files/$relativePath';
    }
    
    return filePath;
  }

  // ---------------------------------------------------------------------------
  // Playback State Persistence (Save & Restore)
  // ---------------------------------------------------------------------------

  DateTime _lastSaveTime = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _savePlaybackState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tracksJson = _queue.map((t) => {
        'id': t.id,
        'name': t.name,
        'artists': t.artists,
        'albumArtist': t.albumArtist,
        'albumId': t.albumId,
        'albumName': t.albumName,
        'genres': t.genres,
        'durationMs': t.durationMs,
        'serverId': t.serverId,
        'imageTag': t.imageTag,
        'dateCreated': t.dateCreated?.toIso8601String(),
        'remoteStreamUrl': t.remoteStreamUrl,
      }).toList();

      await prefs.setString('playback_queue_tracks', jsonEncode(tracksJson));
      await prefs.setInt('playback_queue_index', _currentIndex);
      await prefs.setInt('playback_shuffle_mode', _player.shuffleModeEnabled ? 1 : 0);
      await prefs.setInt('playback_repeat_mode', _player.loopMode.index);

      if (_currentSourceType != null) {
        await prefs.setString('playback_source_type', _currentSourceType!);
      } else {
        await prefs.remove('playback_source_type');
      }
      if (_currentSourceId != null) {
        await prefs.setString('playback_source_id', _currentSourceId!);
      } else {
        await prefs.remove('playback_source_id');
      }
      if (_currentSourceTitle != null) {
        await prefs.setString('playback_source_title', _currentSourceTitle!);
      } else {
        await prefs.remove('playback_source_title');
      }
    } catch (_) {
      // Ignore error
    }
  }

  void _savePlaybackPosition(Duration position) async {
    final now = DateTime.now();
    if (now.difference(_lastSaveTime) > const Duration(seconds: 5)) {
      _lastSaveTime = now;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('playback_position_ms', position.inMilliseconds);
      } catch (_) {
        // Ignore error
      }
    }
  }

  Future<void> _savePlaybackPositionImmediately(Duration position) async {
    _lastSaveTime = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('playback_position_ms', position.inMilliseconds);
    } catch (_) {
      // Ignore error
    }
  }

  Future<void> _restorePlaybackState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueStr = prefs.getString('playback_queue_tracks');
      if (queueStr == null || queueStr.isEmpty) return;

      final List<dynamic> queueList = jsonDecode(queueStr);
      final tracks = queueList.map((item) {
        final dateCreatedStr = item['dateCreated'] as String?;
        final dateCreated = dateCreatedStr != null ? DateTime.tryParse(dateCreatedStr) : null;
        return JellyfinTrack(
          id: item['id'] as String,
          name: item['name'] as String,
          artists: List<String>.from(item['artists'] as List? ?? []),
          albumArtist: item['albumArtist'] as String? ?? '',
          albumId: item['albumId'] as String? ?? '',
          albumName: item['albumName'] as String? ?? '',
          genres: List<String>.from(item['genres'] as List? ?? []),
          durationMs: item['durationMs'] as int? ?? 0,
          serverId: item['serverId'] as String? ?? '',
          imageTag: item['imageTag'] as String?,
          dateCreated: dateCreated,
          remoteStreamUrl: item['remoteStreamUrl'] as String?,
        );
      }).toList();

      if (tracks.isEmpty) return;

      final index = prefs.getInt('playback_queue_index') ?? 0;
      final positionMs = prefs.getInt('playback_position_ms') ?? 0;
      final shuffleModeInt = prefs.getInt('playback_shuffle_mode') ?? 0;
      final repeatModeInt = prefs.getInt('playback_repeat_mode') ?? 0;

      _currentSourceType = prefs.getString('playback_source_type');
      _currentSourceId = prefs.getString('playback_source_id');
      _currentSourceTitle = prefs.getString('playback_source_title');

      _queue = List<JellyfinTrack>.from(tracks);
      _currentIndex = index;

      // Publish the restored queue and active item to audio_service
      queue.add(_queue.map(_trackToMediaItem).toList());
      if (_currentIndex < _queue.length) {
        mediaItem.add(_trackToMediaItem(_queue[_currentIndex]));
        unawaited(_pushArtFromFile(_queue[_currentIndex]));
      }

      // Restore loop mode and shuffle mode on the player
      final loopMode = LoopMode.values[repeatModeInt];
      await _player.setLoopMode(loopMode);
      await _player.setShuffleModeEnabled(shuffleModeInt == 1);

      // Map to AudioService enum to update playbackState
      final repeatMode = repeatModeInt == 0
          ? AudioServiceRepeatMode.none
          : repeatModeInt == 1
              ? AudioServiceRepeatMode.one
              : AudioServiceRepeatMode.all;
      final shuffleMode = shuffleModeInt == 1
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none;

      // Set audio source but do NOT play
      final sources = tracks.map(_buildAudioSource).toList();
      final concatenating = ConcatenatingAudioSource(children: sources);
      await _player.setAudioSource(
        concatenating,
        initialIndex: _currentIndex,
        initialPosition: Duration(milliseconds: positionMs),
      );

      // Emit initial playbackState so UI is updated
      _emitPlaybackState();

      // Update custom modes in playbackState
      playbackState.add(playbackState.value.copyWith(
        repeatMode: repeatMode,
        shuffleMode: shuffleMode,
      ));

    } catch (_) {
      // Ignore error
    }
  }

  // ---------------------------------------------------------------------------
  // Smart Continue
  // ---------------------------------------------------------------------------

  bool _isSmartContinueLoading = false;

  Future<void> _handleSmartContinue({bool autoPlay = false}) async {
    if (_isSmartContinueLoading) return;
    if (_queue.isEmpty) return;

    _isSmartContinueLoading = true;
    try {
      final currentTrack =
          _queue[_currentIndex < _queue.length ? _currentIndex : _queue.length - 1];
      final isPodcast = currentTrack.id.startsWith('podcast_');

      if (isPodcast) {
        await _continuePodcast(currentTrack, autoPlay: autoPlay);
      } else {
        await _continueMusic(autoPlay: autoPlay);
      }
    } catch (_) {
      // Ignore error
    } finally {
      _isSmartContinueLoading = false;
    }
  }

  Future<List<JellyfinTrack>> _getLibraryTracks() async {
    if (_allTracksCache.isNotEmpty) return _allTracksCache;
    try {
      final dbTracks = await _cacheService.db.getAllLocalTracks();
      if (dbTracks.isNotEmpty) {
        _allTracksCache = dbTracks.map(localTrackToJellyfin).toList();
        return _allTracksCache;
      }
    } catch (_) {}

    try {
      final remoteTracks = await _playlistService.jellyfinService.getTracks();
      if (remoteTracks.isNotEmpty) {
        _allTracksCache = remoteTracks;
        return remoteTracks;
      }
    } catch (_) {}

    return _queue;
  }

  Future<void> _continuePodcast(JellyfinTrack currentTrack,
      {bool autoPlay = false}) async {
    final podcastService = PodcastService();
    final feedId = currentTrack.albumId.startsWith('podcast_')
        ? currentTrack.albumId.substring('podcast_'.length)
        : currentTrack.albumId;

    final feeds = await podcastService.getSubscribedFeeds();
    PodcastFeed? targetFeed;
    for (final f in feeds) {
      if (f.id == feedId) {
        targetFeed = f;
        break;
      }
    }
    targetFeed ??= feeds.isNotEmpty ? feeds.first : null;

    if (targetFeed != null) {
      final episodes = await podcastService.fetchEpisodes(targetFeed);
      final queueGuids = _queue
          .where((t) => t.id.startsWith('podcast_'))
          .map((t) => t.id.substring('podcast_'.length))
          .toSet();

      final listenedSet = await podcastService.getListenedEpisodes();

      PodcastEpisode? nextEpisode;
      for (final ep in episodes) {
        if (!queueGuids.contains(ep.guid)) {
          if (!listenedSet.contains(ep.guid)) {
            nextEpisode = ep;
            break;
          }
        }
      }

      nextEpisode ??= episodes.firstWhere(
        (ep) => !queueGuids.contains(ep.guid),
        orElse: () => episodes.first,
      );

      final nextTrack = nextEpisode.toJellyfinTrack();
      await _appendTracksToQueue([nextTrack], autoPlay: autoPlay);
    }
  }

  Future<void> _continueMusic({bool autoPlay = false}) async {
    final libraryTracks = await _getLibraryTracks();
    final excludedIds = _queue.map((t) => t.id).toSet();

    final newTracks = await _playlistService.getRecommendedTracksForPlaylist(
      playlistTracks: _queue,
      libraryTracks: libraryTracks,
      excludedTrackIds: excludedIds,
      count: 5,
    );

    if (newTracks.isNotEmpty) {
      await _appendTracksToQueue(newTracks, autoPlay: autoPlay);
    }
  }

  Future<void> _appendTracksToQueue(List<JellyfinTrack> newTracks,
      {bool autoPlay = false}) async {
    _queue.addAll(newTracks);
    queue.add(_queue.map(_trackToMediaItem).toList());

    final audioSource = _player.audioSource;
    final newSources = newTracks.map(_buildAudioSource).toList();

    if (audioSource is ConcatenatingAudioSource) {
      await audioSource.addAll(newSources);
    } else {
      final allSources = _queue.map(_buildAudioSource).toList();
      final newConcat = ConcatenatingAudioSource(children: allSources);
      await _player.setAudioSource(
        newConcat,
        initialIndex: _currentIndex,
        initialPosition: _player.position,
      );
    }

    if (autoPlay) {
      final targetIndex = _currentIndex + 1 < _queue.length
          ? _currentIndex + 1
          : _queue.length - newTracks.length;
      _currentIndex = targetIndex;

      // Update mediaItem and emit playbackState so PlayerScreen and notifications update immediately
      mediaItem.add(_trackToMediaItem(_queue[targetIndex]));
      _emitPlaybackState();

      if (_originalSourceLength != null && targetIndex >= _originalSourceLength!) {
        _currentSourceType = 'queue';
        _currentSourceId = null;
        _currentSourceTitle = null;
      }

      await _player.seek(Duration.zero, index: targetIndex);
      await _player.play();
    }
  }
}
