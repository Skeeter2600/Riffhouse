import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/queue_notifier.dart';
import '../models/jellyfin_models.dart';
import 'package:go_router/go_router.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartController;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String? _artUrl(JellyfinTrack? track) {
    final service = ref.read(jellyfinServiceProvider);
    if (service == null || track == null) return null;
    if (track.imageTag != null) {
      return service.getImageUrl(track.id, track.imageTag!);
    }
    if (track.albumId.isNotEmpty) {
      return service.getAlbumArtUrl(track.albumId);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final queueState = ref.watch(queueNotifierProvider);
    final queueNotifier = ref.read(queueNotifierProvider.notifier);
    final track = queueState.currentTrack;

    final artUrl = _artUrl(track);
    final duration = queueState.duration ?? Duration.zero;
    final position = queueState.position;
    final progress = (duration.inMilliseconds > 0)
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      body: Stack(
        children: [
          // Blurred background
          if (artUrl != null)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: artUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Container(color: AppColors.background),
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xBB1a0533),
                      Color(0xEE0a0a1a),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded,
                            color: AppColors.textPrimary, size: 32),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Now Playing',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.queue_music_rounded,
                            color: AppColors.textPrimary),
                        onPressed: () =>
                            _showQueue(context, ref, queueState),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Album art
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Hero(
                    tag: 'player_art',
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 40,
                            spreadRadius: 4,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: artUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: artUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                      color: AppColors.card,
                                      child: const Icon(Icons.album,
                                          size: 80,
                                          color: AppColors.textMuted)),
                                  errorWidget: (_, __, ___) => Container(
                                      color: AppColors.card,
                                      child: const Icon(Icons.album,
                                          size: 80,
                                          color: AppColors.textMuted)),
                                )
                              : Container(
                                  color: AppColors.card,
                                  child: const Icon(Icons.album,
                                      size: 80,
                                      color: AppColors.textMuted),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Track info + heart
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track?.name ?? 'Nothing Playing',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            if (track != null) ...[
                              Builder(
                                builder: (context) {
                                  final artists = ref.watch(artistsProvider).valueOrNull ?? [];
                                  final artistName = track.artists.firstOrNull ?? track.albumArtist;
                                  JellyfinArtist? artistObj;
                                  for (final a in artists) {
                                    if (a.name.toLowerCase() == artistName.toLowerCase()) {
                                      artistObj = a;
                                      break;
                                    }
                                  }

                                  final artistId = artistObj?.id;
                                  return MouseRegion(
                                    cursor: artistId != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
                                    child: GestureDetector(
                                      onTap: artistId != null ? () {
                                        context.push('/artist/$artistId');
                                      } : null,
                                      child: Text(
                                        track.artists.isNotEmpty ? track.artists.join(', ') : track.albumArtist,
                                        style: TextStyle(
                                          color: artistObj != null
                                              ? AppColors.primaryLight
                                              : AppColors.textSecondary,
                                          fontSize: 15,
                                          fontWeight: artistObj != null ? FontWeight.w500 : FontWeight.normal,
                                          decoration: artistObj != null
                                              ? TextDecoration.underline
                                              : null,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (track.albumName.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () {
                                      context.push('/album/${track.albumId}');
                                    },
                                    child: Text(
                                      track.albumName,
                                      style: const TextStyle(
                                        color: AppColors.secondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        decoration: TextDecoration.underline,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.favorite_border_rounded,
                            color: AppColors.accent, size: 28),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Seek bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16),
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: AppColors.surfaceVariant,
                          thumbColor: Colors.white,
                          overlayColor:
                              AppColors.primary.withOpacity(0.15),
                        ),
                        child: Slider(
                          value: progress.toDouble(),
                          onChanged: (v) {
                            final target = Duration(
                                milliseconds:
                                    (v * duration.inMilliseconds)
                                        .round());
                            queueNotifier.seek(target);
                          },
                        ),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(position),
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12)),
                            Text(_formatDuration(duration),
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Shuffle
                      IconButton(
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: queueState.shuffleMode == AudioServiceShuffleMode.all
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          size: 22,
                        ),
                        onPressed: () {
                          final isShuffled = queueState.shuffleMode == AudioServiceShuffleMode.all;
                          queueNotifier.setShuffleMode(isShuffled
                              ? AudioServiceShuffleMode.none
                              : AudioServiceShuffleMode.all);
                        },
                      ),
                      // Previous
                      _ControlIconButton(
                        icon: Icons.skip_previous_rounded,
                        size: 36,
                        onPressed: queueNotifier.skipToPrevious,
                      ),
                      // Play / Pause
                      _PlayPauseButton(
                        isPlaying: queueState.isPlaying,
                        isLoading: queueState.isLoading,
                        onPressed: () => queueState.isPlaying
                            ? queueNotifier.pause()
                            : queueNotifier.play(),
                      ),
                      // Next
                      _ControlIconButton(
                        icon: Icons.skip_next_rounded,
                        size: 36,
                        onPressed: queueNotifier.skipToNext,
                      ),
                      // Repeat
                      IconButton(
                        icon: Icon(
                          queueState.repeatMode == AudioServiceRepeatMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          color: queueState.repeatMode != AudioServiceRepeatMode.none
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          size: 22,
                        ),
                        onPressed: () {
                          final nextMode = queueState.repeatMode == AudioServiceRepeatMode.none
                              ? AudioServiceRepeatMode.all
                              : queueState.repeatMode == AudioServiceRepeatMode.all
                                  ? AudioServiceRepeatMode.one
                                  : AudioServiceRepeatMode.none;
                          queueNotifier.setRepeatMode(nextMode);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Bottom row: download & playlist_add
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download_outlined,
                          color: AppColors.textSecondary),
                      onPressed: () {},
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      icon: const Icon(Icons.playlist_add_rounded,
                          color: AppColors.textSecondary, size: 28),
                      onPressed: () {
                        if (track != null) {
                          showAddToPlaylistBottomSheet(context, ref, track);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showQueue(
      BuildContext context, WidgetRef ref, QueueState queueState) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text('Queue',
                      style:
                          Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  Text('${queueState.tracks.length} tracks',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                scrollController: scrollCtrl,
                itemCount: queueState.tracks.length,
                onReorder: (_, __) {},
                itemBuilder: (_, i) {
                  final t = queueState.tracks[i];
                  final isCurrent = i == queueState.currentIndex;
                  return ListTile(
                    key: ValueKey(t.id),
                    leading: CircleAvatar(
                      backgroundColor: isCurrent
                          ? AppColors.primary
                          : AppColors.surfaceVariant,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                            color: isCurrent
                                ? Colors.white
                                : AppColors.textMuted,
                            fontSize: 12),
                      ),
                    ),
                    title: Text(t.name,
                        style: TextStyle(
                            color: isCurrent
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.normal)),
                    subtitle: Text(t.artists.join(', '),
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12)),
                    onTap: () {
                      ref
                          .read(queueNotifierProvider.notifier)
                          .skipToQueueItem(i);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Control widgets
// ---------------------------------------------------------------------------

class _ControlIconButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onPressed;

  const _ControlIconButton({
    required this.icon,
    required this.size,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: AppColors.textSecondary, size: size),
      onPressed: onPressed,
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onPressed;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.5),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: isLoading
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation(Colors.white)),
                ),
              )
            : Icon(
                isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 38,
              ),
      ),
    );
  }
}
