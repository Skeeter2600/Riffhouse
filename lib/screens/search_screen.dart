import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../audio/queue_notifier.dart';
import '../models/jellyfin_models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/track_card.dart';

// ─── Search result state ──────────────────────────────────────────────────────

class _SearchResults {
  final List<JellyfinTrack> tracks;
  final List<JellyfinAlbum> albums;
  final List<JellyfinArtist> artists;
  const _SearchResults({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
  });
  bool get isEmpty => tracks.isEmpty && albums.isEmpty && artists.isEmpty;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  bool _isSearching = false;
  _SearchResults _results = const _SearchResults();
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() => _query = value);

    if (value.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _results = const _SearchResults();
      });
      return;
    }

    // 350ms debounce — waits for the user to pause typing
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(value.trim()));
  }

  Future<void> _runSearch(String query) async {
    final service = ref.read(jellyfinServiceProvider);
    if (service == null) return;

    setState(() => _isSearching = true);

    // Fire all three searches concurrently
    final results = await Future.wait([
      service.searchTracks(query),
      service.searchAlbums(query),
      service.searchArtists(query),
    ]);

    if (mounted) {
      setState(() {
        _isSearching = false;
        _results = _SearchResults(
          tracks: results[0] as List<JellyfinTrack>,
          albums: results[1] as List<JellyfinAlbum>,
          artists: results[2] as List<JellyfinArtist>,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        automaticallyImplyLeading: false,
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search tracks, albums, artists...',
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.textMuted),
                    onPressed: () {
                      _controller.clear();
                      _onQueryChanged('');
                    },
                  )
                : null,
          ),
          onChanged: _onQueryChanged,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_query.trim().isEmpty) return _emptyPrompt();

    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text('Searching...', style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
    }

    if (_results.isEmpty) return _noResults();

    return ListView(
      children: [
        // ── Tracks ──────────────────────────────────────────────────────────
        if (_results.tracks.isNotEmpty) ...[
          _sectionHeader('Tracks', _results.tracks.length),
          ..._results.tracks.mapIndexed((i, t) => TrackCard(
                track: t,
                queue: _results.tracks,
                queueIndex: i,
              )),
        ],

        // ── Albums ──────────────────────────────────────────────────────────
        if (_results.albums.isNotEmpty) ...[
          _sectionHeader('Albums', _results.albums.length),
          ..._results.albums.map((a) => _AlbumResultTile(album: a)),
        ],

        // ── Artists ─────────────────────────────────────────────────────────
        if (_results.artists.isNotEmpty) ...[
          _sectionHeader('Artists', _results.artists.length),
          ..._results.artists.map((a) => _ArtistResultTile(artist: a)),
        ],

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _emptyPrompt() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, color: AppColors.textMuted, size: 64),
          SizedBox(height: 16),
          Text('Search your library',
              style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _noResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_off_rounded, color: AppColors.textMuted, size: 64),
          const SizedBox(height: 16),
          Text('No results for "$_query"',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontSize: 16)),
          const SizedBox(width: 8),
          Text('($count)',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── Result tiles ─────────────────────────────────────────────────────────────

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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      title: Text(album.name,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      subtitle: Text(album.artist,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: () => context.push('/album/${album.id}'),
    );
  }

  Widget _ph() => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.album, color: AppColors.textMuted),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.surfaceVariant,
        backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
        child: imageUrl == null
            ? const Icon(Icons.person_rounded, color: AppColors.textMuted, size: 24)
            : null,
      ),
      title: Text(artist.name,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: () => context.push('/artist/${artist.id}'),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

extension IndexedMap<T> on List<T> {
  List<R> mapIndexed<R>(R Function(int index, T item) f) {
    return asMap().entries.map((e) => f(e.key, e.value)).toList();
  }
}
