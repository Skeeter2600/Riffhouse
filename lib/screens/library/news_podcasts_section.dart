part of '../library_screen.dart';

// ===========================================================================
// News & Podcasts Section
// ===========================================================================

class _NewsPodcastsSection extends ConsumerWidget {
  const _NewsPodcastsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodesAsync = ref.watch(recentEpisodesProvider);
    final listenedSet = ref.watch(listenedEpisodesProvider);
    final queueState = ref.watch(queueNotifierProvider);

    return episodesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (episodes) {
        if (episodes.isEmpty) return const SizedBox.shrink();

        // Limit to 5 episodes for the home screen
        final displayEpisodes = episodes.take(5).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'News & Podcasts',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        "Latest stories from your subscriptions",
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => context.go('/home/podcasts'),
                    child: const Text(
                      'See All',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: displayEpisodes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (ctx, i) {
                  final episode = displayEpisodes[i];
                  final isListened = listenedSet.contains(episode.guid);
                  
                  // Playback state
                  final currentTrack = queueState.currentTrack;
                  final isCurrentTrack = currentTrack != null &&
                      currentTrack.id == 'podcast_${episode.guid}';
                  final isPlaying = isCurrentTrack && queueState.isPlaying;

                  return _PodcastHomeCard(
                    episode: episode,
                    isListened: isListened,
                    isPlaying: isPlaying,
                    onTap: () {
                      final track = episode.toJellyfinTrack();
                      final queue = episodes.map((e) => e.toJellyfinTrack()).toList();
                      ref.read(queueNotifierProvider.notifier).playTrack(
                            track,
                            queue: queue,
                            queueIndex: i,
                            fromType: 'podcast',
                            fromId: 'all_recent',
                            fromTitle: 'Recent Episodes',
                          );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PodcastHomeCard extends StatelessWidget {
  final PodcastEpisode episode;
  final bool isListened;
  final bool isPlaying;
  final VoidCallback onTap;

  const _PodcastHomeCard({
    required this.episode,
    required this.isListened,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 240,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPlaying ? AppColors.primary.withValues(alpha: 0.6) : Colors.transparent,
            width: isPlaying ? 2 : 0,
          ),
          boxShadow: [
            BoxShadow(
              color: isPlaying
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background artwork
            CachedNetworkImage(
              imageUrl: episode.imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.surfaceVariant),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.surfaceVariant,
                child: const Icon(Icons.podcasts, color: AppColors.primary, size: 40),
              ),
            ),
            // Dark gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: isListened ? 0.7 : 0.3),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
            // Content overlay
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top: publisher badge + listened indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.5),
                        ),
                        child: Text(
                          episode.podcastPublisher.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      if (isListened)
                        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16)
                      else
                        Icon(Icons.circle_outlined, color: Colors.white.withValues(alpha: 0.4), size: 16),
                    ],
                  ),
                  // Bottom: title, date, play button
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        episode.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                formatRelativeDate(episode.pubDate, shortWeekday: true),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '  •  ${episode.duration.inMinutes} min',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: isPlaying ? AppColors.primaryLight : AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
