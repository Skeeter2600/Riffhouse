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

  List<JellyfinTrack> get currentQueue => _queue;
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
        // Publish immediately with the HTTPS art URL so UI shows something fast
        mediaItem.add(_trackToMediaItem(_queue[index]));
        // Record the play and pre-fetch the next track asynchronously.
        _playlistService.recordPlay(_queue[index].jellyfinId);
        _prefetchNext(index);
        // Then asynchronously download art to a local file and republish
        // so Android Auto / notification shade can display it without auth headers.
        unawaited(_pushArtFromFile(_queue[index]));

        // Save state immediately on track change!
        unawaited(_savePlaybackState());
        unawaited(_savePlaybackPositionImmediately(Duration.zero));
      }
    });

    // Re-emit playback state whenever the player state changes (play/pause/
    // buffering transitions).
    _player.playerStateStream.listen((state) {
      _emitPlaybackState();
      // Save state immediately on play/pause transition!
      unawaited(_savePlaybackState());

      // Auto-mark podcast as listened on completion
      if (state.processingState == ProcessingState.completed) {
        if (_queue.isNotEmpty && _currentIndex < _queue.length) {
          final currentTrack = _queue[_currentIndex];
          if (currentTrack.id.startsWith('podcast_')) {
            final guid = currentTrack.id.substring('podcast_'.length);
            final podcastService = PodcastService();
            unawaited(podcastService.markAsListened(guid, true));
          }
        }
      }
    });

    // Save position periodically as it plays
    _player.positionStream.listen((pos) {
      _savePlaybackPosition(pos);
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
    _queue = queue ?? [track];
    _currentIndex = queueIndex;
    _currentSourceType = fromType ?? 'track';
    _currentSourceId = fromId ?? track.id;
    _currentSourceTitle = fromTitle ?? track.title;

    // Publish the updated queue to audio_service.
    this.queue.add(_queue.map(_trackToMediaItem).toList());
    mediaItem.add(_trackToMediaItem(track));

    // Save state immediately
    unawaited(_savePlaybackState());
    unawaited(_savePlaybackPositionImmediately(Duration.zero));

    final source = _buildAudioSource(track);
    await _player.setAudioSource(source);
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
    _queue = tracks;
    _currentIndex = startIndex;
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
      await seek(target < duration ? target : duration);
    } else {
      await _player.seekToNext();
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
      await _player.seekToPrevious();
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
        } catch (e) {
          print('Failed to load playlist tracks for Android Auto: $e');
        }
      }
    } else if (parentMediaId.startsWith(kPrefixAlbum)) {
      final albumId = parentMediaId.substring(kPrefixAlbum.length);
      if (!_autoHandler.hasContainer(parentMediaId)) {
        try {
          final tracks = await _playlistService.jellyfinService.getAlbumTracks(albumId);
          _autoHandler.updateContainer(parentMediaId, tracks);
          _notifyChildrenChanged(parentMediaId);
        } catch (e) {
          print('Failed to load album tracks for Android Auto: $e');
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
          } catch (e) {
            print('Failed to load smart mix tracks for Android Auto: $e');
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
    } catch (e) {
      print('[JellyfinAudioHandler] Error caching artwork: $e');
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
    } catch (e) {
      print('Error loading credentials in background service: $e');
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
      } catch (e) {
        print('Error loading new albums in background service: $e');
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
        } catch (e) {
          print('Error loading recently played in background: $e');
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
      print('[JellyfinAudioHandler] Loaded ${_allTracksCache.length} tracks from local database cache.');

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

            print('[JellyfinAudioHandler] Eagerly loaded ${_allTracksCache.length} tracks into background cache and saved to DB.');
          } catch (e) {
            print('[JellyfinAudioHandler] Failed to eagerly load tracks: $e');
          } finally {
            _inFlightAllTracksFetch = null;
          }
        }());
      }
    } catch (e) {
      print('Error loading library in background service: $e');
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
    } catch (e) {
      print('Error saving selection in background: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Playback overrides for Android Auto
  // ---------------------------------------------------------------------------

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    print('[JellyfinAudioHandler] playFromMediaId called: mediaId=$mediaId, extras=$extras');
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
      } catch (e) {
        print('Error playing artist tracks directly in background: $e');
      }
      return;
    }

    // 1. Handle smart mixes
    if (mediaId == 'smart_mix_daily' || mediaId == 'smart_mix_heavy_rotation' || mediaId == 'smart_mix_undiscovered') {
      print('[JellyfinAudioHandler] playMediaId: Direct smart mix play requested for $mediaId');
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
        print('[JellyfinAudioHandler] playMediaId: smart_mix using ${libraryTracks.length} tracks.');
        List<JellyfinTrack> mixTracks = [];
        if (mediaId == 'smart_mix_daily') {
          mixTracks = await _playlistService.getSmartMix(libraryTracks: libraryTracks);
        } else if (mediaId == 'smart_mix_heavy_rotation') {
          mixTracks = await _playlistService.getHeavyRotation(libraryTracks: libraryTracks);
        } else if (mediaId == 'smart_mix_undiscovered') {
          mixTracks = await _playlistService.getUndiscovered(libraryTracks: libraryTracks);
        }
        print('[JellyfinAudioHandler] playMediaId: smart_mix generated ${mixTracks.length} tracks');
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
          print('[JellyfinAudioHandler] playMediaId: smart_mix playQueue started successfully');
        } else {
          print('[JellyfinAudioHandler] playMediaId: smart_mix generated empty track list');
        }
      } catch (e, stack) {
        print('Error playing smart mix directly in background: $e\n$stack');
      }
      return;
    }

    // 2. Resolve container ID
    String? containerId = extras?.containsKey('containerId') == true ? extras!['containerId'] as String? : null;
    print('[JellyfinAudioHandler] playMediaId: extras containerId=$containerId');

    if (containerId == null) {
      // Heuristic 1: check if the track is in the container the user is currently browsing
      if (_lastBrowsedContainerId != null) {
        final tracks = _autoHandler.getTracksForContainer(_lastBrowsedContainerId!);
        if (tracks.any((t) => t.id == mediaId)) {
          containerId = _lastBrowsedContainerId;
          print('[JellyfinAudioHandler] playMediaId: resolved containerId=$containerId via _lastBrowsedContainerId');
        }
      }
      
      // Heuristic 2: fall back to mapping scan
      if (containerId == null) {
        containerId = _autoHandler.findContainerForTrack(mediaId);
        print('[JellyfinAudioHandler] playMediaId: resolved containerId=$containerId via findContainerForTrack');
      }
    }

    if (containerId != null) {
      final tracks = _autoHandler.getTracksForContainer(containerId);
      print('[JellyfinAudioHandler] playMediaId: found ${tracks.length} tracks in container=$containerId');
      if (tracks.isNotEmpty) {
        final index = tracks.indexWhere((t) => t.id == mediaId);
        print('[JellyfinAudioHandler] playMediaId: track index=$index for mediaId=$mediaId');
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

          print('[JellyfinAudioHandler] playMediaId: starting playQueue at index=$index');
          try {
            await playQueue(
              tracks,
              index,
              fromType: fromType,
              fromId: fromId,
              fromTitle: fromTitle,
            );
            print('[JellyfinAudioHandler] playMediaId: playQueue completed successfully');
          } catch (e) {
            print('[JellyfinAudioHandler] playMediaId: playQueue failed with error: $e');
          }
          return;
        }
      }
    }

    // 3. Fallback: play single track
    print('[JellyfinAudioHandler] playMediaId: fallback to single track for mediaId=$mediaId');
    try {
      var track = _autoHandler.findTrackById(mediaId);
      if (track == null) {
        print('[JellyfinAudioHandler] playMediaId: track not cached locally. Fetching from Jellyfin server...');
        track = await _playlistService.jellyfinService.getTrack(mediaId);
      }

      if (track != null) {
        print('[JellyfinAudioHandler] playMediaId: playing track ${track.title}');
        if (track.albumId.isNotEmpty) {
          unawaited(_recordSelection(track.albumId, 'album'));
        }
        await playTrack(
          track,
          fromType: 'track',
          fromId: track.id,
          fromTitle: track.title,
        );
        print('[JellyfinAudioHandler] playMediaId: playTrack completed successfully');
      } else {
        print('[JellyfinAudioHandler] playMediaId: track NOT found anywhere for mediaId=$mediaId');
      }
    } catch (e, stack) {
      print('[JellyfinAudioHandler] playMediaId fallback failed: $e\n$stack');
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
      } catch (e) {
        print('[JellyfinAudioHandler] Error background downloading browse art: $e');
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
    } catch (e) {
      print('[JellyfinAudioHandler] Error saving playback state: $e');
    }
  }

  void _savePlaybackPosition(Duration position) async {
    final now = DateTime.now();
    if (now.difference(_lastSaveTime) > const Duration(seconds: 5)) {
      _lastSaveTime = now;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('playback_position_ms', position.inMilliseconds);
      } catch (e) {
        print('[JellyfinAudioHandler] Error saving playback position: $e');
      }
    }
  }

  Future<void> _savePlaybackPositionImmediately(Duration position) async {
    _lastSaveTime = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('playback_position_ms', position.inMilliseconds);
    } catch (e) {
      print('[JellyfinAudioHandler] Error saving playback position immediately: $e');
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

      _queue = tracks;
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

      print('[JellyfinAudioHandler] Restored playback state successfully: index=$_currentIndex, positionMs=$positionMs, source=$_currentSourceTitle');
    } catch (e, stack) {
      print('[JellyfinAudioHandler] Error restoring playback state: $e\n$stack');
    }
  }
}
