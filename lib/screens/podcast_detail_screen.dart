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

class PodcastDetailScreen extends ConsumerStatefulWidget {
  final String feedId;

  const PodcastDetailScreen({super.key, required this.feedId});

  @override
  ConsumerState<PodcastDetailScreen> createState() => _PodcastDetailScreenState();
}

class _PodcastDetailScreenState extends ConsumerState<PodcastDetailScreen> {
  bool _filterLastWeek = true;
  String? _expandedEpisodeGuid;

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

  void _confirmUnsubscribe(BuildContext context, PodcastFeed feed) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Unsubscribe from ${feed.title}', style: const TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to remove this podcast from your subscriptions?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(subscribedFeedsProvider.notifier).unsubscribe(feed.id);
              context.pop();
            },
            child: const Text('Unsubscribe', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feedsAsync = ref.watch(subscribedFeedsProvider);
    final listenedSet = ref.watch(listenedEpisodesProvider);
    final queueState = ref.watch(queueNotifierProvider);

    return feedsAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.textMuted))),
      ),
      data: (feeds) {
        final feed = feeds.firstWhere(
          (f) => f.id == widget.feedId,
          orElse: () => const PodcastFeed(id: '', title: '', publisher: '', rssUrl: '', imageUrl: '', description: '', category: ''),
        );

        if (feed.id.isEmpty) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: Text('Podcast not found', style: TextStyle(color: AppColors.textMuted))),
          );
        }

        final episodesAsync = ref.watch(podcastEpisodesProvider(feed));

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            slivers: [
              // ── Header Banner ──────────────────────────────────────────────
              SliverAppBar(
                expandedHeight: 240,
                floating: false,
                pinned: true,
                backgroundColor: AppColors.surface,
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  onPressed: () => context.pop(),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.playlist_remove, color: Colors.redAccent),
                    onPressed: () => _confirmUnsubscribe(context, feed),
                    tooltip: 'Unsubscribe',
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Gradient Background
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primaryDark.withValues(alpha: 0.8),
                              const Color(0xFF0F172A),
                              AppColors.background,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      // Content Overlay
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Podcast Logo
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: CachedNetworkImage(
                                  imageUrl: feed.imageUrl,
                                  width: 110,
                                  height: 110,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    color: AppColors.surfaceVariant,
                                    child: const Icon(Icons.podcasts, color: AppColors.primary, size: 40),
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    color: AppColors.surfaceVariant,
                                    child: const Icon(Icons.podcasts, color: AppColors.primary, size: 40),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Podcast Metadata
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 0.5),
                                      ),
                                      child: Text(
                                        feed.category.toUpperCase(),
                                        style: const TextStyle(
                                          color: AppColors.primaryLight,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      feed.title,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      feed.publisher,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: Text(
                                        feed.description,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Filter Tabs ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'Last 7 Days',
                        isSelected: _filterLastWeek,
                        onSelected: () => setState(() => _filterLastWeek = true),
                      ),
                      const SizedBox(width: 10),
                      _FilterChip(
                        label: 'All Episodes',
                        isSelected: !_filterLastWeek,
                        onSelected: () => setState(() => _filterLastWeek = false),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Episodes List ──────────────────────────────────────────────
              episodesAsync.when(
                loading: () => const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
                error: (err, _) => SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            'Failed to load episodes',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            err.toString(),
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                data: (episodes) {
                  final now = DateTime.now();
                  final filtered = _filterLastWeek
                      ? episodes.where((ep) => now.difference(ep.pubDate).inDays <= 7).toList()
                      : episodes;

                  if (filtered.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.calendar_today_outlined, color: AppColors.textMuted, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              _filterLastWeek
                                  ? 'No episodes in the last week'
                                  : 'No episodes available',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final episode = filtered[index];
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
                              final queue = filtered.map((e) => e.toJellyfinTrack()).toList();
                              ref.read(queueNotifierProvider.notifier).playTrack(
                                    track,
                                    queue: queue,
                                    queueIndex: index,
                                    fromType: 'podcast',
                                    fromId: feed.id,
                                    fromTitle: feed.title,
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
                            formattedDate: _formatDate(episode.pubDate),
                            formattedDuration: _formatDuration(episode.duration),
                          );
                        },
                        childCount: filtered.length,
                      ),
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
}

// ── Filter Chip Widget ───────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date & Listened Checkbox Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formattedDate,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isListened ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isListened ? Colors.green : AppColors.textMuted,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onListenedToggle,
                    tooltip: isListened ? 'Mark as unlistened' : 'Mark as listened',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Episode Title
              Text(
                episode.title,
                style: TextStyle(
                  color: isListened ? AppColors.textSecondary : AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              // Episode Description
              AnimatedCrossFade(
                firstChild: Text(
                  episode.description,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                secondChild: Text(
                  episode.description,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
              const SizedBox(height: 12),
              // Controls Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Play Button
                  GestureDetector(
                    onTap: onPlayTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isPlaying ? 'PLAYING' : 'LISTEN',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
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
                      const Icon(Icons.access_time_rounded, color: AppColors.textMuted, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        formattedDuration,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
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
      ),
    );
  }
}
