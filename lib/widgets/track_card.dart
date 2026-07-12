import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/jellyfin_models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../audio/queue_notifier.dart';
import '../theme/app_theme.dart';
import 'add_to_playlist_sheet.dart';

class TrackCard extends ConsumerWidget {
  final JellyfinTrack track;
  final List<JellyfinTrack>? queue;
  final int queueIndex;

  const TrackCard({
    super.key,
    required this.track,
    this.queue,
    this.queueIndex = 0,
  });

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(jellyfinServiceProvider);
    final imageUrl = (service != null && track.imageTag != null)
        ? service.getImageUrl(track.id, track.imageTag!)
        : null;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        final queueNotifier = ref.read(queueNotifierProvider.notifier);
        queueNotifier.playTrack(
          track,
          queue: queue,
          queueIndex: queueIndex,
        );
        context.push('/player');
      },
      onLongPress: () => _showContextMenu(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Album art
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 50,
                height: 50,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _placeholder(),
                        errorWidget: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            const SizedBox(width: 12),
            // Track info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artists.join(', '),
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Duration
            Text(
              _formatDuration(track.durationMs),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.textMuted, size: 20),
              onPressed: () => _showContextMenu(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.music_note, color: AppColors.textMuted, size: 24),
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (track.albumId.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.album_outlined, color: AppColors.primary),
                title: const Text('Go to Album',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/album/${track.albumId}');
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded, color: AppColors.primary),
              title: const Text('Go to Artist',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                final artists = ref.read(artistsProvider).valueOrNull ?? [];
                final firstArtist = track.artists.firstOrNull ?? track.albumArtist;
                JellyfinArtist? artistObj;
                for (final a in artists) {
                  if (a.name.toLowerCase() == firstArtist.toLowerCase()) {
                    artistObj = a;
                    break;
                  }
                }
                if (artistObj != null) {
                  context.push('/artist/${artistObj.id}');
                } else {
                  context.push('/home/search');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add, color: AppColors.primary),
              title: const Text('Add to Playlist',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                showAddToPlaylistBottomSheet(context, ref, track);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.download_outlined, color: AppColors.primary),
              title: const Text('Download',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined,
                  color: AppColors.textSecondary),
              title: const Text('Share',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
