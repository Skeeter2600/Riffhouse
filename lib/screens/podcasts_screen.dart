import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../models/podcast_episode.dart';
import '../models/podcast_feed.dart';
import '../providers/podcast_provider.dart';
import '../audio/queue_notifier.dart';
import '../theme/app_theme.dart';

class PodcastsScreen extends ConsumerStatefulWidget {
  const PodcastsScreen({super.key});

  @override
  ConsumerState<PodcastsScreen> createState() => _PodcastsScreenState();
}

class _PodcastsScreenState extends ConsumerState<PodcastsScreen> {
  final _rssController = TextEditingController();
  bool _isSubscribing = false;
  String? _expandedEpisodeGuid;
  String _selectedCategory = 'All';

  @override
  void dispose() {
    _rssController.dispose();
    super.dispose();
  }

  void _showAddFeedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Podcast Feed', style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the RSS feed URL of the podcast or news source you would like to subscribe to:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _rssController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'https://...',
                  labelText: 'RSS Feed URL',
                ),
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              if (_isSubscribing) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(color: AppColors.primary),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: _isSubscribing ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: _isSubscribing
                  ? null
                  : () async {
                      final url = _rssController.text.trim();
                      if (url.isEmpty) return;
                      
                      setDialogState(() => _isSubscribing = true);
                      try {
                        await ref.read(subscribedFeedsProvider.notifier).subscribe(url);
                        _rssController.clear();
                        if (context.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to subscribe: $e'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      } finally {
                        setDialogState(() => _isSubscribing = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(100, 40),
              ),
              child: const Text('Subscribe', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final compareDate = DateTime(date.year, date.month, date.day);

    if (compareDate == today) {
      return 'Today';
    } else if (compareDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEEE, MMM d').format(date);
    }
  }

  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return '10-15 mins';
    final minutes = duration.inMinutes;
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final feedsAsync = ref.watch(subscribedFeedsProvider);
    final recentEpisodesAsync = ref.watch(recentEpisodesProvider);
    final listenedSet = ref.watch(listenedEpisodesProvider);
    final queueState = ref.watch(queueNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Podcasts & News'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.textPrimary),
            onPressed: () => _showAddFeedDialog(context),
            tooltip: 'Subscribe to Feed',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(subscribedFeedsProvider);
          ref.invalidate(recentEpisodesProvider);
        },
        color: AppColors.primary,
        child: CustomScrollView(
          slivers: [
            // ── Section: Subscriptions ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  'My Subscriptions',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),

            feedsAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                ),
              ),
              error: (err, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Error loading feeds: $err', style: const TextStyle(color: AppColors.textMuted)),
                ),
              ),
              data: (feeds) {
                if (feeds.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.podcasts, color: AppColors.textMuted, size: 40),
                            const SizedBox(height: 12),
                            const Text('No subscriptions yet', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            const Text('Subscribe to your first news or podcast feed.', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => _showAddFeedDialog(context),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add RSS Feed'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(160, 36),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return SliverToBoxAdapter(
                  child: SizedBox(
                    height: 125,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: feeds.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (ctx, i) {
                        final feed = feeds[i];
                        return _HorizontalSubscriptionCard(
                          feed: feed,
                          onTap: () => context.push('/podcast/${feed.id}'),
                        );
                      },
                    ),
                  ),
                );
              },
            ),

            // ── Category Filter Chips ────────────────────────────────────────
            feedsAsync.when(
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (feeds) {
                if (feeds.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
                final categories = ['All', ...feeds.map((f) => f.category).toSet().toList()];
                return SliverToBoxAdapter(
                  child: Container(
                    height: 38,
                    margin: const EdgeInsets.only(top: 8, bottom: 8),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final cat = categories[index];
                        final isSelected = _selectedCategory == cat;
                        return ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedCategory = cat;
                              });
                            }
                          },
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.card,
                          side: BorderSide(
                            color: isSelected ? AppColors.primary : AppColors.glassBorder.withValues(alpha: 0.1),
                            width: 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          showCheckmark: false,
                        );
                      },
                    ),
                  ),
                );
              },
            ),

            // ── Section: Recent Episodes ─────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  'Recent Episodes',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),

            recentEpisodesAsync.when(
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              ),
              error: (err, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Error loading recent episodes: $err', style: const TextStyle(color: AppColors.textMuted)),
                  ),
                ),
              ),
              data: (episodes) {
                final feeds = feedsAsync.valueOrNull ?? [];
                final feedCategoryMap = {for (final f in feeds) f.id: f.category};

                final filteredEpisodes = _selectedCategory == 'All'
                    ? episodes
                    : episodes.where((ep) => feedCategoryMap[ep.podcastFeedId] == _selectedCategory).toList();

                if (filteredEpisodes.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        _selectedCategory == 'All'
                            ? 'No recent episodes from the last week.'
                            : 'No recent episodes in this category.',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final episode = filteredEpisodes[index];
                        final isListened = listenedSet.contains(episode.guid);
                        final isExpanded = _expandedEpisodeGuid == episode.guid;

                        // Check if currently playing
                        final currentTrack = queueState.currentTrack;
                        final isCurrentTrack = currentTrack != null &&
                            currentTrack.id == 'podcast_${episode.guid}';
                        final isPlaying = isCurrentTrack && queueState.isPlaying;

                        return _EpisodeCard(
                          episode: episode,
                          isListened: isListened,
                          isExpanded: isExpanded,
                          isPlaying: isPlaying,
                          onPlayTap: () {
                            final track = episode.toJellyfinTrack();
                            final queue = filteredEpisodes.map((e) => e.toJellyfinTrack()).toList();
                            ref.read(queueNotifierProvider.notifier).playTrack(
                                  track,
                                  queue: queue,
                                  queueIndex: index,
                                  fromType: 'podcast',
                                  fromId: 'all_recent',
                                  fromTitle: 'Recent Episodes',
                                );
                          },
                          onListenedToggle: () {
                            ref.read(listenedEpisodesProvider.notifier).toggleListened(episode.guid);
                          },
                          onCardTap: () {
                            setState(() {
                              _expandedEpisodeGuid = isExpanded ? null : episode.guid;
                            });
                          },
                          onHeaderTap: () {
                            // Navigate to detail screen of that show!
                            context.push('/podcast/${episode.podcastFeedId}');
                          },
                          formattedDate: _formatDate(episode.pubDate),
                          formattedDuration: _formatDuration(episode.duration),
                        );
                      },
                      childCount: filteredEpisodes.length,
                    ),
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }
}

