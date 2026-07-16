import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../audio/queue_notifier.dart';
import '../theme/app_theme.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueState = ref.watch(queueNotifierProvider);
    final track = queueState.currentTrack;

    if (track == null) return const SizedBox.shrink();

    final progress = (queueState.duration != null &&
            queueState.duration!.inMilliseconds > 0)
        ? (queueState.position.inMilliseconds /
                queueState.duration!.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    // Use artUrl from the mediaItem stream (includes api_key for Jellyfin auth)
    final artUrl = queueState.currentArtUrl;

    return GestureDetector(
      onTap: () => context.push('/player'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(
            top: BorderSide(color: AppColors.glassBorder, width: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar at the very top
            LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.surfaceVariant,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 2,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Album art
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: _buildArt(artUrl),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Track info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.name,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          track.artists.join(', '),
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Play / Pause button
                  IconButton(
                    icon: Icon(
                      queueState.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: AppColors.textPrimary,
                      size: 28,
                    ),
                    onPressed: () {
                      final notifier =
                          ref.read(queueNotifierProvider.notifier);
                      queueState.isPlaying
                          ? notifier.pause()
                          : notifier.play();
                    },
                  ),
                  // Skip next
                   IconButton(
                    icon: Icon(
                      (queueState.currentTrack?.id.startsWith('podcast_') ?? false)
                          ? Icons.fast_forward_rounded
                          : Icons.skip_next_rounded,
                      color: AppColors.textSecondary,
                      size: 24,
                    ),
                    onPressed: () =>
                        ref.read(queueNotifierProvider.notifier).skipToNext(),
                  ),
                  // Open full player
                  IconButton(
                    icon: const Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: AppColors.textSecondary,
                      size: 26,
                    ),
                    onPressed: () => context.push('/player'),
                    tooltip: 'Open player',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArt(String? url) {
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.music_note, color: AppColors.textMuted, size: 20),
    );
  }
}
