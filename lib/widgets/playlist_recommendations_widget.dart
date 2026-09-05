import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/jellyfin_models.dart';
import '../providers/auth_provider.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';

class PlaylistRecommendationsWidget extends ConsumerStatefulWidget {
  final String playlistId;
  final List<JellyfinTrack> currentTracks;
  final bool showCounter;
  final bool isFullPage;

  const PlaylistRecommendationsWidget({
    super.key,
    required this.playlistId,
    required this.currentTracks,
    this.showCounter = false,
    this.isFullPage = false,
  });

  @override
  ConsumerState<PlaylistRecommendationsWidget> createState() =>
      _PlaylistRecommendationsWidgetState();
}

class _PlaylistRecommendationsWidgetState
    extends ConsumerState<PlaylistRecommendationsWidget>
    with SingleTickerProviderStateMixin {
  List<JellyfinTrack> _candidates = [];
  int _index = 0;
  final Set<String> _actedTrackIds = {};
  bool _loading = false;

  AudioPlayer? _player;
  String? _playingTrackId;
  bool _isPlaying = false;

  double _dragOffset = 0.0;
  late AnimationController _swipeAnimController;
  Animation<double>? _swipeAnimation;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player!.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing = state.playing &&
          state.processingState != ProcessingState.completed &&
          state.processingState != ProcessingState.idle;
      setState(() {
        _isPlaying = playing;
        if (state.processingState == ProcessingState.completed) {
          _playingTrackId = null;
        }
      });
    });

    _swipeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_swipeAnimation != null) {
          setState(() {
            _dragOffset = _swipeAnimation!.value;
          });
        }
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCandidates();
    });
  }

  @override
  void dispose() {
    _swipeAnimController.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final playlistService = ref.read(playlistServiceProvider);
      final tracks = await ref.read(tracksProvider.future);

      final result = await playlistService.getRecommendedTracksForPlaylist(
        playlistTracks: widget.currentTracks,
        libraryTracks: tracks,
        excludedTrackIds: _actedTrackIds,
        count: 5,
      );

      if (mounted) {
        setState(() {
          _candidates = result;
          _index = 0;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _togglePreview(JellyfinTrack track) async {
    if (_player == null) return;

    if (_playingTrackId == track.id && _isPlaying) {
      await _player!.pause();
      setState(() => _isPlaying = false);
      return;
    }

    try {
      final service = ref.read(jellyfinServiceProvider);
      if (service == null) return;

      final streamUrl = track.streamUrl ?? service.getStreamUrl(track.jellyfinId);

      await _player!.stop();
      setState(() {
        _playingTrackId = track.id;
        _isPlaying = true;
      });

      await _player!.setUrl(streamUrl);
      await _player!.play();
    } catch (e) {
      if (mounted) {
        setState(() {
          _playingTrackId = null;
          _isPlaying = false;
        });
      }
    }
  }

  Future<void> _stopPreview() async {
    if (_player != null && _isPlaying) {
      await _player!.stop();
      if (mounted) {
        setState(() {
          _playingTrackId = null;
          _isPlaying = false;
        });
      }
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_swipeAnimController.isAnimating) return;
    setState(() {
      _dragOffset += details.primaryDelta ?? 0.0;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_swipeAnimController.isAnimating || _candidates.isEmpty || _index >= _candidates.length) return;
    final track = _candidates[_index];
    if (_dragOffset > 90) {
      _animateCardOut(toRight: true, onComplete: () => _addTrack(track));
    } else if (_dragOffset < -90) {
      _animateCardOut(toRight: false, onComplete: () => _skipTrack(track));
    } else {
      _animateCardBack();
    }
  }

  void _animateCardOut({required bool toRight, required VoidCallback onComplete}) {
    final start = _dragOffset;
    final end = toRight ? 500.0 : -500.0;
    _swipeAnimation = Tween<double>(begin: start, end: end).animate(
      CurvedAnimation(parent: _swipeAnimController, curve: Curves.easeOutCubic),
    );
    _swipeAnimController.forward(from: 0.0).then((_) {
      _dragOffset = 0.0;
      onComplete();
    });
  }

  void _animateCardBack() {
    _swipeAnimation = Tween<double>(begin: _dragOffset, end: 0.0).animate(
      CurvedAnimation(parent: _swipeAnimController, curve: Curves.easeOutCubic),
    );
    _swipeAnimController.forward(from: 0.0).then((_) {
      _dragOffset = 0.0;
    });
  }

  void _addTrack(JellyfinTrack track) {
    _stopPreview();
    _actedTrackIds.add(track.id);
    _advanceCard();

    final playlistService = ref.read(playlistServiceProvider);
    playlistService.addTrackToPlaylist(widget.playlistId, track.id).then((success) {
      if (mounted && success) {
        ref.invalidate(playlistsProvider);
        ref
            .read(downloadProvider.notifier)
            .onTrackAddedToPlaylist(widget.playlistId, track);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${track.title}" to playlist'),
            backgroundColor: AppColors.primary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _skipTrack(JellyfinTrack track) {
    _stopPreview();
    _actedTrackIds.add(track.id);
    _advanceCard();
  }

  void _advanceCard() {
    setState(() {
      _index++;
    });

    // Auto-reload when all 5 are acted on
    if (_index >= _candidates.length) {
      _loadCandidates();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }

    if (_candidates.isEmpty || _index >= _candidates.length) {
      if (widget.isFullPage) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 64,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'All caught up!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You reviewed all current recommendations for this playlist.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _actedTrackIds.clear();
                      _index = 0;
                    });
                    _loadCandidates();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh Recommendations'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final currentTrack = _candidates[_index];
    final service = ref.watch(jellyfinServiceProvider);
    final imageUrl = (service != null && currentTrack.imageTag != null)
        ? service.getImageUrl(currentTrack.id, currentTrack.imageTag!)
        : (service != null && currentTrack.albumId.isNotEmpty)
            ? service.getAlbumArtUrl(currentTrack.albumId)
            : null;

    final isPreviewPlaying =
        _playingTrackId == currentTrack.id && _isPlaying;

    final isFull = widget.isFullPage;

    final cardContent = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(isFull ? 28 : 20),
        border: Border.all(
          color: _dragOffset > 30
              ? const Color(0xFF10B981)
              : _dragOffset < -30
                  ? const Color(0xFFEF4444)
                  : AppColors.glassBorder,
          width: _dragOffset.abs() > 30 ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _dragOffset > 30
                ? const Color(0xFF10B981).withValues(alpha: 0.25)
                : _dragOffset < -30
                    ? const Color(0xFFEF4444).withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.4),
            blurRadius: isFull ? 24 : 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isFull ? 28 : 20),
        child: Column(
          mainAxisSize: isFull ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isFull) ...[
              // Full-page Hero Artwork
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl != null)
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.music_note_rounded,
                              color: AppColors.textMuted, size: 72),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.music_note_rounded,
                              color: AppColors.textMuted, size: 72),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.4),
                              AppColors.surfaceVariant,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.music_note_rounded,
                            color: AppColors.textMuted, size: 80),
                      ),
                    // Gradient overlay to blend bottom of art into card info
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 100,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              AppColors.card.withValues(alpha: 0.95),
                              AppColors.card,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    if (currentTrack.genres.isNotEmpty)
                      Positioned(
                        top: 18,
                        left: 18,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24, width: 0.5),
                          ),
                          child: Text(
                            currentTrack.genres.first,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Full-page Track Info & Controls
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentTrack.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentTrack.artist,
                      style: const TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (currentTrack.album.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        currentTrack.album,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Controls in full page mode
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Skip Button
                        IconButton.filledTonal(
                          iconSize: 32,
                          style: IconButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFEF4444).withValues(alpha: 0.15),
                            foregroundColor: const Color(0xFFEF4444),
                            padding: const EdgeInsets.all(16),
                          ),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Skip',
                          onPressed: () {
                            if (!_swipeAnimController.isAnimating) {
                              _animateCardOut(
                                  toRight: false,
                                  onComplete: () => _skipTrack(currentTrack));
                            }
                          },
                        ),

                        // Preview Sample Button
                        ElevatedButton.icon(
                          onPressed: () => _togglePreview(currentTrack),
                          icon: Icon(
                            isPreviewPlaying
                                ? Icons.stop_rounded
                                : Icons.play_arrow_rounded,
                            size: 22,
                          ),
                          label: Text(
                            isPreviewPlaying ? 'Stop Preview' : 'Preview',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isPreviewPlaying
                                ? AppColors.primary
                                : AppColors.surfaceVariant,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 52),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                        ),

                        // Add Button
                        IconButton.filledTonal(
                          iconSize: 32,
                          style: IconButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF10B981).withValues(alpha: 0.15),
                            foregroundColor: const Color(0xFF10B981),
                            padding: const EdgeInsets.all(16),
                          ),
                          icon: const Icon(Icons.check_rounded),
                          tooltip: 'Add to Playlist',
                          onPressed: () {
                            if (!_swipeAnimController.isAnimating) {
                              _animateCardOut(
                                  toRight: true,
                                  onComplete: () => _addTrack(currentTrack));
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Compact Inline Layout (for non-fullPage use)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 80,
                            height: 80,
                            child: imageUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      color: AppColors.surfaceVariant,
                                      child: const Icon(Icons.music_note_rounded,
                                          color: AppColors.textMuted),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      color: AppColors.surfaceVariant,
                                      child: const Icon(Icons.music_note_rounded,
                                          color: AppColors.textMuted),
                                    ),
                                  )
                                : Container(
                                    color: AppColors.surfaceVariant,
                                    child: const Icon(Icons.music_note_rounded,
                                        color: AppColors.textMuted),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentTrack.title,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentTrack.artist,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (currentTrack.album.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  currentTrack.album,
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (currentTrack.genres.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    currentTrack.genres.first,
                                    style: const TextStyle(
                                      color: AppColors.primaryLight,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton.filledTonal(
                          iconSize: 26,
                          style: IconButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFEF4444).withValues(alpha: 0.15),
                            foregroundColor: const Color(0xFFEF4444),
                            padding: const EdgeInsets.all(12),
                          ),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Skip',
                          onPressed: () {
                            if (!_swipeAnimController.isAnimating) {
                              _animateCardOut(
                                  toRight: false,
                                  onComplete: () => _skipTrack(currentTrack));
                            }
                          },
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _togglePreview(currentTrack),
                          icon: Icon(
                            isPreviewPlaying
                                ? Icons.stop_rounded
                                : Icons.play_arrow_rounded,
                            size: 20,
                          ),
                          label: Text(
                            isPreviewPlaying ? 'Stop Sample' : 'Sample Song',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isPreviewPlaying
                                ? AppColors.primary
                                : AppColors.surfaceVariant,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          iconSize: 26,
                          style: IconButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF10B981).withValues(alpha: 0.15),
                            foregroundColor: const Color(0xFF10B981),
                            padding: const EdgeInsets.all(12),
                          ),
                          icon: const Icon(Icons.check_rounded),
                          tooltip: 'Add to Playlist',
                          onPressed: () {
                            if (!_swipeAnimController.isAnimating) {
                              _animateCardOut(
                                  toRight: true,
                                  onComplete: () => _addTrack(currentTrack));
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final swipeableCard = GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(_dragOffset, 0),
        child: Transform.rotate(
          angle: (_dragOffset / 1000) * 0.15,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              cardContent,

              // Directional Overlays during Drag
              if (_dragOffset > 20)
                Positioned(
                  top: isFull ? 24 : 14,
                  right: isFull ? 24 : 14,
                  child: Opacity(
                    opacity: ((_dragOffset - 20) / 70).clamp(0.0, 1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 6),
                          Text(
                            'ADD',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (_dragOffset < -20)
                Positioned(
                  top: isFull ? 24 : 14,
                  left: isFull ? 24 : 14,
                  child: Opacity(
                    opacity: (((-_dragOffset) - 20) / 70).clamp(0.0, 1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SKIP',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 1,
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(Icons.close_rounded, color: Colors.white, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (isFull) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Swipe left to skip | Swipe right to add',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(child: swipeableCard),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recommended Songs',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Swipe right to add, left to skip',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              if (widget.showCounter)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_index + 1} of ${_candidates.length}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          swipeableCard,
        ],
      ),
    );
  }
}
