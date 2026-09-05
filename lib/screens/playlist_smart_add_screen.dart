import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/jellyfin_models.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/playlist_recommendations_widget.dart';

class PlaylistSmartAddScreen extends ConsumerWidget {
  final String playlistId;

  const PlaylistSmartAddScreen({
    super.key,
    required this.playlistId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final tracksAsync = ref.watch(playlistTracksProvider(playlistId));

    final playlist = playlistsAsync.valueOrNull?.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => JellyfinPlaylist(id: playlistId, name: 'Playlist', trackCount: 0),
    );
    final playlistName = playlist?.name ?? 'Playlist';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: AppColors.primaryLight, size: 18),
                SizedBox(width: 8),
                Text(
                  'Smart Add',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Text(
              playlistName,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: tracksAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (err, _) => Center(
            child: Text('Error loading playlist tracks: $err'),
          ),
          data: (tracks) {
            return PlaylistRecommendationsWidget(
              playlistId: playlistId,
              currentTracks: tracks,
              showCounter: false,
              isFullPage: true,
            );
          },
        ),
      ),
    );
  }
}
