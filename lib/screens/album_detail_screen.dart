import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:audio_service/audio_service.dart';

import '../audio/queue_notifier.dart';
import '../models/jellyfin_models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/track_card.dart';
import '../widgets/add_to_playlist_sheet.dart';

class AlbumDetailScreen extends ConsumerWidget {
  final String albumId;
  const AlbumDetailScreen({super.key, required this.albumId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(albumsProvider);
    final tracksAsync = ref.watch(albumTracksProvider(albumId));
    final service = ref.watch(jellyfinServiceProvider);

    return albumsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary))),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (albums) {
        final album = albums.firstWhere((a) => a.id == albumId,
            orElse: () => JellyfinAlbum(
                id: albumId,
                name: 'Unknown Album',
                artist: '',
                trackCount: 0));
        final imageUrl = (service != null && album.imageTag != null)
            ? service.getImageUrl(album.id, album.imageTag!)
            : null;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            slivers: [
              // Parallax app bar
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                backgroundColor: AppColors.background,
                flexibleSpace: FlexibleSpaceBar(
                  background: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(color: AppColors.card),
                        )
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.primary, AppColors.background],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: const Icon(Icons.album,
                              size: 80, color: AppColors.textMuted),
                        ),
                  stretchModes: const [
                    StretchMode.zoomBackground,
                    StretchMode.fadeTitle,
                  ],
                ),
              ),

              // Album info
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(album.name,
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      Builder(builder: (context) {
                        final artists = ref.watch(artistsProvider).valueOrNull ?? [];
                        JellyfinArtist? artistObj;
                        for (final a in artists) {
                          if (a.name.toLowerCase() == album.artist.toLowerCase()) {
                            artistObj = a;
                            break;
                          }
                        }
                        final artistId = artistObj?.id;
                        return MouseRegion(
                          cursor: artistId != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
                          child: GestureDetector(
                            onTap: artistId != null
                                ? () => context.push('/artist/$artistId')
                                : null,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: album.artist,
                                    style: TextStyle(
                                      color: artistObj != null
                                          ? AppColors.primaryLight
                                          : AppColors.textSecondary,
                                      fontWeight: artistObj != null ? FontWeight.w600 : FontWeight.normal,
                                      decoration: artistObj != null
                                          ? TextDecoration.underline
                                          : null,
                                    ),
                                  ),
                                  if (album.year != null)
                                    TextSpan(
                                      text: '  ·  ${album.year}',
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.normal,
                                          decoration: TextDecoration.none),
                                    ),
                                ],
                              ),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                      // Action buttons
                      tracksAsync.whenData((tracks) {
                        if (tracks.isEmpty) return const SizedBox();
                        return Row(
                          children: [                             Expanded(
                              child: _ActionButton(
                                icon: Icons.play_arrow_rounded,
                                label: 'Play All',                                 onTap: () {
                                  ref
                                      .read(recentSelectionsProvider.notifier)
                                      .addSelection(albumId, 'album');
                                  ref
                                      .read(queueNotifierProvider.notifier)
                                      .playQueue(
                                        tracks,
                                        0,
                                        fromType: 'album',
                                        fromId: albumId,
                                        fromTitle: album.name,
                                      );
                                  ref
                                      .read(queueNotifierProvider.notifier)
                                      .setShuffleMode(AudioServiceShuffleMode.none);
                                  context.push('/player');
                                },
                                primary: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ActionButton(
                                icon: Icons.shuffle_rounded,
                                label: 'Shuffle',
                                onTap: () {
                                  ref
                                      .read(recentSelectionsProvider.notifier)
                                      .addSelection(albumId, 'album');
                                  final shuffled = [...tracks]..shuffle();
                                  ref
                                      .read(queueNotifierProvider.notifier)
                                      .playQueue(
                                        shuffled,
                                        0,
                                        fromType: 'album',
                                        fromId: albumId,
                                        fromTitle: album.name,
                                      );
                                  ref
                                      .read(queueNotifierProvider.notifier)
                                      .setShuffleMode(AudioServiceShuffleMode.all);
                                  context.push('/player');
                                },
                                primary: false,
                              ),
                            ),
                          ],
                        );
                      }).valueOrNull ??
                          const SizedBox(),
                    ],
                  ),
                ),
              ),

              // Track list
              tracksAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: Center(
                      child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )),
                ),
                error: (e, _) => SliverToBoxAdapter(
                    child: Center(child: Text('$e'))),
                data: (tracks) => SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final t = tracks[i];
                      return _TrackRow(
                          track: t,
                          index: i + 1,
                          queue: tracks,
                          queueIndex: i);
                    },
                    childCount: tracks.length,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Track row for album detail
// ---------------------------------------------------------------------------

class _TrackRow extends ConsumerWidget {
  final JellyfinTrack track;
  final int index;
  final List<JellyfinTrack> queue;
  final int queueIndex;

  const _TrackRow({
    required this.track,
    required this.index,
    required this.queue,
    required this.queueIndex,
  });

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
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
              leading: const Icon(Icons.download_outlined, color: AppColors.primary),
              title: const Text('Download',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () {
        ref.read(recentSelectionsProvider.notifier).addSelection(track.albumId.isNotEmpty ? track.albumId : track.albumName, 'album');
        ref.read(queueNotifierProvider.notifier).playQueue(queue, queueIndex);
        context.push('/player');
      },
      onLongPress: () => _showContextMenu(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text('$index',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 14)),
            ),
            Expanded(
              child: Text(track.name,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.textMuted, size: 20),
              onPressed: () => _showContextMenu(context, ref),
            ),
            const SizedBox(width: 8),
            Text(_formatDuration(track.durationMs),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: primary
              ? const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark])
              : null,
          color: primary ? null : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: primary
              ? null
              : Border.all(color: AppColors.glassBorder, width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
