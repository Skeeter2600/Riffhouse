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

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final albumsAsync = ref.watch(albumsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ─────────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: AppColors.background,
            floating: true,
            pinned: false,
            automaticallyImplyLeading: false,
            toolbarHeight: 72,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_greeting()},',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user?.name ?? 'Listener',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.search_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => context.go('/home/search'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined,
                          color: AppColors.textPrimary),
                      onPressed: () => context.push('/settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Smart Mixes ─────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _sectionHeader(context, 'Smart Mixes'),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 140,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _MixCard(
                    title: 'Daily Mix',
                    subtitle: 'Curated for you',
                    colors: const [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                    icon: Icons.auto_awesome,
                    onTap: () => context.push('/smart-mix/daily'),
                  ),
                  const SizedBox(width: 12),
                  _MixCard(
                    title: 'Heavy Rotation',
                    subtitle: 'Your favorites',
                    colors: const [Color(0xFFEC4899), Color(0xFFBE185D)],
                    icon: Icons.replay_rounded,
                    onTap: () => context.push('/smart-mix/heavy'),
                  ),
                  const SizedBox(width: 12),
                  _MixCard(
                    title: 'Undiscovered',
                    subtitle: 'New to you',
                    colors: const [Color(0xFF06B6D4), Color(0xFF0369A1)],
                    icon: Icons.explore_rounded,
                    onTap: () => context.push('/smart-mix/undiscovered'),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Recently Played ─────────────────────────────────────────────────
          const SliverToBoxAdapter(child: _RecentlyPlayedSection()),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── New For You ─────────────────────────────────────────────────────
          const SliverToBoxAdapter(child: _NewForYouSection()),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Albums ──────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Albums',
                      style: Theme.of(context).textTheme.headlineSmall),
                  TextButton(
                    onPressed: () {},
                    child: const Text(
                      'See All',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),

          albumsAsync.when(
            loading: () => SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _shimmerCard(),
                  childCount: 6,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.75,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
              ),
            ),
            error: (_, __) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Error loading albums',
                    style: const TextStyle(color: AppColors.textMuted)),
              ),
            ),
            data: (albums) => SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => AlbumCard(album: albums[i]),
                  childCount: albums.take(20).length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.75,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 10),
      child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
    );
  }

  static Widget _shimmerCard() {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceVariant,
      highlightColor: AppColors.card,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

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
    final service = ref.watch(jellyfinServiceProvider);

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
    switch (item.type) {
      case RecentlyPlayedType.album: return AppColors.primary;
      case RecentlyPlayedType.artist: return const Color(0xFF06B6D4);
      case RecentlyPlayedType.playlist: return const Color(0xFFEC4899);
      case RecentlyPlayedType.track: return AppColors.primary;
    }
  }

  String get _typeLabel {
    switch (item.type) {
      case RecentlyPlayedType.album: return 'ALBUM';
      case RecentlyPlayedType.artist: return 'ARTIST';
      case RecentlyPlayedType.playlist: return 'PLAYLIST';
      case RecentlyPlayedType.track: return 'TRACK';
    }
  }

  IconData get _fallbackIcon {
    switch (item.type) {
      case RecentlyPlayedType.album: return Icons.album_rounded;
      case RecentlyPlayedType.artist: return Icons.person_rounded;
      case RecentlyPlayedType.playlist: return Icons.queue_music_rounded;
      case RecentlyPlayedType.track: return Icons.music_note_rounded;
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
                    if (imageUrl != null)
                      CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover,
                          placeholder: (_, __) => _placeholder(),
                          errorWidget: (_, __, ___) => _placeholder())
                    else
                      _placeholder(),
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

  Widget _placeholder() => Container(
    color: AppColors.surfaceVariant,
    child: Icon(_fallbackIcon, color: _typeColor.withValues(alpha: 0.7), size: 36),
  );
}

// ===========================================================================
// New For You Section
// ===========================================================================


class _NewForYouSection extends ConsumerWidget {
  const _NewForYouSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newAlbumsAsync = ref.watch(newAlbumsProvider);
    final service = ref.watch(jellyfinServiceProvider);

    return newAlbumsAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.only(left: 20, top: 20, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 120, height: 20,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, __) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 130, height: 160,
                    color: AppColors.card,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (albums) {
        if (albums.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 22,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFF06B6D4)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New For You',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Fresh albums you haven\'t heard yet',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: albums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (ctx, i) {
                  final album = albums[i];
                  final imageUrl = (service != null && album.imageTag != null)
                      ? service.getImageUrl(album.id, album.imageTag!)
                      : null;

                  return GestureDetector(
                    onTap: () => context.push('/album/${album.id}'),
                    child: SizedBox(
                      width: 150,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 150,
                            width: 150,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.2),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (imageUrl != null)
                                    CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => _albumPlaceholder(),
                                      errorWidget: (_, __, ___) => _albumPlaceholder(),
                                    )
                                  else
                                    _albumPlaceholder(),
                                  // "New" badge
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF7C3AED), Color(0xFF06B6D4)],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'NEW',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            album.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            album.artist,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _albumPlaceholder() {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.album_rounded,
          color: AppColors.primary, size: 40),
    );
  }
}

// ===========================================================================
// Mix card
// ===========================================================================

class _MixCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Color> colors;
  final IconData icon;
  final VoidCallback onTap;

  const _MixCard({
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 28),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
