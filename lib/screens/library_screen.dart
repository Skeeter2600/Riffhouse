import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../models/jellyfin_models.dart';
import '../models/podcast_episode.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/podcast_provider.dart';
import '../audio/queue_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/album_card.dart';
import '../widgets/track_card.dart';
import 'package:intl/intl.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _isSearching = false;
  Timer? _debounce;

  List<JellyfinPlaylist> _matchedPlaylists = [];
  List<JellyfinTrack> _matchedTracks = [];
  List<JellyfinAlbum> _matchedAlbums = [];
  List<JellyfinArtist> _matchedArtists = [];
  List<String> _matchedGenres = [];

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() => _searchQuery = value);

    if (value.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _matchedPlaylists = [];
        _matchedTracks = [];
        _matchedAlbums = [];
        _matchedArtists = [];
        _matchedGenres = [];
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(value.trim()));
  }

  Future<void> _runSearch(String query) async {
    final service = ref.read(jellyfinServiceProvider);
    setState(() => _isSearching = true);

    try {
      final qLower = query.toLowerCase();
      final allPlaylists = ref.read(playlistsProvider).valueOrNull ?? [];
      final filteredPlaylists = allPlaylists
          .where((p) => p.name.toLowerCase().contains(qLower))
          .take(10)
          .toList();

      // Collect unique genres from the local track library
      final allTracks = ref.read(tracksProvider).valueOrNull ?? [];
      final genreSet = <String>{};
      for (final t in allTracks) {
        for (final g in t.genres) {
          final clean = g.trim();
          if (clean.isNotEmpty) genreSet.add(clean);
        }
      }
      final filteredGenres = genreSet
          .where((g) => g.toLowerCase().contains(qLower))
          .take(3)
          .toList()
        ..sort();

      List<JellyfinTrack> tracks = [];
      List<JellyfinAlbum> albums = [];
      List<JellyfinArtist> artists = [];

      if (service != null) {
        final results = await Future.wait([
          service.searchTracks(query),
          service.searchAlbums(query),
          service.searchArtists(query),
        ]);
        tracks = (results[0] as List<JellyfinTrack>).take(10).toList();
        albums = (results[1] as List<JellyfinAlbum>).take(10).toList();
        artists = (results[2] as List<JellyfinArtist>).take(10).toList();
      }

      if (mounted) {
        setState(() {
          _isSearching = false;
          _matchedPlaylists = filteredPlaylists;
          _matchedTracks = tracks;
          _matchedAlbums = albums;
          _matchedArtists = artists;
          _matchedGenres = filteredGenres;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final albumsAsync = ref.watch(homeAlbumsProvider);

    final isSearching = _searchQuery.trim().isNotEmpty || _searchFocusNode.hasFocus;

    return PopScope(
      canPop: !isSearching,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isSearching) {
          setState(() {
            _searchController.clear();
            _searchQuery = '';
            _isSearching = false;
            _matchedPlaylists = [];
            _matchedTracks = [];
            _matchedAlbums = [];
            _matchedArtists = [];
            _matchedGenres = [];
          });
          _searchFocusNode.unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          slivers: [
            // ── App Bar & Evident Search Bar ─────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 52),
                    Text(
                      '${_greeting()},',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user?.name ?? 'Listener',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold, fontSize: 24),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _searchQuery.isNotEmpty
                              ? AppColors.primary
                              : AppColors.glassBorder,
                          width: _searchQuery.isNotEmpty ? 1.5 : 1,
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search songs, albums, artists, playlists...',
                          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 22),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, color: AppColors.textMuted, size: 20),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onQueryChanged('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        onChanged: _onQueryChanged,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_searchQuery.trim().isNotEmpty)
              ..._buildSearchSlivers()
            else
              ..._buildLibrarySlivers(context, albumsAsync),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSearchSlivers() {
    if (_isSearching) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text('Searching library...', style: TextStyle(color: AppColors.textMuted)),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    final hasResults = _matchedGenres.isNotEmpty ||
        _matchedPlaylists.isNotEmpty ||
        _matchedTracks.isNotEmpty ||
        _matchedAlbums.isNotEmpty ||
        _matchedArtists.isNotEmpty;

    if (!hasResults) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.music_off_rounded, color: AppColors.textMuted, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    'No results for "$_searchQuery"',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    final slivers = <Widget>[];

    // 0. Genre Mixes (max 3) — shown first
    if (_matchedGenres.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: _sectionHeader(context, 'Genre Mixes'),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => _GenreSearchResultTile(genre: _matchedGenres[i]),
          childCount: _matchedGenres.length,
        ),
      ));
    }

    // 1. Playlists (max 10)
    if (_matchedPlaylists.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: _sectionHeader(context, 'Playlists (${_matchedPlaylists.length})'),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => _PlaylistResultTile(playlist: _matchedPlaylists[i]),
          childCount: _matchedPlaylists.length,
        ),
      ));
    }

    // 2. Songs (max 10)
    if (_matchedTracks.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: _sectionHeader(context, 'Songs (${_matchedTracks.length})'),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => TrackCard(track: _matchedTracks[i]),
          childCount: _matchedTracks.length,
        ),
      ));
    }

    // 3. Albums (max 10)
    if (_matchedAlbums.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: _sectionHeader(context, 'Albums (${_matchedAlbums.length})'),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => _AlbumResultTile(album: _matchedAlbums[i]),
          childCount: _matchedAlbums.length,
        ),
      ));
    }

    // 4. Artists (max 10)
    if (_matchedArtists.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: _sectionHeader(context, 'Artists (${_matchedArtists.length})'),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => _ArtistResultTile(artist: _matchedArtists[i]),
          childCount: _matchedArtists.length,
        ),
      ));
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 100)));
    return slivers;
  }

  List<Widget> _buildLibrarySlivers(
      BuildContext context, AsyncValue<List<JellyfinAlbum>> albumsAsync) {
    return [
      // â”€â”€ Smart Mixes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                    title: 'Daily Drive',
                    subtitle: 'News + music',
                    colors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
                    icon: Icons.directions_car_rounded,
                    onTap: () => context.push('/smart-mix/daily_drive'),
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

          // â”€â”€ Recently Played â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const SliverToBoxAdapter(child: _RecentlyPlayedSection()),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // â”€â”€ Genre Mixes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const SliverToBoxAdapter(child: _GenreMixesSection()),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // â”€â”€ News & Podcasts â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const SliverToBoxAdapter(child: _NewsPodcastsSection()),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // â”€â”€ New For You â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const SliverToBoxAdapter(child: _NewForYouSection()),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // â”€â”€ Albums â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            error: (_, __) => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Error loading albums',
                    style: TextStyle(color: AppColors.textMuted)),
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
    ];
  }

  Widget _sectionHeader(BuildContext context, String title, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          if (action != null) action,
        ],
      ),
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
// Recently Played Section â€” prominent mixed-media grid
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
// Recent card widget â€” now uses RecentlyPlayedItem directly
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
                    if (imageUrl != null)
                      CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover,
                          placeholder: (_, __) => _placeholder(),
                          errorWidget: (_, __, ___) => _placeholder())
                    else
                      _placeholder(),
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
      data: (data) {
        final albums = data.albums;
        final isFallback = data.isFallback;
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
                        isFallback
                            ? 'Inspired by your recent listens'
                            : 'Fresh albums you haven\'t heard yet',
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
                                  // Badge
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
                                      child: Text(
                                        isFallback ? 'FOR YOU' : 'NEW',
                                        style: const TextStyle(
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

// ===========================================================================
// Genre Mixes Section
// ===========================================================================

class _GenreMixesSection extends ConsumerWidget {
  const _GenreMixesSection();

  static const _palette = [
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // Blue
    [Color(0xFF10B981), Color(0xFF047857)], // Emerald
    [Color(0xFFF97316), Color(0xFFC2410C)], // Orange
    [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // Purple
    [Color(0xFFEC4899), Color(0xFFBE185D)], // Pink
    [Color(0xFF14B8A6), Color(0xFF0F766E)], // Teal
    [Color(0xFFEAB308), Color(0xFFA16207)], // Amber
    [Color(0xFF6366F1), Color(0xFF4338CA)], // Indigo
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(homeGenreMixesProvider);

    return genresAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (genres) {
        if (genres.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Genre Mixes',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          )),
                  const SizedBox(height: 2),
                  Text('Daily mixes of your favorite genres',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          )),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: genres.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (ctx, i) {
                  final genre = genres[i];
                  final colors = _palette[i % _palette.length];
                  return _GenreMixCard(
                    genre: genre,
                    colors: colors,
                    onTap: () => context.push('/smart-mix/genre_${Uri.encodeComponent(genre)}'),
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

class _GenreMixCard extends StatelessWidget {
  final String genre;
  final List<Color> colors;
  final VoidCallback onTap;

  const _GenreMixCard({
    required this.genre,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 130,
              width: 130,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.first.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: -15,
                    right: -15,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(
                      Icons.music_note_rounded,
                      color: Colors.white.withValues(alpha: 0.9),
                      size: 40,
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'GENRE',
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
            const SizedBox(height: 8),
            Text(
              '$genre Mix',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            const Text(
              'Daily mix',
              style: TextStyle(
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
  }
}

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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final compareDate = DateTime(date.year, date.month, date.day);

    if (compareDate == today) return 'Today';
    if (compareDate == yesterday) return 'Yesterday';
    return DateFormat('EEE, MMM d').format(date);
  }

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
                                _formatDate(episode.pubDate),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '  â€¢  ${episode.duration.inMinutes} min',
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

// ---------------------------------------------------------------------------
// Search Result Tiles for Library Search
// ---------------------------------------------------------------------------

class _PlaylistResultTile extends ConsumerWidget {
  final JellyfinPlaylist playlist;
  const _PlaylistResultTile({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(jellyfinServiceProvider);
    final imageUrl = (service != null && playlist.imageTag != null)
        ? service.getImageUrl(playlist.id, playlist.imageTag!)
        : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
      title: Text(
        playlist.name,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${playlist.trackCount} tracks',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: () => context.push('/playlist/${playlist.id}'),
    );
  }

  Widget _ph() => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.queue_music_rounded, color: AppColors.textMuted),
      );
}

class _AlbumResultTile extends ConsumerWidget {
  final JellyfinAlbum album;
  const _AlbumResultTile({required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(jellyfinServiceProvider);
    final imageUrl = (service != null && album.imageTag != null)
        ? service.getImageUrl(album.id, album.imageTag!)
        : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
      title: Text(
        album.name,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        album.artist,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: () => context.push('/album/${album.id}'),
    );
  }

  Widget _ph() => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.album_rounded, color: AppColors.textMuted),
      );
}

class _ArtistResultTile extends ConsumerWidget {
  final JellyfinArtist artist;
  const _ArtistResultTile({required this.artist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(jellyfinServiceProvider);
    final imageUrl = (service != null && artist.imageTag != null)
        ? service.getImageUrl(artist.id, artist.imageTag!)
        : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.surfaceVariant,
        backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
        child: imageUrl == null
            ? const Icon(Icons.person_rounded, color: AppColors.textMuted, size: 24)
            : null,
      ),
      title: Text(
        artist.name,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: () => context.push('/artist/${artist.id}'),
    );
  }
}

// ---------------------------------------------------------------------------
// Genre Search Result Tile — opens a SmartMixDetailScreen for the genre
// ---------------------------------------------------------------------------

class _GenreSearchResultTile extends ConsumerWidget {
  final String genre;
  const _GenreSearchResultTile({required this.genre});

  static const _palette = [
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
    [Color(0xFF10B981), Color(0xFF047857)],
    [Color(0xFFF97316), Color(0xFFC2410C)],
    [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
    [Color(0xFFEC4899), Color(0xFFBE185D)],
    [Color(0xFF14B8A6), Color(0xFF0F766E)],
    [Color(0xFFEAB308), Color(0xFFA16207)],
    [Color(0xFF6366F1), Color(0xFF4338CA)],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = _palette[genre.hashCode.abs() % _palette.length];
    final mixType = 'genre_${Uri.encodeComponent(genre)}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 24),
      ),
      title: Text(
        '$genre Mix',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: const Text(
        'Genre Mix · Tap to play',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: () => context.push('/smart-mix/$mixType'),
    );
  }
}
