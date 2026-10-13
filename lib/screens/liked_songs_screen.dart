import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../audio/queue_notifier.dart';
import '../models/jellyfin_models.dart';
import '../providers/library_provider.dart';
import '../services/favorites_store.dart';
import '../theme/app_theme.dart';
import '../widgets/track_card.dart';

/// The songs the user has liked, as a playlist that fills itself.
class LikedSongsScreen extends ConsumerWidget {
  const LikedSongsScreen({super.key});

  void _play(BuildContext context, WidgetRef ref, List<JellyfinTrack> tracks,
      {required bool shuffle}) {
    ref.read(queueNotifierProvider.notifier).playQueue(
          tracks,
          0,
          fromType: 'liked',
          fromId: FavoritesStore.likedSongsId,
          fromTitle: FavoritesStore.likedSongsTitle,
          shuffle: shuffle,
        );
    context.push('/player');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(tracksProvider).valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text(FavoritesStore.likedSongsTitle)),
      body: ValueListenableBuilder<int>(
        valueListenable: FavoritesStore.revision,
        builder: (context, _, __) {
          final tracks = FavoritesStore.likedTracks(library);
          if (tracks.isEmpty) return const _Empty();

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: tracks.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return _Header(
                  count: tracks.length,
                  onPlay: () => _play(context, ref, tracks, shuffle: false),
                  onShuffle: () => _play(context, ref, tracks, shuffle: true),
                );
              }
              return TrackCard(
                track: tracks[i - 1],
                queue: tracks,
                queueIndex: i - 1,
              );
            },
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  const _Header({
    required this.count,
    required this.onPlay,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              const LikedSongsArt(size: 96, iconSize: 44),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(FavoritesStore.likedSongsTitle,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      '$count ${count == 1 ? 'song' : 'songs'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Play'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShuffle,
                  icon: const Icon(Icons.shuffle_rounded,
                      size: 18, color: AppColors.primary),
                  label: const Text('Shuffle',
                      style: TextStyle(color: AppColors.primary)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 48),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_border_rounded,
                color: AppColors.textMuted, size: 64),
            const SizedBox(height: 16),
            Text('No liked songs yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Tap the heart on the player to like the song that is playing. '
              'It will show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// The heart-on-gradient artwork that stands for the Liked Songs playlist.
class LikedSongsArt extends StatelessWidget {
  /// Side length, or null to fill the space given.
  final double? size;
  final double iconSize;

  const LikedSongsArt({super.key, this.size, this.iconSize = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: size == null ? null : BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [AppColors.accent, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.favorite_rounded, color: Colors.white, size: iconSize),
    );
  }
}
