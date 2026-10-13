part of '../library_screen.dart';

// ===========================================================================
// Recently Played Section — prominent mixed-media grid
// ===========================================================================

class _RecentlyPlayedSection extends ConsumerWidget {
  const _RecentlyPlayedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentlyPlayedProvider);
    final allAlbumsAsync = ref.watch(albumsProvider);
    final allArtistsAsync = ref.watch(artistsProvider);
    final allPlaylistsAsync = ref.watch(playlistsProvider);
    final service = ref.watch(musicServiceProvider);

    final recentItems = recentAsync.valueOrNull ?? [];
    final hasLocalHistory = recentItems.isNotEmpty;

    // Fallback to library browsing when no play history exists
    final fallbackItems = <RecentlyPlayedItem>[];
    if (!hasLocalHistory) {
      final albums = allAlbumsAsync.valueOrNull ?? [];
      final artists = allArtistsAsync.valueOrNull ?? [];
      final playlists = allPlaylistsAsync.valueOrNull ?? [];
      fallbackItems.addAll(albums.take(8).map((a) => RecentlyPlayedItem(
            id: a.id, title: a.name, subtitle: a.artist,
            imageTag: a.imageTag, type: RecentlyPlayedType.album,
            lastPlayedAt: DateTime(2000))));
      fallbackItems.addAll(artists.take(3).map((a) => RecentlyPlayedItem(
            id: a.id, title: a.name, subtitle: 'Artist',
            imageTag: a.imageTag, type: RecentlyPlayedType.artist,
            lastPlayedAt: DateTime(2000))));
      fallbackItems.addAll(playlists.take(3).map((p) => RecentlyPlayedItem(
            id: p.id, title: p.name, subtitle: '${p.trackCount} tracks',
            imageTag: p.imageTag, type: RecentlyPlayedType.playlist,
            lastPlayedAt: DateTime(2000))));
    }

    final displayItems = hasLocalHistory ? recentItems : fallbackItems;
    final sectionLabel = hasLocalHistory ? 'Recently Played' : 'Your Library';
    final sectionSubtitle = hasLocalHistory ? 'Jump back in' : 'Your music collection';

    final isLoading = recentAsync.isLoading ||
        (!hasLocalHistory && allAlbumsAsync.isLoading);

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
                  Text(sectionLabel,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold, fontSize: 22)),
                  const SizedBox(height: 2),
                  Text(sectionSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary)),
                ],
              ),
              if (!isLoading && displayItems.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${displayItems.length} items',
                      style: const TextStyle(
                          color: AppColors.primaryLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (isLoading)
          _shimmerRecentRow()
        else if (displayItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: _EmptyRecentCard(),
          )
        else
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: displayItems.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (ctx, i) =>
                  _RecentCard(item: displayItems[i], service: service),
            ),
          ),
      ],
    );
  }

  Widget _shimmerRecentRow() {
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, __) => Shimmer.fromColors(
          baseColor: AppColors.surfaceVariant,
          highlightColor: AppColors.card,
          child: Container(
            width: 130,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state for Recently Played
// ---------------------------------------------------------------------------

class _EmptyRecentCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder, width: 0.5),
      ),
      child: const Column(
        children: [
          Icon(Icons.history_rounded, color: AppColors.textMuted, size: 36),
          SizedBox(height: 10),
          Text('No recent plays yet',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          SizedBox(height: 4),
          Text('Start listening to see your history here',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent card widget — now uses RecentlyPlayedItem directly
// ---------------------------------------------------------------------------

class _RecentCard extends StatelessWidget {
  final RecentlyPlayedItem item;
  final dynamic service;

  const _RecentCard({required this.item, required this.service});

  Color get _typeColor {
    if (item.type == RecentlyPlayedType.mix && item.colorValue != null) {
      return Color(item.colorValue!);
    }
    switch (item.type) {
      case RecentlyPlayedType.album: return AppColors.primary;
      case RecentlyPlayedType.artist: return const Color(0xFF06B6D4);
      case RecentlyPlayedType.playlist: return const Color(0xFFEC4899);
      case RecentlyPlayedType.track: return AppColors.primary;
      case RecentlyPlayedType.mix: return const Color(0xFF8B5CF6);
    }
  }

  String get _typeLabel {
    switch (item.type) {
      case RecentlyPlayedType.album: return 'ALBUM';
      case RecentlyPlayedType.artist: return 'ARTIST';
      case RecentlyPlayedType.playlist: return 'PLAYLIST';
      case RecentlyPlayedType.track: return 'TRACK';
      case RecentlyPlayedType.mix: return 'MIX';
    }
  }

  IconData get _fallbackIcon {
    switch (item.type) {
      case RecentlyPlayedType.album: return Icons.album_rounded;
      case RecentlyPlayedType.artist: return Icons.person_rounded;
      case RecentlyPlayedType.playlist: return Icons.queue_music_rounded;
      case RecentlyPlayedType.track: return Icons.music_note_rounded;
      case RecentlyPlayedType.mix:
        if (item.mixType == 'daily_drive') return Icons.directions_car_rounded;
        if (item.mixType == 'heavy') return Icons.replay_rounded;
        if (item.mixType == 'undiscovered') return Icons.explore_rounded;
        return Icons.auto_awesome_rounded;
    }
  }

  void _navigate(BuildContext context) {
    switch (item.type) {
      case RecentlyPlayedType.album:
        context.push('/album/${item.id}'); break;
      case RecentlyPlayedType.artist:
        context.push('/artist/${item.id}'); break;
      case RecentlyPlayedType.playlist:
        context.push('/playlist/${item.id}'); break;
      case RecentlyPlayedType.track: break;
      case RecentlyPlayedType.mix:
        if (item.mixType != null) {
          context.push('/smart-mix/${item.mixType}');
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = (service != null && item.imageTag != null)
        ? service.getImageUrl(item.id, item.imageTag!)
        : null;
    final isArtist = item.type == RecentlyPlayedType.artist;

    return GestureDetector(
      onTap: () => _navigate(context),
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 130,
              width: 130,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(isArtist ? 65 : 14),
                boxShadow: [BoxShadow(
                  color: _typeColor.withValues(alpha: 0.25),
                  blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isArtist ? 65 : 14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LocalCoverOr(
                      itemId: item.type == RecentlyPlayedType.playlist
                          ? item.id
                          : null,
                      child: imageUrl != null
                          ? CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover,
                              placeholder: (_, __) => _placeholder(),
                              errorWidget: (_, __, ___) => _placeholder())
                          : _placeholder(),
                    ),
                    if (!isArtist)
                      Positioned(
                        bottom: 8, left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: _typeColor.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(6)),
                          child: Text(_typeLabel,
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 9, fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(item.title,
                style: const TextStyle(color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(item.subtitle,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    if (item.type == RecentlyPlayedType.mix && item.colorValue != null) {
      final c1 = Color(item.colorValue!);
      final c2 = item.secondaryColorValue != null
          ? Color(item.secondaryColorValue!)
          : c1.withValues(alpha: 0.7);
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c1, c2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Icon(_fallbackIcon, color: Colors.white.withValues(alpha: 0.9), size: 44),
        ),
      );
    }
    return Container(
      color: AppColors.surfaceVariant,
      child: Icon(_fallbackIcon, color: _typeColor.withValues(alpha: 0.7), size: 36),
    );
  }
}