// ── Horizontal Subscription Card Widget ──────────────────────────────────────
class _HorizontalSubscriptionCard extends StatelessWidget {
  final PodcastFeed feed;
  final VoidCallback onTap;

  const _HorizontalSubscriptionCard({
    required this.feed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Rounded Cover Art
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl: feed.imageUrl,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: AppColors.surfaceVariant,
                  child: const Icon(Icons.podcasts, color: AppColors.primary, size: 28),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.surfaceVariant,
                  child: const Icon(Icons.podcasts, color: AppColors.primary, size: 28),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Title
            Expanded(
              child: Text(
                feed.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Episode Card Widget ──────────────────────────────────────────────────────
class _EpisodeCard extends StatelessWidget {
  final PodcastEpisode episode;
  final bool isListened;
  final bool isExpanded;
  final bool isPlaying;
  final VoidCallback onPlayTap;
  final VoidCallback onListenedToggle;
  final VoidCallback onCardTap;
  final VoidCallback onHeaderTap;
  final String formattedDate;
  final String formattedDuration;

  const _EpisodeCard({
    required this.episode,
    required this.isListened,
    required this.isExpanded,
    required this.isPlaying,
    required this.onPlayTap,
    required this.onListenedToggle,
    required this.onCardTap,
    required this.onHeaderTap,
    required this.formattedDate,
    required this.formattedDuration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isListened ? AppColors.card.withValues(alpha: 0.6) : AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlaying
              ? AppColors.primary.withValues(alpha: 0.5)
              : AppColors.glassBorder.withValues(alpha: 0.05),
          width: isPlaying ? 1.5 : 0.5,
        ),
      ),
      child: InkWell(
        onTap: onCardTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side: Artwork Thumbnail
              GestureDetector(
                onTap: onHeaderTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: episode.imageUrl,
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.podcasts, color: AppColors.primary, size: 24),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.podcasts, color: AppColors.primary, size: 24),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Right side: Episode content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Feed Header link (e.g. "Up First • Today")
                    GestureDetector(
                      onTap: onHeaderTap,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${episode.podcastTitle} • $formattedDate',
                              style: const TextStyle(
                                color: AppColors.primaryLight,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isListened ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: isListened ? Colors.green : AppColors.textMuted,
                              size: 18,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: onListenedToggle,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Episode Title
                    Text(
                      episode.title,
                      style: TextStyle(
                        color: isListened ? AppColors.textSecondary : AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Episode Description
                    AnimatedCrossFade(
                      firstChild: Text(
                        episode.description,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      secondChild: Text(
                        episode.description,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                      crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 200),
                    ),
                    const SizedBox(height: 10),
                    // Controls Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Play Button
                        GestureDetector(
                          onTap: onPlayTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isPlaying ? AppColors.primaryLight : AppColors.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isPlaying ? 'PLAYING' : 'LISTEN',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Duration
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded, color: AppColors.textMuted, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              formattedDuration,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
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
      ),
    );
  }
}
