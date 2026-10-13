// ConcatenatingAudioSource still works in just_audio 0.10 and the queue
// reordering here is built on it; moving to the playlist API is a separate job.
// ignore_for_file: deprecated_member_use

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
import '../services/favorites_store.dart';
import '../services/jellyfin_service.dart';
import '../services/playlist_service.dart';
import '../providers/library_provider.dart';
import 'android_auto_handler.dart';
import 'queue_order.dart';
import '../services/podcast_service.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_feed.dart';
import '../utils/playback_diagnostics.dart';

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

  /// Shuffle is implemented by reordering [_queue] itself rather than through
  /// just_audio's shuffle mode, so it only ever affects the source tracks of
  /// the current play and never the smart-continue tracks appended after them.
  bool _shuffleEnabled = false;

  /// The source tracks of the current play in their original order.
  List<JellyfinTrack> _sourceOrder = [];

  /// True while the audio source is being rearranged; index changes reported
  /// by the player during that window are transient and must be ignored.
  bool _reordering = false;

  // Playback settings (persisted; see [setGaplessEnabled] / [setCrossfadeEnabled]).
  static const _gaplessPrefKey = 'playback_gapless_enabled';
  static const _crossfadePrefKey = 'playback_crossfade_enabled';

  static const _crossfadeSecondsPrefKey = 'playback_crossfade_seconds';

  /// Shortest, longest and default crossfade the user can choose.
  static const minCrossfadeSeconds = 1;
  static const maxCrossfadeSeconds = 12;
  static const defaultCrossfadeSeconds = 2;

  /// How long before the overlap the outgoing track is primed on
  /// [_fadePlayer], so it is loaded and buffered when the fade starts.
  static const _crossfadePrepareLead = Duration(seconds: 8);

  /// How far the two players may be apart at the hand-over before the fade
  /// player is moved to match.
  static const _crossfadeSyncTolerance = Duration(milliseconds: 250);

  int _crossfadeSeconds = defaultCrossfadeSeconds;

  /// Length of the overlap between two tracks when crossfade is on.
  int get crossfadeSeconds => _crossfadeSeconds;
  Duration get crossfadeDuration => Duration(seconds: _crossfadeSeconds);

  /// Volumes of the two tracks [elapsed] into a crossfade of [length]: the
  /// outgoing one falls from full to silent in a straight line while the
  /// incoming one rises from silent to full, as on the radio.
  static ({double incoming, double outgoing}) crossfadeVolumes(
    Duration elapsed,
    Duration length,
  ) {
    if (length <= Duration.zero) return (incoming: 1.0, outgoing: 0.0);
    final t =
        (elapsed.inMicroseconds / length.inMicroseconds).clamp(0.0, 1.0);
    return (incoming: t, outgoing: 1.0 - t);
  }

  /// When on, the next track is downloaded ahead of time so the hand-over has
  /// no buffering pause. (The queue itself is always one continuous source.)
  bool _gaplessEnabled = true;

  /// When on, the end of each song overlaps the start of the next.
  bool _crossfadeEnabled = false;

  bool get gaplessEnabled => _gaplessEnabled;
  bool get crossfadeEnabled => _crossfadeEnabled;

  /// Second player used only during a crossfade: it plays the tail of the
  /// outgoing track while [_player] has already moved on to the next one.
  AudioPlayer? _fadePlayer;

  /// Track id [_fadePlayer] has been asked to load / has finished loading.
  String? _fadePreparingFor;
  String? _fadeReadyFor;

  /// Bumped to abandon a crossfade in progress (pause, skip, new queue...).
  int _fadeToken = 0;

  /// Fires at the moment the overlap is due to begin.
  Timer? _fadeTimer;

  /// Where in the outgoing track [_fadePlayer] is parked.
  Duration _fadeStartPosition = Duration.zero;
  bool _crossfading = false;

  /// Id of the track the index listener last handled, used to drop the echo
  /// of a reorder (same track, already-known index).
  String? _activeTrackId;

  // ---- Diagnostics (see [PlaybackDiagnostics]) ------------------------------

  /// Where the current track was at the last position tick, so a track
  /// change can report how much of the previous song was left.
  Duration _lastPosition = Duration.zero;
  Duration? _lastDuration;
  String? _lastTrackName;

  /// When the user (or the app on their behalf) last skipped, sought, paused
  /// or started a new queue.
  DateTime _lastTransportAction = DateTime.fromMillisecondsSinceEpoch(0);

  String? _lastLoggedMainState;
  String? _lastLoggedFadeState;
  bool _volumeWarned = false;
  String? _fadeSkipLoggedFor;

  void _diag(String message) => PlaybackDiagnostics.log(message);

  /// One-line description of what [player] is doing right now.
  String _snapshot(AudioPlayer player) =>
      'pos=${PlaybackDiagnostics.time(player.position)}'
      '/${PlaybackDiagnostics.time(player.duration)} '
      'buffered=${PlaybackDiagnostics.time(player.bufferedPosition)} '
      'state=${player.processingState.name} '
      'playing=${player.playing} '
      'vol=${player.volume.toStringAsFixed(2)}';

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
    final svc = playlistService.musicService;
    _autoHandler = AndroidAutoHandler(
      service: svc,
      getCachedArtPath: (url) => _artCache[url],
      requestArtDownload: (url, parentId) => _requestArtDownload(url, parentId),
      toContentUri: (path) => _toContentUri(path),
    );
    _setupListeners();
    // Redraw the heart in Android Auto and the notification when a like
    // changes, wherever it was changed.
    FavoritesStore.revision.addListener(_emitPlaybackState);
    FavoritesStore.revision
        .addListener(() => _notifyChildrenChanged(kRootPlaylists));
    _loadPlaybackSettings();
    _loadSavedCredentials();
    _initAudioSession();
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    // Another app or the system taking the audio away looks just like a song
    // being cut short, so record it.
    session.interruptionEventStream.listen((event) {
      _diag('AUDIO FOCUS ${event.begin ? 'lost' : 'regained'} '
          '(${event.type.name}) main[${_snapshot(_player)}]');
    });
    session.becomingNoisyEventStream.listen((_) {
      _diag('AUDIO OUTPUT removed (headphones unplugged / disconnected)');
    });
  }

  // ---------------------------------------------------------------------------
  // Listener wiring
  // ---------------------------------------------------------------------------

  void _setupListeners() {
    // Forward raw playback events → playbackState stream.
    _player.playbackEventStream.listen(
      _handlePlaybackEvent,
      onError: (Object e, StackTrace st) {
        PlaybackDiagnostics.failed(
            'main player error: $e main[${_snapshot(_player)}]');
        // Surface errors without crashing the handler.
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
        ));
      },
    );

    // Keep mediaItem in sync with the currently active track.
    _player.currentIndexStream.listen((index) async {
      if (_reordering) return;
      if (index != null && index < _queue.length) {
        final trackId = _queue[index].id;
        if (index == _currentIndex && trackId == _activeTrackId) return;
        _logTrackChange(index);
        _activeTrackId = trackId;
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
      final described =
          '${state.processingState.name}/${state.playing ? 'playing' : 'paused'}';
      if (described != _lastLoggedMainState) {
        _lastLoggedMainState = described;
        _diag('MAIN -> $described [${_snapshot(_player)}]');
      }
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
      _checkPlaybackHealth(pos);
      _maybeCrossfade(pos);

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
  // Diagnostics
  // ---------------------------------------------------------------------------

  /// Records a move to queue item [index] and checks that the song before
  /// it was not cut short.
  void _logTrackChange(int index) {
    final sinceAction = DateTime.now().difference(_lastTransportAction);
    final reason = _crossfading
        ? 'crossfade'
        : sinceAction < const Duration(seconds: 3)
            ? 'skip / seek / new queue'
            : 'reached its end';
    final previous = _lastTrackName;
    final duration = _lastDuration;
    if (previous != null) {
      _diag('TRACK CHANGE ($reason): "$previous" left at '
          '${PlaybackDiagnostics.time(_lastPosition)}'
          '/${PlaybackDiagnostics.time(duration)} '
          '-> #$index "${_queue[index].name}"');
      if (reason == 'reached its end' && duration != null) {
        final unplayed = duration - _lastPosition;
        if (unplayed > const Duration(milliseconds: 1500)) {
          PlaybackDiagnostics.failed(
              '"$previous" stopped ${PlaybackDiagnostics.time(unplayed)} '
              'before its end with no skip, seek or crossfade');
        }
      }
    } else {
      _diag('TRACK START: #$index "${_queue[index].name}"');
    }
    _lastTrackName = _queue[index].name;
    _lastPosition = Duration.zero;
    _lastDuration = null;
    _volumeWarned = false;
    _fadeSkipLoggedFor = null;
  }

  /// Runs on every position tick.
  void _checkPlaybackHealth(Duration pos) {
    if (_reordering) return;
    _lastPosition = pos;
    _lastDuration = _player.duration ?? _lastDuration;

    // Only a crossfade may turn the main player down.
    if (!_crossfading && !_volumeWarned && _player.volume < 0.99) {
      _volumeWarned = true;
      PlaybackDiagnostics.failed('main player volume is '
          '${_player.volume.toStringAsFixed(2)} outside a crossfade '
          '[${_snapshot(_player)}]');
    }
  }

  /// After the second player has loaded, makes sure the main one is still
  /// playing: on some devices two players cannot share the audio output.
  Future<void> _checkMainSurvivedFadeLoad(String trackName) async {
    const window = Duration(milliseconds: 1500);
    final before = _player.position;
    final wasPlaying = _player.playing;
    await Future.delayed(window);
    if (!wasPlaying || !_player.playing || _crossfading) return;
    if (_queue.isEmpty ||
        _currentIndex >= _queue.length ||
        _queue[_currentIndex].name != trackName) {
      return;
    }
    final advanced = _player.position - before;
    if (advanced < const Duration(milliseconds: 700)) {
      PlaybackDiagnostics.failed(
          'main player stopped advancing after the second player loaded '
          '(moved ${advanced.inMilliseconds} ms in ${window.inMilliseconds} ms) '
          'main[${_snapshot(_player)}]');
    } else {
      _diag('XFADE check ok: main still advancing after second player loaded '
          '(${advanced.inMilliseconds} ms in ${window.inMilliseconds} ms)');
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Play a single [track], optionally with a surrounding [queue] starting at
  /// [queueIndex]. Replaces any existing queue.
  ///
  /// With [shuffle], [track] plays first and the rest of [queue] follows in
  /// random order. Shuffle applies to this play only.
  Future<void> playTrack(
    JellyfinTrack track, {
    List<JellyfinTrack>? queue,
    int queueIndex = 0,
    String? fromType,
    String? fromId,
    String? fromTitle,
    bool shuffle = false,
  }) async {
    _sourceOrder = queue != null ? List<JellyfinTrack>.from(queue) : [track];
    _shuffleEnabled = shuffle && _sourceOrder.length > 1;
    if (_shuffleEnabled) {
      _queue = shuffledForPlay(_sourceOrder, startIndex: queueIndex);
      _currentIndex = 0;
    } else {
      _queue = List<JellyfinTrack>.from(_sourceOrder);
      _currentIndex = queueIndex;
    }
    _originalSourceLength = _sourceOrder.length;
    _activeTrackId = null;
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
    await _cancelCrossfade();
    await _player.setShuffleModeEnabled(false);
    await _player.setAudioSource(concatenating, initialIndex: _currentIndex);
    await _player.play();
  }

  /// Build a [ConcatenatingAudioSource] from [tracks] and start playback at
  /// [startIndex]. Kicks off background pre-fetch for the next track.
  ///
  /// With [shuffle], [tracks] are played in random order starting from a
  /// random track and [startIndex] is ignored. Shuffle applies to this play
  /// only: the next call without it plays in order again.
  Future<void> playQueue(
    List<JellyfinTrack> tracks,
    int startIndex, {
    String? fromType,
    String? fromId,
    String? fromTitle,
    bool shuffle = false,
  }) async {
    _sourceOrder = List<JellyfinTrack>.from(tracks);
    _shuffleEnabled = shuffle && tracks.length > 1;
    if (_shuffleEnabled) {
      _queue = shuffledForPlay(_sourceOrder);
      _currentIndex = 0;
    } else {
      _queue = List<JellyfinTrack>.from(tracks);
      _currentIndex = startIndex;
    }
    _originalSourceLength = tracks.length;
    _activeTrackId = null;
    _currentTrackCountedAsListen = false;
    _currentSourceType = fromType ?? 'queue';
    _currentSourceId = fromId;
    _currentSourceTitle = fromTitle;

    // Publish queue to audio_service.
    queue.add(_queue.map(_trackToMediaItem).toList());
    mediaItem.add(_trackToMediaItem(_queue[_currentIndex]));

    // Save state immediately
    unawaited(_savePlaybackState());
    unawaited(_savePlaybackPositionImmediately(Duration.zero));

    final sources = _queue.map(_buildAudioSource).toList();
    final concatenating = ConcatenatingAudioSource(children: sources);

    final initialIndex = _currentIndex;
    await _cancelCrossfade();
    await _player.setShuffleModeEnabled(false);
    await _player.setAudioSource(
      concatenating,
      initialIndex: initialIndex,
    );
    await _player.play();

    _prefetchNext(initialIndex);
  }

  // ---------------------------------------------------------------------------
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() async {
    await _cancelCrossfade();
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _cancelCrossfade();
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    await _cancelCrossfade();
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
    await _cancelCrossfade();
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
    await _cancelCrossfade();
    await _player.seek(position);
    await _savePlaybackPositionImmediately(position);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _cancelCrossfade();
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  void updateAndroidAutoService(MusicService service) {
    _autoHandler.updateService(service);
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
    if (parentMediaId == kLikedSongsContainer) {
      // Built from the likes each time it is opened, so it is never stale.
      _autoHandler.updateContainer(
          parentMediaId, FavoritesStore.likedTracks(await _getLibraryTracks()));
    } else if (parentMediaId.startsWith(kPrefixPlaylist)) {
      final playlistId = parentMediaId.substring(kPrefixPlaylist.length);
      if (!_autoHandler.hasContainer(parentMediaId)) {
        try {
          final tracks = await _playlistService.musicService.getPlaylistTracks(playlistId);
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
          final tracks = await _playlistService.musicService.getAlbumTracks(albumId);
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
            final mixTracks = await _resolveSmartMix(parentMediaId);
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

  // ---------------------------------------------------------------------------
  // Extra media controls (Android Auto, notification, lock screen)
  // ---------------------------------------------------------------------------

  static const actionToggleShuffle = 'riffhouse.toggle_shuffle';
  static const actionCycleRepeat = 'riffhouse.cycle_repeat';
  static const actionToggleFavorite = 'riffhouse.toggle_favorite';

  /// The repeat button steps through off, repeat all, repeat one.
  static AudioServiceRepeatMode nextRepeatMode(AudioServiceRepeatMode mode) {
    switch (mode) {
      case AudioServiceRepeatMode.none:
        return AudioServiceRepeatMode.all;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        return AudioServiceRepeatMode.one;
      case AudioServiceRepeatMode.one:
        return AudioServiceRepeatMode.none;
    }
  }

  AudioServiceRepeatMode get _repeatMode => switch (_player.loopMode) {
        LoopMode.off => AudioServiceRepeatMode.none,
        LoopMode.one => AudioServiceRepeatMode.one,
        LoopMode.all => AudioServiceRepeatMode.all,
      };

  /// The music track playing now, or null for podcasts and an empty queue
  /// (which cannot be liked).
  JellyfinTrack? get _likeableTrack {
    if (_queue.isEmpty || _currentIndex >= _queue.length) return null;
    final track = _queue[_currentIndex];
    return track.id.startsWith('podcast_') ? null : track;
  }

  /// Buttons shown next to previous / play / next where there is room.
  List<MediaControl> get _extraControls {
    final repeat = _repeatMode;
    final likeable = _likeableTrack;
    final liked = likeable != null && FavoritesStore.isFavorite(likeable.id);
    return [
      MediaControl.custom(
        androidIcon:
            _shuffleEnabled ? 'drawable/ic_shuffle_on' : 'drawable/ic_shuffle_off',
        label: _shuffleEnabled ? 'Shuffle is on' : 'Shuffle is off',
        name: actionToggleShuffle,
      ),
      MediaControl.custom(
        androidIcon: switch (repeat) {
          AudioServiceRepeatMode.one => 'drawable/ic_repeat_one',
          AudioServiceRepeatMode.none => 'drawable/ic_repeat_off',
          _ => 'drawable/ic_repeat_all',
        },
        label: switch (repeat) {
          AudioServiceRepeatMode.one => 'Repeating this song',
          AudioServiceRepeatMode.none => 'Repeat is off',
          _ => 'Repeating all',
        },
        name: actionCycleRepeat,
      ),
      if (likeable != null)
        MediaControl.custom(
          androidIcon:
              liked ? 'drawable/ic_favorite_on' : 'drawable/ic_favorite_off',
          label: liked ? 'Liked' : 'Like',
          name: actionToggleFavorite,
        ),
    ];
  }

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    switch (name) {
      case actionToggleShuffle:
        await setShuffleMode(_shuffleEnabled
            ? AudioServiceShuffleMode.none
            : AudioServiceShuffleMode.all);
      case actionCycleRepeat:
        await setRepeatMode(nextRepeatMode(_repeatMode));
      case actionToggleFavorite:
        final track = _likeableTrack;
        if (track != null) {
          await FavoritesStore.toggle(_playlistService.musicService, track.id);
        }
      default:
        return super.customAction(name, extras);
    }
    _emitPlaybackState();
    return null;
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
    _emitPlaybackState();
    await _savePlaybackState();
  }

  /// Toggles shuffle for the current play. Turning it on shuffles the source
  /// tracks that have not played yet; turning it off puts the source tracks
  /// back in their original order. The playing track and any smart-continue
  /// tracks at the end of the queue are left where they are.
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode != AudioServiceShuffleMode.none;
    if (enable != _shuffleEnabled) {
      _shuffleEnabled = enable;
      if (_queue.isNotEmpty && _currentIndex < _queue.length) {
        final sourceLength = _originalSourceLength ?? _queue.length;
        if (enable) {
          await _applyQueueOrder(
            shuffleUpcoming(_queue, _currentIndex, sourceLength),
            _currentIndex,
            keepPrefix: true,
          );
        } else {
          final restored = restoreSourceOrder(
              _queue, _currentIndex, _sourceOrder, sourceLength);
          await _applyQueueOrder(restored.queue, restored.currentIndex);
        }
      }
    }
    _emitPlaybackState();
    await _savePlaybackState();
  }

  /// Rearranges the queue to [newQueue] without interrupting playback. The
  /// playing track must be the same one, now located at [newIndex]. With
  /// [keepPrefix], everything before the playing track is known to be
  /// unchanged and is left alone.
  Future<void> _applyQueueOrder(
    List<JellyfinTrack> newQueue,
    int newIndex, {
    bool keepPrefix = false,
  }) async {
    final oldIndex = _currentIndex;
    final audioSource = _player.audioSource;
    _reordering = true;
    try {
      if (audioSource is ConcatenatingAudioSource &&
          audioSource.length == _queue.length) {
        // Rebuild around the playing item: drop what follows and precedes it,
        // then insert the new neighbours.
        if (oldIndex + 1 < audioSource.length) {
          await audioSource.removeRange(oldIndex + 1, audioSource.length);
        }
        if (!keepPrefix) {
          if (oldIndex > 0) await audioSource.removeRange(0, oldIndex);
          final before =
              newQueue.sublist(0, newIndex).map(_buildAudioSource).toList();
          if (before.isNotEmpty) await audioSource.insertAll(0, before);
        }
        final after =
            newQueue.sublist(newIndex + 1).map(_buildAudioSource).toList();
        if (after.isNotEmpty) await audioSource.addAll(after);
      } else {
        await _player.setAudioSource(
          ConcatenatingAudioSource(
              children: newQueue.map(_buildAudioSource).toList()),
          initialIndex: newIndex,
          initialPosition: _player.position,
        );
      }
      _queue = newQueue;
      _currentIndex = newIndex;
      _activeTrackId = newQueue[newIndex].id;
    } finally {
      _reordering = false;
    }
    queue.add(_queue.map(_trackToMediaItem).toList());
    _prefetchNext(_currentIndex);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Pre-fetch the track after [currentIndex] so it is ready for gapless
  /// playback. Runs entirely in the background – callers must NOT await this.
  Future<void> _prefetchNext(int currentIndex) async {
    if (!_gaplessEnabled) return;
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
      final streamUrl = _playlistService.musicService.getStreamUrl(nextTrack.jellyfinId);
      // Fire-and-forget: start downloading without blocking playback.
      unawaited(_cacheService.downloadTrack(nextTrack.jellyfinId, streamUrl));
    }
  }

  // ---------------------------------------------------------------------------
  // Playback settings: gapless + crossfade
  // ---------------------------------------------------------------------------

  Future<void> _loadPlaybackSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _gaplessEnabled = prefs.getBool(_gaplessPrefKey) ?? true;
      _crossfadeEnabled = prefs.getBool(_crossfadePrefKey) ?? false;
      _crossfadeSeconds = (prefs.getInt(_crossfadeSecondsPrefKey) ??
              defaultCrossfadeSeconds)
          .clamp(minCrossfadeSeconds, maxCrossfadeSeconds);
    } catch (_) {
      // Keep defaults
    }
    _diag('SETTINGS crossfade=${_crossfadeEnabled ? 'on' : 'off'} '
        'length=${_crossfadeSeconds}s gapless=${_gaplessEnabled ? 'on' : 'off'}');
  }

  /// Turns pre-loading of the next track on or off.
  Future<void> setGaplessEnabled(bool enabled) async {
    _gaplessEnabled = enabled;
    if (enabled) unawaited(_prefetchNext(_currentIndex));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_gaplessPrefKey, enabled);
    } catch (_) {
      // Ignore error
    }
  }

  /// Turns the [crossfadeDuration] overlap between songs on or off.
  Future<void> setCrossfadeEnabled(bool enabled) async {
    _crossfadeEnabled = enabled;
    _diag('SETTINGS crossfade turned ${enabled ? 'on' : 'off'}');
    if (!enabled) await _cancelCrossfade();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_crossfadePrefKey, enabled);
    } catch (_) {
      // Ignore error
    }
  }

  /// Sets how many seconds two songs overlap.
  Future<void> setCrossfadeSeconds(int seconds) async {
    _crossfadeSeconds =
        seconds.clamp(minCrossfadeSeconds, maxCrossfadeSeconds);
    _diag('SETTINGS crossfade length set to ${_crossfadeSeconds}s');
    // Anything already primed was parked for the old length.
    await _cancelCrossfade();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_crossfadeSecondsPrefKey, _crossfadeSeconds);
    } catch (_) {
      // Ignore error
    }
  }

  // How the crossfade works
  //
  // [_player] owns the queue, so it has to be the one that moves on to the
  // next song. The overlap therefore plays the END of the outgoing song on a
  // second player:
  //
  //  1. A few seconds before the overlap, [_fadePlayer] loads the outgoing
  //     song and parks, paused, exactly where the overlap will begin.
  //  2. A timer fires when [_player] reaches that same point. [_fadePlayer]
  //     starts playing from where it is parked: no seek, so no pause to
  //     rebuffer. Once it is audibly running, [_player] is silenced and
  //     skips to the next song.
  //  3. Over the fade length [_fadePlayer] (the old song's last seconds)
  //     goes from full volume to silent while [_player] (the new song) goes
  //     from silent to full.
  //
  // If the second player is not ready or does not start, nothing is touched
  // and the song simply plays to its end.

  /// Called on every position tick. Primes the fade player shortly before
  /// the overlap and schedules the overlap itself.
  void _maybeCrossfade(Duration pos) {
    if (!_crossfadeEnabled || _crossfading || _reordering) return;
    if (!_player.playing || _player.loopMode == LoopMode.one) return;
    if (_player.processingState != ProcessingState.ready) return;
    if (_currentIndex + 1 >= _queue.length) return;

    final current = _queue[_currentIndex];
    final next = _queue[_currentIndex + 1];

    void skip(String why) {
      if (_fadeSkipLoggedFor == current.id) return;
      _fadeSkipLoggedFor = current.id;
      _diag('XFADE not used for "${current.name}": $why');
    }

    // Spoken-word episodes are never blended into music or each other, and
    // their "listened" state relies on reaching the real end of the episode.
    if (current.id.startsWith('podcast_') || next.id.startsWith('podcast_')) {
      return skip('podcast episode');
    }

    final fadeLength = crossfadeDuration;
    final duration = _player.duration;
    // Very short tracks (skits, interludes) are left alone.
    if (duration == null) return;
    if (duration < const Duration(seconds: 20) || duration < fadeLength * 4) {
      return skip('track is too short '
          '(${PlaybackDiagnostics.time(duration)} for a ${_crossfadeSeconds}s fade)');
    }

    final remaining = duration - pos;
    if (remaining <= fadeLength) {
      // Too late to start one cleanly.
      if (_fadeTimer == null) {
        skip('not ready in time (second player '
            '${_fadeReadyFor == current.id ? 'ready' : _fadePreparingFor == current.id ? 'still loading' : 'never started loading'})');
      }
      return;
    }

    if (_fadeReadyFor == current.id) {
      // Schedule against the clock rather than waiting for the next tick,
      // which could be a fifth of a second late.
      if (_fadeTimer == null) {
        final wait = remaining - fadeLength;
        _diag('XFADE scheduled in ${wait.inMilliseconds} ms for '
            '"${current.name}" -> "${next.name}" main[${_snapshot(_player)}]');
        _fadeTimer = Timer(wait, () {
          _fadeTimer = null;
          unawaited(_runCrossfade(current.id, fadeLength));
        });
      }
    } else if (remaining <= fadeLength + _crossfadePrepareLead &&
        _fadePreparingFor != current.id) {
      unawaited(_prepareCrossfade(current, duration - fadeLength));
    }
  }

  /// Creates the second player, with its state changes and errors recorded.
  AudioPlayer _createFadePlayer() {
    final fade = AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
    );
    fade.playerStateStream.listen((state) {
      final described =
          '${state.processingState.name}/${state.playing ? 'playing' : 'paused'}';
      if (described != _lastLoggedFadeState) {
        _lastLoggedFadeState = described;
        _diag('FADE -> $described [${_snapshot(fade)}]');
      }
    });
    fade.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        PlaybackDiagnostics.failed('second player error: $e');
      },
    );
    return fade;
  }

  /// Loads [track] into [_fadePlayer], parked at [startAt], where the
  /// overlap will begin.
  Future<void> _prepareCrossfade(JellyfinTrack track, Duration startAt) async {
    _fadePreparingFor = track.id;
    _fadeReadyFor = null;
    final clock = Stopwatch()..start();
    try {
      final source = _buildAudioSource(track);
      _diag('XFADE loading "${track.name}" into second player at '
          '${PlaybackDiagnostics.time(startAt)} '
          '(${source is UriAudioSource && source.uri.scheme == 'file' ? 'downloaded file' : 'stream'}) '
          'main[${_snapshot(_player)}]');

      final fade = _fadePlayer ??= _createFadePlayer();
      await fade.pause();
      await fade.setVolume(0);
      await fade.setAudioSource(source, initialPosition: startAt);

      if (_fadePreparingFor != track.id) {
        _diag('XFADE load finished after ${clock.elapsedMilliseconds} ms '
            'but is no longer wanted');
        return;
      }
      _fadeStartPosition = startAt;
      _fadeReadyFor = track.id;
      _diag('XFADE second player ready after ${clock.elapsedMilliseconds} ms '
          'fade[${_snapshot(fade)}] main[${_snapshot(_player)}]');

      // Both players must agree on how long the song is, or the tail the
      // second one plays is not the real ending.
      final mainDuration = _player.duration;
      final fadeDuration = fade.duration;
      if (mainDuration != null &&
          fadeDuration != null &&
          (mainDuration - fadeDuration).abs() > const Duration(seconds: 1)) {
        PlaybackDiagnostics.failed('the two players disagree on the length of '
            '"${track.name}": main ${PlaybackDiagnostics.time(mainDuration)}, '
            'second ${PlaybackDiagnostics.time(fadeDuration)}');
      }
      unawaited(_checkMainSurvivedFadeLoad(track.name));
    } catch (e) {
      // No crossfade for this track; it ends normally.
      PlaybackDiagnostics.failed('second player could not load '
          '"${track.name}" after ${clock.elapsedMilliseconds} ms: $e');
    }
  }

  /// Starts [player] and reports whether it is really running: its position
  /// only advances once audio is being produced.
  Future<bool> _startAndConfirm(AudioPlayer player) async {
    final from = player.position;
    unawaited(player.play());
    try {
      await player
          .createPositionStream(
            minPeriod: const Duration(milliseconds: 10),
            maxPeriod: const Duration(milliseconds: 20),
          )
          .firstWhere((p) => p - from >= const Duration(milliseconds: 20))
          .timeout(const Duration(milliseconds: 600));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Plays the last [fadeLength] of the outgoing track [trackId] on
  /// [_fadePlayer], fading out, while [_player] moves to the next track,
  /// fading in.
  Future<void> _runCrossfade(String trackId, Duration fadeLength) async {
    final fade = _fadePlayer;
    if (fade == null || _crossfading) return;

    // Everything must still be as it was when the fade was scheduled.
    String? blocked;
    if (!_crossfadeEnabled) {
      blocked = 'crossfade was turned off';
    } else if (_fadeReadyFor != trackId) {
      blocked = 'second player is no longer prepared for this track';
    } else if (_currentIndex >= _queue.length ||
        _queue[_currentIndex].id != trackId) {
      blocked = 'the track changed';
    } else if (!_player.playing) {
      blocked = 'playback is paused';
    } else if (fade.processingState != ProcessingState.ready) {
      blocked = 'second player is ${fade.processingState.name}, not ready';
    }
    if (blocked != null) {
      _diag('XFADE not started: $blocked '
          'main[${_snapshot(_player)}] fade[${_snapshot(fade)}]');
      return;
    }

    // The timer assumed uninterrupted playback. If the song stalled it is
    // not there yet: let the next tick schedule again.
    final ahead = _player.position - _fadeStartPosition;
    if (ahead < -_crossfadeSyncTolerance) {
      _diag('XFADE postponed: main is ${-ahead.inMilliseconds} ms short of '
          'the fade point (it stalled) main[${_snapshot(_player)}]');
      return;
    }

    _crossfading = true;
    final token = ++_fadeToken;
    _fadeReadyFor = null;
    var handedOver = false;
    final total = Stopwatch()..start();
    final outgoing = _queue[_currentIndex].name;
    _diag('XFADE START "$outgoing" (${fadeLength.inSeconds}s), main is '
        '${ahead.inMilliseconds} ms past the fade point '
        'main[${_snapshot(_player)}] fade[${_snapshot(fade)}]');
    try {
      if (ahead > _crossfadeSyncTolerance) {
        _diag('XFADE moving second player to match main');
        await fade.seek(_player.position);
        if (token != _fadeToken) return;
      }

      await fade.setVolume(1.0);
      final started = await _startAndConfirm(fade);
      _diag('XFADE second player ${started ? 'is playing' : 'DID NOT START'} '
          'after ${total.elapsedMilliseconds} ms fade[${_snapshot(fade)}]');
      if (!started) {
        PlaybackDiagnostics.failed('second player did not start; '
            '"$outgoing" will play to its end without a fade');
        return; // Song ends normally.
      }
      if (token != _fadeToken) return;

      // The old song now continues on the fade player; the main player can
      // go quiet and move on.
      await _player.setVolume(0);
      handedOver = true;
      final clock = Stopwatch()..start();
      await _player.seekToNext();
      _diag('XFADE handed over after ${total.elapsedMilliseconds} ms; main '
          'moved to next track main[${_snapshot(_player)}] '
          'fade[${_snapshot(fade)}]');

      // Driven by the clock, so slow volume calls cannot stretch the fade.
      var loggedQuarter = 0;
      while (true) {
        await Future.delayed(const Duration(milliseconds: 40));
        if (token != _fadeToken) return;
        final volumes = crossfadeVolumes(clock.elapsed, fadeLength);
        await _player.setVolume(volumes.incoming);
        await fade.setVolume(volumes.outgoing);

        final quarter = (volumes.incoming * 4).floor();
        if (quarter > loggedQuarter) {
          loggedQuarter = quarter;
          _diag('XFADE ${quarter * 25}% at ${clock.elapsedMilliseconds} ms: '
              'new song vol=${volumes.incoming.toStringAsFixed(2)} '
              '(${_player.processingState.name}, '
              '${PlaybackDiagnostics.time(_player.position)}), '
              'old song vol=${volumes.outgoing.toStringAsFixed(2)} '
              '(${fade.processingState.name}, '
              '${PlaybackDiagnostics.time(fade.position)}'
              '/${PlaybackDiagnostics.time(fade.duration)})');
          // The old song should still be sounding until the fade is over.
          if (quarter < 3 &&
              (!fade.playing ||
                  fade.processingState != ProcessingState.ready)) {
            PlaybackDiagnostics.failed('the outgoing song stopped sounding '
                'part-way through the fade fade[${_snapshot(fade)}]');
          }
        }
        if (volumes.incoming >= 1.0) break;
      }
    } catch (e) {
      PlaybackDiagnostics.failed('crossfade aborted by an error: $e');
      // Fall through to restoring normal playback below.
    } finally {
      if (token == _fadeToken) {
        _crossfading = false;
        try {
          if (handedOver) await _player.setVolume(1.0);
          await fade.pause();
          await fade.setVolume(0);
        } catch (_) {
          // Ignore error
        }
        _diag('XFADE END after ${total.elapsedMilliseconds} ms '
            '(${handedOver ? 'completed' : 'not performed'}) '
            'main[${_snapshot(_player)}]');
      } else {
        _diag('XFADE interrupted after ${total.elapsedMilliseconds} ms '
            '(skip, seek, pause or new queue)');
      }
    }
  }

  /// Abandons any crossfade in progress and restores full volume.
  Future<void> _cancelCrossfade() async {
    _lastTransportAction = DateTime.now();
    final pending = _crossfading
        ? 'a fade in progress'
        : _fadeTimer != null
            ? 'a scheduled fade'
            : (_fadeReadyFor != null || _fadePreparingFor != null)
                ? 'a prepared second player'
                : null;
    if (pending != null) _diag('XFADE cancelled $pending');

    _fadeToken++;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fadePreparingFor = null;
    _fadeReadyFor = null;
    final wasCrossfading = _crossfading;
    _crossfading = false;
    final fade = _fadePlayer;
    if (fade == null) return;
    try {
      if (fade.playing) await fade.pause();
      if (wasCrossfading) await _player.setVolume(1.0);
    } catch (_) {
      // Ignore error
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

    final streamUrl = _playlistService.musicService.getStreamUrl(track.jellyfinId);
    final streamUri = Uri.parse(streamUrl);
    return AudioSource.uri(
      streamUri,
      tag: _trackToMediaItem(track),
    );
  }

  MediaItem _trackToMediaItem(JellyfinTrack track) {
    final svc = _playlistService.musicService;
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
    final svc = _playlistService.musicService;
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
    final svc = _playlistService.musicService;
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
        ..._extraControls,
        // Last, so it is the one left out where space runs short.
        const MediaControl(
          androidIcon: 'drawable/ic_stop',
          label: 'Stop',
          action: MediaAction.stop,
        ),
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToQueueItem,
        MediaAction.setShuffleMode,
        MediaAction.setRepeatMode,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: playerState.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex,
      // Carried on every emission; omitting them would reset both to "none".
      shuffleMode: _shuffleEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
      repeatMode: _repeatMode,
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
        final service = MusicService.create(
          type: ServerType.fromId(config.serverType),
          serverUrl: config.serverUrl,
          accessToken: config.accessToken,
          userId: config.userId,
        );
        _playlistService.musicService = service;
        _autoHandler.updateService(service);
        await _loadLibraryFromDb();
        await _restorePlaybackState();
      }
    } catch (_) {
      // Ignore error
    }
  }

  Future<void> _loadLibraryFromDb() async {
    try {
      final svc = _playlistService.musicService;
      if (!svc.isSignedIn) return;

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

  /// Returns the tracks of the smart mix behind [mediaId]. Uses the same daily
  /// cache as the app's smart mix screens, so both show the same mix, and only
  /// generates (and caches) one when the app has not done so yet today.
  Future<List<JellyfinTrack>> _resolveSmartMix(String mediaId) async {
    final mixType = kSmartMixes[mediaId]?.mixType;
    if (mixType == null) return [];

    final cached = await getCachedSmartMix(mixType);
    if (cached != null && cached.isNotEmpty) return cached;

    List<JellyfinTrack> libraryTracks;
    if (_allTracksCache.isNotEmpty) {
      libraryTracks = _allTracksCache;
    } else if (_inFlightAllTracksFetch != null) {
      libraryTracks = await _inFlightAllTracksFetch!;
    } else {
      _inFlightAllTracksFetch = _playlistService.musicService.getTracks();
      try {
        libraryTracks = await _inFlightAllTracksFetch!;
        _allTracksCache = libraryTracks;
      } finally {
        _inFlightAllTracksFetch = null;
      }
    }

    var complete = true;
    final List<JellyfinTrack> mixTracks;
    switch (mediaId) {
      case kSmartMixDaily:
        mixTracks = await _playlistService.getSmartMix(libraryTracks: libraryTracks);
      case kSmartMixDailyDrive:
        mixTracks = await _playlistService.getDailyDrive(
          libraryTracks: libraryTracks,
          podcastService: PodcastService(),
          onIncomplete: () => complete = false,
        );
      case kSmartMixHeavy:
        mixTracks = await _playlistService.getHeavyRotation(libraryTracks: libraryTracks);
      case kSmartMixUndiscovered:
        mixTracks = await _playlistService.getUndiscovered(libraryTracks: libraryTracks);
      default:
        mixTracks = [];
    }

    if (complete && mixTracks.isNotEmpty) {
      await cacheSmartMix(mixType, mixTracks);
    }
    return mixTracks;
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
        final artistTracks = await _playlistService.musicService.getArtistTracks(artistId);
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
    final smartMix = kSmartMixes[mediaId];
    if (smartMix != null) {
      try {
        final mixTracks = await _resolveSmartMix(mediaId);
        if (mixTracks.isNotEmpty) {
          await playQueue(
            mixTracks,
            0,
            fromType: 'smart_mix',
            fromId: smartMix.mixType,
            fromTitle: smartMix.title,
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
          } else if (containerId == kLikedSongsContainer) {
            fromId = FavoritesStore.likedSongsId;
            fromType = 'liked';
            fromTitle = FavoritesStore.likedSongsTitle;
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
      track ??= await _playlistService.musicService.getTrack(mediaId);

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
      await prefs.setInt('playback_shuffle_mode', _shuffleEnabled ? 1 : 0);
      await prefs.setStringList(
          'playback_source_order_ids', _sourceOrder.map((t) => t.id).toList());
      if (_originalSourceLength != null) {
        await prefs.setInt('playback_source_length', _originalSourceLength!);
      } else {
        await prefs.remove('playback_source_length');
      }
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
      _activeTrackId = null;

      // Restore the shuffle bookkeeping. Shuffle is only kept if the original
      // source order can be rebuilt exactly; state saved by older builds
      // (which shuffled inside the player) falls back to off.
      _originalSourceLength = prefs.getInt('playback_source_length');
      final sourceLength = _originalSourceLength;
      final byId = {for (final t in tracks) t.id: t};
      final orderIds = prefs.getStringList('playback_source_order_ids') ?? const [];
      final sourceOrder = [
        for (final id in orderIds)
          if (byId[id] != null) byId[id]!,
      ];
      if (sourceLength != null &&
          sourceLength <= tracks.length &&
          sourceOrder.length == sourceLength &&
          orderIds.length == sourceLength) {
        _sourceOrder = sourceOrder;
        _shuffleEnabled = shuffleModeInt == 1;
      } else {
        _sourceOrder = tracks.take(sourceLength ?? tracks.length).toList();
        _shuffleEnabled = false;
      }

      // Publish the restored queue and active item to audio_service
      queue.add(_queue.map(_trackToMediaItem).toList());
      if (_currentIndex < _queue.length) {
        mediaItem.add(_trackToMediaItem(_queue[_currentIndex]));
        unawaited(_pushArtFromFile(_queue[_currentIndex]));
      }

      // Restore loop mode on the player. Player-level shuffle is never used.
      final loopMode = LoopMode.values[repeatModeInt];
      await _player.setLoopMode(loopMode);
      await _player.setShuffleModeEnabled(false);

      // Set audio source but do NOT play
      final sources = tracks.map(_buildAudioSource).toList();
      final concatenating = ConcatenatingAudioSource(children: sources);
      await _player.setAudioSource(
        concatenating,
        initialIndex: _currentIndex,
        initialPosition: Duration(milliseconds: positionMs),
      );

      // Emit initial playbackState (including repeat/shuffle) so UI is updated
      _emitPlaybackState();

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
      final remoteTracks = await _playlistService.musicService.getTracks();
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
