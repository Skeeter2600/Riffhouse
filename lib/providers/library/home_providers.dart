part of '../library_provider.dart';

// ---------------------------------------------------------------------------
// New For You (recently-added unplayed albums with 14-day filter + fallback)
// ---------------------------------------------------------------------------

class NewForYouData {
  final List<JellyfinAlbum> albums;
  final bool isFallback;
  const NewForYouData({required this.albums, required this.isFallback});
}

final newAlbumsProvider = FutureProvider<NewForYouData>((ref) async {
  final service = ref.watch(musicServiceProvider);
  if (service == null) return const NewForYouData(albums: [], isFallback: false);

  final rawNewAlbums = await service.getNewAlbums(limit: 20);
  final twoWeeksAgo = DateTime.now().subtract(const Duration(days: 14));

  final recentNewAlbums = rawNewAlbums.where((album) {
    if (album.dateCreated == null) return false;
    return album.dateCreated!.isAfter(twoWeeksAgo);
  }).toList();

  if (recentNewAlbums.isNotEmpty) {
    return NewForYouData(albums: recentNewAlbums, isFallback: false);
  }

  // Fallback: Albums related to recent listens and categories/genres
  final allAlbums = ref.watch(albumsProvider).valueOrNull ?? await service.getAlbums();
  final recentPlays = ref.watch(recentlyPlayedProvider).valueOrNull ?? [];

  // Preferred artists & genres
  final preferredArtists = <String>{};
  final preferredGenres = <String>{};

  for (final item in recentPlays) {
    if (item.type == RecentlyPlayedType.artist) {
      preferredArtists.add(item.title.toLowerCase());
    } else if (item.type == RecentlyPlayedType.album) {
      preferredArtists.add(item.subtitle.toLowerCase());
    }
  }

  for (final album in allAlbums) {
    if (preferredArtists.contains(album.artist.toLowerCase())) {
      preferredGenres.addAll(album.genres.map((g) => g.toLowerCase()));
    }
  }

  final scoredAlbums = <({JellyfinAlbum album, int score})>[];
  for (final album in allAlbums) {
    int score = 0;
    if (preferredArtists.contains(album.artist.toLowerCase())) {
      score += 3;
    }
    for (final g in album.genres) {
      if (preferredGenres.contains(g.toLowerCase())) {
        score += 2;
      }
    }
    if (score > 0) {
      scoredAlbums.add((album: album, score: score));
    }
  }

  scoredAlbums.sort((a, b) => b.score.compareTo(a.score));

  List<JellyfinAlbum> fallbackAlbums = scoredAlbums.map((s) => s.album).take(12).toList();
  if (fallbackAlbums.isEmpty) {
    fallbackAlbums = (List<JellyfinAlbum>.from(allAlbums)..shuffle()).take(12).toList();
  }

  return NewForYouData(albums: fallbackAlbums, isFallback: true);
});

// ---------------------------------------------------------------------------
// Shuffled Home Albums (biased / inspired by recent listens)
// ---------------------------------------------------------------------------

final homeAlbumsProvider = Provider<AsyncValue<List<JellyfinAlbum>>>((ref) {
  final albumsAsync = ref.watch(albumsProvider);
  return albumsAsync.whenData((albums) {
    if (albums.isEmpty) return [];

    final recentPlays = ref.watch(recentlyPlayedProvider).valueOrNull ?? [];

    final preferredArtists = <String>{};
    for (final item in recentPlays) {
      if (item.type == RecentlyPlayedType.artist) {
        preferredArtists.add(item.title.toLowerCase());
      } else if (item.type == RecentlyPlayedType.album) {
        preferredArtists.add(item.subtitle.toLowerCase());
      }
    }

    final inspired = <JellyfinAlbum>[];
    final others = <JellyfinAlbum>[];

    for (final album in albums) {
      if (preferredArtists.contains(album.artist.toLowerCase())) {
        inspired.add(album);
      } else {
        others.add(album);
      }
    }

    final rng = Random();
    final shuffledInspired = List<JellyfinAlbum>.from(inspired)..shuffle(rng);
    final shuffledOthers = List<JellyfinAlbum>.from(others)..shuffle(rng);

    return [...shuffledInspired, ...shuffledOthers];
  });
});

// ---------------------------------------------------------------------------
// Home Genre Mixes (top listened / library genres)
// ---------------------------------------------------------------------------

final homeGenreMixesProvider = FutureProvider<List<String>>((ref) async {
  final playlistService = ref.watch(playlistServiceProvider);
  final topListened = await playlistService.getTopListenedGenres(limit: 8);

  final tracks = ref.watch(tracksProvider).valueOrNull ?? [];
  final genreCounts = <String, int>{};
  for (final t in tracks) {
    for (final g in t.genres) {
      final clean = g.trim();
      if (clean.isNotEmpty) {
        genreCounts[clean] = (genreCounts[clean] ?? 0) + 1;
      }
    }
  }

  final libraryGenres = genreCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final result = <String>[];
  for (final g in topListened) {
    if (genreCounts.containsKey(g) && !result.contains(g)) {
      result.add(g);
    }
  }
  for (final entry in libraryGenres) {
    if (!result.contains(entry.key)) {
      result.add(entry.key);
    }
    if (result.length >= 8) break;
  }
  return result;
});
