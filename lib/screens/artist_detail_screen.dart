import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../models/jellyfin_models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../audio/queue_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/album_card.dart';

class ArtistDetailScreen extends ConsumerWidget {
  final String artistId;
  const ArtistDetailScreen({super.key, required this.artistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistsAsync = ref.watch(artistsProvider);
    final artistAlbumsAsync = ref.watch(artistAlbumsProvider(artistId));
    final artistTracksAsync = ref.watch(artistTracksProvider(artistId));
    final service = ref.watch(jellyfinServiceProvider);

    return artistsAsync.when(
      loading: () => const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: AppColors.primary))),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (artists) {
        final artist = artists.firstWhere((a) => a.id == artistId,
            orElse: () =>
                JellyfinArtist(id: artistId, name: 'Unknown Artist'));
        final imageUrl = (service != null && artist.imageTag != null)
            ? service.getImageUrl(artist.id, artist.imageTag!)
            : null;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            slivers: [
              // Header
              SliverAppBar(
                expandedHeight: 260,
                pinned: true,
                backgroundColor: AppColors.background,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(artist.name,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                  background: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _gradientBg(artist.name),
                        )
                      : _gradientBg(artist.name),
                  stretchModes: const [StretchMode.zoomBackground],
                ),
              ),

              // Play buttons
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: artistTracksAsync.when(
                    loading: () => const SizedBox(),
                    error: (_, __) => const SizedBox(),
                    data: (tracks) {
                      if (tracks.isEmpty) return const SizedBox();
                      return Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                              label: const Text('Play All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                ref.read(recentSelectionsProvider.notifier).addSelection(artistId, 'artist');
                                ref.read(queueNotifierProvider.notifier).playQueue(tracks, 0);
                                context.push('/player');
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.shuffle_rounded, color: Colors.white),
                              label: const Text('Shuffle', style: TextStyle(color: Colors.white)),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: AppColors.card,
                                side: const BorderSide(color: AppColors.glassBorder, width: 0.5),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                ref.read(recentSelectionsProvider.notifier).addSelection(artistId, 'artist');
                                final shuffledTracks = [...tracks]..shuffle();
                                ref.read(queueNotifierProvider.notifier).playQueue(shuffledTracks, 0);
                                context.push('/player');
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // Albums header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Text('Albums',
                      style: Theme.of(context).textTheme.headlineSmall),
                ),
              ),

              // Albums grid (async)
              artistAlbumsAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: Center(
                      child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: Center(
                      child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Error loading albums: $e',
                        style: const TextStyle(color: AppColors.textMuted)),
                  )),
                ),
                data: (albums) {
                  if (albums.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('No albums found',
                            style: TextStyle(color: AppColors.textMuted)),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => AlbumCard(album: albums[i]),
                        childCount: albums.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.75,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                      ),
                    ),
                  );
                },
              ),

              // Top Tracks header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Text('Top Tracks',
                      style: Theme.of(context).textTheme.headlineSmall),
                ),
              ),

              // Top Tracks list (async)
              artistTracksAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: Center(
                      child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: Center(
                      child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Error loading tracks: $e',
                        style: const TextStyle(color: AppColors.textMuted)),
                  )),
                ),
                data: (tracks) {
                  if (tracks.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text('No tracks found',
                            style: TextStyle(color: AppColors.textMuted)),
                      ),
                    );
                  }
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final t = tracks[i];
                        return _TopTrackTile(
                            track: t, queue: tracks, index: i, artistId: artistId);
                      },
                      childCount: tracks.length,
                    ),
                  );
                },
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        );
      },
    );
  }

  Widget _gradientBg(String name) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.background],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: const Center(
          child: Icon(Icons.person_rounded,
              size: 80, color: AppColors.textMuted)),
    );
  }
}

// ---------------------------------------------------------------------------
// Top track tile
// ---------------------------------------------------------------------------

class _TopTrackTile extends ConsumerWidget {
  final JellyfinTrack track;
  final List<JellyfinTrack> queue;
  final int index;
  final String artistId;

  const _TopTrackTile({
    required this.track,
    required this.queue,
    required this.index,
    required this.artistId,
  });

  String _dur(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(jellyfinServiceProvider);
    final imageUrl = (service != null && track.imageTag != null)
        ? service.getImageUrl(track.id, track.imageTag!)
        : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      title: Text(track.name,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(track.albumName,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: Text(_dur(track.durationMs),
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      onTap: () {
        ref.read(recentSelectionsProvider.notifier).addSelection(artistId, 'artist');
        ref.read(queueNotifierProvider.notifier).playQueue(queue, index);
        context.push('/player');
      },
    );
  }

  Widget _ph() => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.music_note, color: AppColors.textMuted),
      );
}
