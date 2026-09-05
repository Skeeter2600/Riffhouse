import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../audio/queue_notifier.dart';
import '../database/app_database.dart';
import '../models/jellyfin_models.dart';
import '../providers/auth_provider.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  List<JellyfinTrack> _resolveDownloadedTracks(
      List<CachedTrack> cachedList, List<JellyfinTrack> libraryTracks) {
    final map = {for (final t in libraryTracks) t.id: t};
    return cachedList.map((c) {
      return map[c.jellyfinId] ??
          JellyfinTrack(
            id: c.jellyfinId,
            name: 'Downloaded Track',
            artists: ['Offline'],
            albumArtist: '',
            albumId: '',
            albumName: '',
            genres: const [],
            durationMs: 0,
            serverId: '',
          );
    }).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cachedAsync = ref.watch(cachedTracksProvider);
    final allTracks = ref.watch(tracksProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Downloads'),
      ),
      body: cachedAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.textMuted))),
        data: (tracks) {
          final totalBytes =
              tracks.fold<int>(0, (sum, t) => sum + t.sizeBytes);
          final playableTracks = _resolveDownloadedTracks(tracks, allTracks);

          return Column(
            children: [
              // Header
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.2),
                      AppColors.card,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.glassBorder, width: 0.5),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storage_rounded,
                            color: AppColors.primary, size: 28),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatBytes(totalBytes),
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${tracks.length} tracks downloaded',
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (tracks.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                ref.read(queueNotifierProvider.notifier).playQueue(
                                      playableTracks,
                                      0,
                                      fromType: 'downloads',
                                      fromId: 'downloads',
                                      fromTitle: 'Downloads',
                                    );
                                context.push('/player');
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded, size: 20),
                              label: const Text('Play All'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                final shuffled = [...playableTracks]..shuffle();
                                ref.read(queueNotifierProvider.notifier).playQueue(
                                      shuffled,
                                      0,
                                      fromType: 'downloads',
                                      fromId: 'downloads',
                                      fromTitle: 'Downloads',
                                    );
                                context.push('/player');
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textPrimary,
                                side: const BorderSide(color: AppColors.glassBorder),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.shuffle_rounded, size: 18),
                              label: const Text('Shuffle'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // List
              Expanded(
                child: tracks.isEmpty
                    ? _emptyState(context)
                    : ListView.separated(
                        itemCount: tracks.length,
                        separatorBuilder: (_, __) => const Divider(
                            color: AppColors.surfaceVariant, height: 1),
                        itemBuilder: (ctx, i) => _CachedTrackTile(
                          track: tracks[i],
                          resolvedTrack: playableTracks[i],
                          allPlayable: playableTracks,
                          index: i,
                        ),
                      ),
              ),

              // Cache Management buttons
              if (tracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final count = await ref.read(downloadProvider.notifier).pruneUnpinnedTracks();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(count > 0
                                    ? 'Cleaned up $count temporary tracks'
                                    : 'No extra tracks to clean. Downloaded playlists intact.'),
                                backgroundColor: AppColors.primary,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.cleaning_services_rounded,
                            color: AppColors.primary),
                        label: const Text('Prune Temporary Songs',
                            style: TextStyle(color: AppColors.primary)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _confirmClearAll(context, ref),
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent),
                        label: const Text('Clear All Downloads',
                            style: TextStyle(color: Colors.redAccent)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.download_outlined,
              color: AppColors.textMuted, size: 64),
          const SizedBox(height: 16),
          Text('No downloads yet',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Download tracks to listen offline',
              style: TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All Downloads',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This will delete all downloaded tracks from your device.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(cachedTracksProvider.notifier).clearAll();
            },
            child:
                const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cached track tile
// ---------------------------------------------------------------------------

class _CachedTrackTile extends ConsumerWidget {
  final CachedTrack track;
  final JellyfinTrack resolvedTrack;
  final List<JellyfinTrack> allPlayable;
  final int index;

  const _CachedTrackTile({
    required this.track,
    required this.resolvedTrack,
    required this.allPlayable,
    required this.index,
  });

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(jellyfinServiceProvider);
    final imageUrl = (service != null && resolvedTrack.imageTag != null)
        ? service.getImageUrl(resolvedTrack.id, resolvedTrack.imageTag!)
        : null;

    final isKnownTrack = resolvedTrack.name != 'Downloaded Track';
    final title = isKnownTrack ? resolvedTrack.name : track.jellyfinId;
    final artists = isKnownTrack ? resolvedTrack.artists.join(', ') : 'Downloaded file';

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _ph(),
                )
              : _ph(),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$artists  •  ${_formatBytes(track.sizeBytes)}',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
        tooltip: 'Delete download',
        onPressed: () => ref
            .read(cachedTracksProvider.notifier)
            .deleteTrack(track.jellyfinId),
      ),
      onTap: () {
        ref.read(queueNotifierProvider.notifier).playQueue(
              allPlayable,
              index,
              fromType: 'downloads',
              fromId: 'downloads',
              fromTitle: 'Downloads',
            );
        context.push('/player');
      },
    );
  }

  Widget _ph() => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.music_note_rounded,
            color: AppColors.primary, size: 24),
      );
}
