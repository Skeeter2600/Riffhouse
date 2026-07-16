import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../models/jellyfin_models.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_feed.dart';
import 'jellyfin_service.dart';
import 'podcast_service.dart';

/// Manages playlist synchronisation and smart mix generation using Drift.
class PlaylistService {
  final AppDatabase db;
  JellyfinService jellyfinService;

  PlaylistService(this.db, this.jellyfinService);

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  /// Fetches all playlists from the Jellyfin server and upserts them locally.
  Future<void> syncPlaylists() async {
    final serverPlaylists = await jellyfinService.getPlaylists();

    for (final playlist in serverPlaylists) {
      final existing = await db.getLocalPlaylist(playlist.id);
      await db.upsertLocalPlaylist(LocalPlaylistsCompanion(
        id: existing != null ? Value(existing.id) : const Value.absent(),
        jellyfinId: Value(playlist.id),
        name: Value(playlist.name),
        trackIdsJson: existing != null 
            ? Value(existing.trackIdsJson) 
            : const Value('[]'),
        lastSyncedAt: Value(DateTime.now()),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Smart mix (25 / 25 / 50 curation)
  // ---------------------------------------------------------------------------

  /// Generates a smart mix using the 25/25/50 curation algorithm.
  ///
  /// The [libraryTracks] list is the full set of tracks to pick from.
  /// Optional [genreFilter] and [artistFilter] narrow the candidate pool.
  /// Returns up to [count] tracks (default 30).
  ///
  /// Distribution:
  /// - 25% from **heavy** tracks (playCount >= 5)
  /// - 25% from **low** tracks (playCount 1–4)
  /// - 50% from **unplayed** tracks (playCount == 0)
  Future<List<JellyfinTrack>> getSmartMix({
    List<String>? genreFilter,
    String? artistFilter,
    int count = 30,
    required List<JellyfinTrack> libraryTracks,
  }) async {
    // Apply optional genre / artist filters.
    final candidates = libraryTracks.where((track) {
      if (genreFilter != null && genreFilter.isNotEmpty) {
        final hasGenre = track.genres.any(
          (g) => genreFilter.any(
            (f) => g.toLowerCase().contains(f.toLowerCase()),
          ),
        );
        if (!hasGenre) return false;
      }
      if (artistFilter != null && artistFilter.isNotEmpty) {
        final hasArtist = track.artists.any(
          (a) => a.toLowerCase().contains(artistFilter.toLowerCase()),
        ) || track.albumArtist.toLowerCase().contains(artistFilter.toLowerCase());
        if (!hasArtist) return false;
      }
      return true;
    }).toList();

    // Load all playback records from database.
    final allRecords = await db.getAllPlaybackRecords();
    final recordMap = <String, PlaybackRecord>{
      for (final r in allRecords) r.jellyfinId: r,
    };

    // Bucket the candidates.
    final heavy = <JellyfinTrack>[];   // playCount >= 5
    final low = <JellyfinTrack>[];    // playCount 1–4
    final unplayed = <JellyfinTrack>[]; // playCount == 0

    for (final track in candidates) {
      final record = recordMap[track.id];
      final playCount = record?.playCount ?? 0;

      if (playCount >= 5) {
        heavy.add(track);
      } else if (playCount >= 1) {
        low.add(track);
      } else {
        unplayed.add(track);
      }
    }

    // Shuffle each bucket independently.
    final rng = Random();
    heavy.shuffle(rng);
    low.shuffle(rng);
    unplayed.shuffle(rng);

    // Calculate pick counts (floor to avoid exceeding [count]).
    final heavyCount = (count * 0.25).floor();
    final lowCount = (count * 0.25).floor();
    final unplayedCount = count - heavyCount - lowCount;

    final result = <JellyfinTrack>[
      ...heavy.take(heavyCount),
      ...low.take(lowCount),
      ...unplayed.take(unplayedCount),
    ];

    // If we are short (some buckets were smaller than quota), pad with
    // whatever is left across the other buckets.
    if (result.length < count) {
      final used = result.map((t) => t.id).toSet();
      final remaining = candidates
          .where((t) => !used.contains(t.id))
          .toList()
        ..shuffle(rng);
      result.addAll(remaining.take(count - result.length));
    }

    // Final shuffle for variety.
    result.shuffle(rng);
    return result;
  }

  /// Generates a Heavy Rotation mix (most played tracks first, shuffled for variety).
  Future<List<JellyfinTrack>> getHeavyRotation({
    int count = 30,
    required List<JellyfinTrack> libraryTracks,
  }) async {
    final allRecords = await db.getAllPlaybackRecords();
    final recordMap = <String, PlaybackRecord>{
      for (final r in allRecords) r.jellyfinId: r,
    };

    // Sort tracks by playCount descending
    final playedTracks = libraryTracks.where((t) {
      final rec = recordMap[t.id];
      return rec != null && rec.playCount > 0;
    }).toList();

    playedTracks.sort((a, b) {
      final countA = recordMap[a.id]?.playCount ?? 0;
      final countB = recordMap[b.id]?.playCount ?? 0;
      return countB.compareTo(countA); // Descending
    });

    // Take top tracks
    final result = playedTracks.take(count).toList();

    // If we don't have enough played tracks, pad with random tracks
    if (result.length < count) {
      final rng = Random();
      final remaining = libraryTracks
          .where((t) => !result.contains(t))
          .toList()
        ..shuffle(rng);
      result.addAll(remaining.take(count - result.length));
    }

    result.shuffle();
    return result;
  }

  /// Generates an Undiscovered mix (random selection of unplayed tracks).
  Future<List<JellyfinTrack>> getUndiscovered({
    int count = 30,
    required List<JellyfinTrack> libraryTracks,
  }) async {
    final allRecords = await db.getAllPlaybackRecords();
    final recordMap = <String, PlaybackRecord>{
      for (final r in allRecords) r.jellyfinId: r,
    };

    final unplayed = libraryTracks.where((t) {
      final rec = recordMap[t.id];
      return rec == null || rec.playCount == 0;
    }).toList();

    final rng = Random();
    unplayed.shuffle(rng);

    final result = unplayed.take(count).toList();

    // Pad if library has fewer than count unplayed tracks
    if (result.length < count) {
      final remaining = libraryTracks
          .where((t) => !result.contains(t))
          .toList()
        ..shuffle(rng);
      result.addAll(remaining.take(count - result.length));
    }

    result.shuffle(rng);
    return result;
  }

  // ---------------------------------------------------------------------------
  // Daily Drive (podcast + music interleave)
  // ---------------------------------------------------------------------------

  /// Builds a Daily Drive queue interleaving podcast episodes and music:
  ///
  /// 1. Most recent episode of Up First
  /// 2. 5 frequently played songs (highest playCount)
  /// 3. Most recent episode of Marketplace
  /// 4. 5 recently listened songs (most recent lastPlayedAt)
  /// 5. 1 unlistened podcast episode from any other subscribed feed
  /// 6. 20 undiscovered (unplayed) songs, shuffled randomly
  Future<List<JellyfinTrack>> getDailyDrive({
    required List<JellyfinTrack> libraryTracks,
    required PodcastService podcastService,
  }) async {
    final result = <JellyfinTrack>[];

    // Load playback records for music selection.
    final allRecords = await db.getAllPlaybackRecords();
    final recordMap = <String, PlaybackRecord>{
      for (final r in allRecords) r.jellyfinId: r,
    };

    // Load subscribed feeds once.
    List<PodcastFeed> feeds = [];
    try {
      feeds = await podcastService.getSubscribedFeeds();
    } catch (e) {
      print('[PlaylistService] getDailyDrive: Failed to load feeds: $e');
    }

    // ── 1. Most recent episode of Up First ──────────────────────────────
    try {
      final upFirstFeed = feeds.cast<PodcastFeed?>().firstWhere(
        (f) => f!.id == 'up_first',
        orElse: () => null,
      );
      if (upFirstFeed != null) {
        final episodes = await podcastService.fetchEpisodes(upFirstFeed);
        if (episodes.isNotEmpty) {
          episodes.sort((a, b) => b.pubDate.compareTo(a.pubDate));
          result.add(episodes.first.toJellyfinTrack());
        }
      }
    } catch (e) {
      print('[PlaylistService] getDailyDrive: Up First failed: $e');
    }

    // ── 2. 5 frequently played songs (highest playCount) ────────────────
    final playedTracks = libraryTracks.where((t) {
      final rec = recordMap[t.id];
      return rec != null && rec.playCount > 0;
    }).toList();
    playedTracks.sort((a, b) {
      final countA = recordMap[a.id]?.playCount ?? 0;
      final countB = recordMap[b.id]?.playCount ?? 0;
      return countB.compareTo(countA);
    });
    result.addAll(playedTracks.take(5));

    // ── 3. Most recent episode of Marketplace ───────────────────────────
    try {
      final marketplaceFeed = feeds.cast<PodcastFeed?>().firstWhere(
        (f) => f!.id == 'marketplace',
        orElse: () => null,
      );
      if (marketplaceFeed != null) {
        final episodes = await podcastService.fetchEpisodes(marketplaceFeed);
        if (episodes.isNotEmpty) {
          episodes.sort((a, b) => b.pubDate.compareTo(a.pubDate));
          result.add(episodes.first.toJellyfinTrack());
        }
      }
    } catch (e) {
      print('[PlaylistService] getDailyDrive: Marketplace failed: $e');
    }

    // ── 4. 5 recently listened songs (most recent lastPlayedAt) ─────────
    final recentlyPlayed = libraryTracks.where((t) {
      final rec = recordMap[t.id];
      return rec != null && rec.lastPlayedAt != null;
    }).toList();
    recentlyPlayed.sort((a, b) {
      final dateA = recordMap[a.id]!.lastPlayedAt!;
      final dateB = recordMap[b.id]!.lastPlayedAt!;
      return dateB.compareTo(dateA);
    });
    // Avoid duplicates with the frequently-played segment.
    final usedIds = result.map((t) => t.id).toSet();
    final recentUnique = recentlyPlayed.where((t) => !usedIds.contains(t.id));
    result.addAll(recentUnique.take(5));

    // Get unplayed discovery tracks beforehand
    final rng = Random();
    final unplayed = libraryTracks.where((t) {
      final rec = recordMap[t.id];
      return rec == null || rec.playCount == 0;
    }).toList();
    unplayed.shuffle(rng);

    var discoveryIndex = 0;

    // ── 5. 2 unheard non-news podcast episodes of different genres with 5 songs in between ──────
    try {
      final nonNewsFeeds = feeds.where(
        (f) => f.id != 'up_first' && f.id != 'marketplace' && f.category.toLowerCase() != 'news',
      ).toList();
      if (nonNewsFeeds.isNotEmpty) {
        final listenedGuids = await podcastService.getListenedEpisodes();
        
        final feedEpisodesMap = <PodcastFeed, List<PodcastEpisode>>{};
        await Future.wait(
          nonNewsFeeds.map((feed) async {
            try {
              final eps = await podcastService.fetchEpisodes(feed);
              final unheardEps = eps.where((ep) => !listenedGuids.contains(ep.guid)).toList();
              if (unheardEps.isNotEmpty) {
                unheardEps.sort((a, b) => b.pubDate.compareTo(a.pubDate));
                feedEpisodesMap[feed] = unheardEps;
              }
            } catch (_) {}
          }),
        );
        
        if (feedEpisodesMap.isNotEmpty) {
          final sortedFeeds = feedEpisodesMap.keys.toList()
            ..sort((a, b) {
              final dateA = feedEpisodesMap[a]!.first.pubDate;
              final dateB = feedEpisodesMap[b]!.first.pubDate;
              return dateB.compareTo(dateA);
            });
          
          final firstFeed = sortedFeeds.first;
          final firstEp = feedEpisodesMap[firstFeed]!.first;
          result.add(firstEp.toJellyfinTrack());
          
          // ── 6. 5 songs between the 2 podcasts ──────
          final first5Songs = unplayed.skip(discoveryIndex).take(5).toList();
          result.addAll(first5Songs);
          discoveryIndex += first5Songs.length;
          
          // ── 7. Second unheard non-news podcast episode of different genre ──
          final firstGenre = firstFeed.category;
          final differentGenreFeed = sortedFeeds.cast<PodcastFeed?>().firstWhere(
            (f) => f!.category != firstGenre,
            orElse: () => null,
          );
          
          if (differentGenreFeed != null) {
            final secondEp = feedEpisodesMap[differentGenreFeed]!.first;
            result.add(secondEp.toJellyfinTrack());
          } else if (sortedFeeds.length > 1) {
            final secondFeed = sortedFeeds.firstWhere((f) => f != firstFeed);
            final secondEp = feedEpisodesMap[secondFeed]!.first;
            result.add(secondEp.toJellyfinTrack());
          }
        }
      }
    } catch (e) {
      print('[PlaylistService] getDailyDrive: Non-news podcasts failed: $e');
    }

    // ── 8. 20 undiscovered (unplayed) songs, shuffled randomly ──────────
    final remaining20Songs = unplayed.skip(discoveryIndex).take(20).toList();
    result.addAll(remaining20Songs);

    return result;
  }

  // ---------------------------------------------------------------------------
  // Server playlist creation
  // ---------------------------------------------------------------------------

  /// Creates a new playlist on the server and saves it locally.
  ///
  /// Returns the new playlist's Jellyfin ID, or `null` on failure.
  Future<String?> createPlaylistOnServer(
    String name,
    List<String> trackIds,
  ) async {
    final newId = await jellyfinService.createPlaylist(name, trackIds);
    if (newId == null) return null;

    final existing = await db.getLocalPlaylist(newId);
    await db.upsertLocalPlaylist(LocalPlaylistsCompanion(
      id: existing != null ? Value(existing.id) : const Value.absent(),
      jellyfinId: Value(newId),
      name: Value(name),
      trackIdsJson: Value(jsonEncode(trackIds)),
      lastSyncedAt: Value(DateTime.now()),
    ));

    return newId;
  }

  /// Adds a track to a playlist on the server and updates local database cache.
  Future<bool> addTrackToPlaylist(String playlistId, String trackId) async {
    final success = await jellyfinService.addTrackToPlaylist(playlistId, trackId);
    if (!success) return false;

    // Update local database cache
    final existing = await db.getLocalPlaylist(playlistId);
    if (existing != null) {
      List<dynamic> ids = [];
      try {
        ids = jsonDecode(existing.trackIdsJson);
      } catch (_) {}
      if (!ids.contains(trackId)) {
        ids.add(trackId);
        await db.upsertLocalPlaylist(LocalPlaylistsCompanion(
          id: Value(existing.id),
          jellyfinId: Value(existing.jellyfinId),
          name: Value(existing.name),
          trackIdsJson: Value(jsonEncode(ids)),
          lastSyncedAt: Value(DateTime.now()),
        ));
      }
    }
    return true;
  }

  /// Deletes a playlist from the server and local database.
  Future<bool> deletePlaylist(String playlistId) async {
    final success = await jellyfinService.deletePlaylist(playlistId);
    if (success) {
      await db.deleteLocalPlaylist(playlistId);
    }
    return success;
  }

  /// Uploads custom album art for a playlist, updating the cache.
  Future<bool> uploadPlaylistImage(String playlistId, List<int> imageBytes, String mimeType) async {
    return jellyfinService.uploadItemImage(playlistId, imageBytes, mimeType);
  }

  // ---------------------------------------------------------------------------
  // Playback recording
  // ---------------------------------------------------------------------------

  /// Records a play event for [jellyfinId], incrementing playCount.
  Future<void> recordPlay(String jellyfinId) async {
    await db.incrementPlayCount(jellyfinId);
  }

  /// Records a skip event for [jellyfinId], incrementing skipCount.
  Future<void> recordSkip(String jellyfinId) async {
    await db.incrementSkipCount(jellyfinId);
  }
}
