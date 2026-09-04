import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/jellyfin_models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';

class PlaylistRecommendationsWidget extends ConsumerStatefulWidget {
  final String playlistId;
  final List<JellyfinTrack> currentTracks;

  const PlaylistRecommendationsWidget({
    super.key,
    required this.playlistId,
    required this.currentTracks,
  });

  @override
  ConsumerState<PlaylistRecommendationsWidget> createState() =>
      _PlaylistRecommendationsWidgetState();
}

class _PlaylistRecommendationsWidgetState
    extends ConsumerState<PlaylistRecommendationsWidget> {
  List<JellyfinTrack> _candidates = [];
  int _index = 0;
  final Set<String> _actedTrackIds = {};
  bool _loading = false;

  AudioPlayer? _player;
  String? _playingTrackId;
  bool _isPlaying = false;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCandidates();
    });
  }

  @override
  void dispose() {
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

  Future<void> _addTrack(JellyfinTrack track) async {
    await _stopPreview();
    _actedTrackIds.add(track.id);

    final playlistService = ref.read(playlistServiceProvider);
    final success =
        await playlistService.addTrackToPlaylist(widget.playlistId, track.id);

    if (mounted) {
      if (success) {
        ref.invalidate(playlistsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${track.title}" to playlist'),
            backgroundColor: AppColors.primary,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      _advanceCard();
    }
  }

  Future<void> _skipTrack(JellyfinTrack track) async {
    await _stopPreview();
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

          // Swipeable Dismissible Card
          Dismissible(
            key: ValueKey('${currentTrack.id}_$_index'),
            direction: DismissDirection.horizontal,
            background: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 28),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.playlist_add_check_rounded,
                      color: Colors.white, size: 32),
                  SizedBox(width: 8),
                  Text(
                    'ADD TO PLAYLIST',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            secondaryBackground: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 28),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'SKIP',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.close_rounded, color: Colors.white, size: 32),
                ],
              ),
            ),
            onDismissed: (direction) {
              if (direction == DismissDirection.startToEnd) {
                _addTrack(currentTrack);
              } else {
                _skipTrack(currentTrack);
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.glassBorder,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Album Art
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

                      // Track details
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

                  // Quick Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Skip Button
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
                        onPressed: () => _skipTrack(currentTrack),
                      ),

                      // Preview Sample Button
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),

                      // Add Button
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
                        onPressed: () => _addTrack(currentTrack),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
