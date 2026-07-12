import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/jellyfin_models.dart';
import 'audio_handler.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Immutable snapshot of the queue and playback status exposed to the UI.
class QueueState {
  final List<JellyfinTrack> tracks;
  final int currentIndex;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration? duration;
  final String? currentArtUrl;
  final AudioServiceShuffleMode shuffleMode;
  final AudioServiceRepeatMode repeatMode;

  const QueueState({
    this.tracks = const [],
    this.currentIndex = 0,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration,
    this.currentArtUrl,
    this.shuffleMode = AudioServiceShuffleMode.none,
    this.repeatMode = AudioServiceRepeatMode.none,
  });

  /// Returns the currently active [JellyfinTrack], or `null` when the queue is
  /// empty or [currentIndex] is out of range.
  JellyfinTrack? get currentTrack =>
      tracks.isNotEmpty && currentIndex < tracks.length
          ? tracks[currentIndex]
          : null;

  QueueState copyWith({
    List<JellyfinTrack>? tracks,
    int? currentIndex,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    String? currentArtUrl,
    AudioServiceShuffleMode? shuffleMode,
    AudioServiceRepeatMode? repeatMode,
    bool clearDuration = false,
  }) {
    return QueueState(
      tracks: tracks ?? this.tracks,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: clearDuration ? null : (duration ?? this.duration),
      currentArtUrl: currentArtUrl ?? this.currentArtUrl,
      shuffleMode: shuffleMode ?? this.shuffleMode,
      repeatMode: repeatMode ?? this.repeatMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueueState &&
          runtimeType == other.runtimeType &&
          tracks == other.tracks &&
          currentIndex == other.currentIndex &&
          isPlaying == other.isPlaying &&
          isLoading == other.isLoading &&
          position == other.position &&
          duration == other.duration &&
          currentArtUrl == other.currentArtUrl &&
          shuffleMode == other.shuffleMode &&
          repeatMode == other.repeatMode;

  @override
  int get hashCode => Object.hash(
        tracks,
        currentIndex,
        isPlaying,
        isLoading,
        position,
        duration,
        currentArtUrl,
        shuffleMode,
        repeatMode,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Riverpod [StateNotifier] that listens to [JellyfinAudioHandler]'s streams
/// and re-exposes the combined state as [QueueState] for the UI layer.
class QueueNotifier extends StateNotifier<QueueState> {
  final JellyfinAudioHandler _handler;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  QueueNotifier(this._handler) : super(const QueueState()) {
    _bindToHandler();
  }

  // ---------------------------------------------------------------------------
  // Stream binding
  // ---------------------------------------------------------------------------

  void _bindToHandler() {
    // --- queue (track list + active index) ---
    _subscriptions.add(
      _handler.queue.listen((mediaItems) {
        // The queue published by audio_service contains MediaItems; we resolve
        // the corresponding JellyfinTracks from the handler's internal list.
        // If that list hasn't been populated yet we keep whatever we have.
        if (mediaItems.isEmpty) {
          state = state.copyWith(tracks: [], currentIndex: 0);
        }
        // Actual JellyfinTrack list is synced via playbackState/queueIndex below.
      }),
    );

    // --- playback state (playing, loading, position, queue index) ---
    _subscriptions.add(
      _handler.playbackState.listen((ps) {
        final isLoading = ps.processingState == AudioProcessingState.loading ||
            ps.processingState == AudioProcessingState.buffering;

        state = state.copyWith(
          isPlaying: ps.playing,
          isLoading: isLoading,
          position: ps.position,
          currentIndex: ps.queueIndex ?? state.currentIndex,
          shuffleMode: ps.shuffleMode,
          repeatMode: ps.repeatMode,
        );
      }),
    );

    // --- position updates (real-time stream) ---
    _subscriptions.add(
      _handler.positionStream.listen((pos) {
        state = state.copyWith(position: pos);
      }),
    );

    // --- current media item (title, duration, artwork) ---
    _subscriptions.add(
      _handler.mediaItem.listen((item) {
        if (item != null) {
          state = state.copyWith(
            duration: item.duration,
            currentArtUrl: item.artUri?.toString(),
          );
        } else {
          state = state.copyWith(clearDuration: true);
        }
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Delegating control actions to the handler
  // ---------------------------------------------------------------------------

  /// Replaces the queue with [tracks] and begins playback at [startIndex].
  Future<void> playQueue(List<JellyfinTrack> tracks, int startIndex) async {
    state = state.copyWith(
      tracks: tracks,
      currentIndex: startIndex,
      isLoading: true,
    );
    await _handler.playQueue(tracks, startIndex);
  }

  /// Plays a single [track], optionally within a surrounding [queue].
  Future<void> playTrack(
    JellyfinTrack track, {
    List<JellyfinTrack>? queue,
    int queueIndex = 0,
  }) async {
    final effectiveQueue = queue ?? [track];
    state = state.copyWith(
      tracks: effectiveQueue,
      currentIndex: queueIndex,
      isLoading: true,
    );
    await _handler.playTrack(track, queue: queue, queueIndex: queueIndex);
  }

  Future<void> play() => _handler.play();
  Future<void> pause() => _handler.pause();
  Future<void> stop() => _handler.stop();
  Future<void> skipToNext() => _handler.skipToNext();
  Future<void> skipToPrevious() => _handler.skipToPrevious();
  Future<void> seek(Duration position) => _handler.seek(position);
  Future<void> skipToQueueItem(int index) => _handler.skipToQueueItem(index);

  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      _handler.setRepeatMode(repeatMode);

  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      _handler.setShuffleMode(shuffleMode);

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Provider for [JellyfinAudioHandler]. The handler must be initialised before
/// this provider is read (typically in `main()` via `AudioService.init()`).
///
/// Override this in tests or with `ProviderScope` overrides.
final audioHandlerProvider = Provider<JellyfinAudioHandler>((ref) {
  throw UnimplementedError(
    'audioHandlerProvider must be overridden with the initialised handler.',
  );
});

/// Provider that exposes [QueueNotifier] (and thus [QueueState]) to the widget
/// tree. It is automatically invalidated when the handler is replaced.
final queueNotifierProvider =
    StateNotifierProvider<QueueNotifier, QueueState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return QueueNotifier(handler);
});


