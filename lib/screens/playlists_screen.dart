import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../models/jellyfin_models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Your Playlists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
      body: playlistsAsync.when(
        loading: () => _buildShimmer(),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.textMuted))),
        data: (playlists) => playlists.isEmpty
            ? _emptyState(context)
            : GridView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.8,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: playlists.length,
                itemBuilder: (ctx, i) =>
                    _PlaylistCard(playlist: playlists[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Playlist',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildShimmer() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: AppColors.surfaceVariant,
        highlightColor: AppColors.card,
        child: Container(
            decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        )),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.queue_music_outlined,
              color: AppColors.textMuted, size: 64),
          const SizedBox(height: 16),
          Text('No playlists yet',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Create your first playlist',
              style: TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Playlist',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary),
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: AppColors.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                final playlistService = ref.read(playlistServiceProvider);
                final newId = await playlistService.createPlaylistOnServer(name, []);
                if (newId != null) {
                  ref.invalidate(playlistsProvider);
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Playlist card
// ---------------------------------------------------------------------------

class _PlaylistCard extends ConsumerWidget {
  final JellyfinPlaylist playlist;
  const _PlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(jellyfinServiceProvider);
    final imageUrl = (service != null && playlist.imageTag != null)
        ? service.getImageUrl(playlist.id, playlist.imageTag!)
        : null;

    return GestureDetector(
      onTap: () => context.push('/playlist/${playlist.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: AppColors.glassBorder, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorWidget: (_, __, ___) => _gradientPh(),
                        placeholder: (_, __) => _gradientPh(),
                      )
                    : _gradientPh(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${playlist.trackCount} tracks',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradientPh() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.4), AppColors.card],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
          child: Icon(Icons.queue_music_rounded,
              color: AppColors.primary, size: 40)),
    );
  }
}
