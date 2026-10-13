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
import '../utils/formatters.dart';
import '../widgets/art_placeholder.dart';
import '../widgets/local_cover.dart';

part 'library/recently_played_section.dart';
part 'library/new_for_you_section.dart';
part 'library/genre_mixes_section.dart';
part 'library/news_podcasts_section.dart';
part 'library/search_result_tiles.dart';

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
    final service = ref.read(musicServiceProvider);
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
        body: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              ref.read(albumsProvider.notifier).refresh(),
              ref.read(playlistsProvider.notifier).refresh(),
              ref.read(artistsProvider.notifier).refresh(),
              ref.read(tracksProvider.notifier).refresh(),
            ]);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
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
