import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/app_database.dart';
import '../models/daily_mix_config.dart';
import '../models/jellyfin_models.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_feed.dart';
import 'jellyfin_service.dart';
import 'podcast_service.dart';

/// Manages playlist synchronisation and smart mix generation using Drift.
class PlaylistService {
  final AppDatabase db;
  JellyfinService jellyfinService;

  static const _dailyMixConfigKey = 'daily_mix_config_v1';
  static const _genreStatsKey = 'genre_playback_stats';
  static const _playTimestampsKey = 'track_play_timestamps_v1';

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
  // Custom Daily Mix / Daily Drive
  // ---------------------------------------------------------------------------

  Future<DailyMixConfig> getDailyMixConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_dailyMixConfigKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        return DailyMixConfig.fromJson(decoded);
      }
    } catch (_) {
      // Ignore error
    }
    return DailyMixConfig.defaultConfig();
  }

  Future<void> saveDailyMixConfig(DailyMixConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyMixConfigKey, jsonEncode(config.toJson()));
  }

  Future<void> resetDailyMixConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dailyMixConfigKey);
  }

  /// Removes [feedId] from any specific podcast slots in DailyMixConfig.
  /// If a slot has no remaining podcast feeds, that slot is deleted.
  Future<void> removePodcastFromDailyMixConfig(String feedId) async {
    final currentConfig = await getDailyMixConfig();
    final updatedSlots = <DailyMixSlotConfig>[];
    bool changed = false;

    for (final slot in currentConfig.slots) {
      if (slot.slotType == DailyMixSlotType.podcast &&
          slot.podcastSelectionType == PodcastSelectionType.specific) {
        if (slot.podcastFeedIds.contains(feedId)) {
          changed = true;
          final remainingFeeds = slot.podcastFeedIds.where((id) => id != feedId).toList();
          if (remainingFeeds.isNotEmpty) {
            // Keep slot with remaining feeds
            updatedSlots.add(slot.copyWith(podcastFeedIds: remainingFeeds));
          } else {
            // Drop this slot entirely because all of its feeds were removed
            continue;
          }
        } else {
          updatedSlots.add(slot);
        }
      } else {
        updatedSlots.add(slot);
      }
    }

    if (changed) {
      final newConfig = currentConfig.copyWith(slots: updatedSlots);
      await saveDailyMixConfig(newConfig);
    }
  }

  /// Generates the Daily Drive / Mix based on the user's custom configuration.
  Future<List<JellyfinTrack>> getDailyDrive({
    required List<JellyfinTrack> libraryTracks,
    required PodcastService podcastService,
    DailyMixConfig? customConfig,
  }) async {
    final config = customConfig ?? await getDailyMixConfig();
    return generateCustomDailyMix(
      config: config,
      libraryTracks: libraryTracks,
      podcastService: podcastService,
    );
  }

  /// Evaluates each slot in [config] and builds a personalized queue.
  Future<List<JellyfinTrack>> generateCustomDailyMix({
    required DailyMixConfig config,
    required List<JellyfinTrack> libraryTracks,
    required PodcastService podcastService,
  }) async {
    final result = <JellyfinTrack>[];
    final usedTrackIds = <String>{};
    final usedEpisodeGuids = <String>{};
    final rng = Random();

    // Load playback records for music selections
    final allRecords = await db.getAllPlaybackRecords();
    final recordMap = <String, PlaybackRecord>{
      for (final r in allRecords) r.jellyfinId: r,
    };

    // Load subscribed feeds once
    List<PodcastFeed> subscribedFeeds = [];
    try {
      subscribedFeeds = await podcastService.getSubscribedFeeds();
    } catch (_) {
      // Ignore error
    }

    Set<String> listenedGuids = {};
    try {
      listenedGuids = await podcastService.getListenedEpisodes();
    } catch (_) {}

    // Cache of fetched episodes by feed to avoid duplicate network calls
    final feedEpisodesCache = <String, List<PodcastEpisode>>{};

    Future<List<PodcastEpisode>> getEpisodesForFeed(PodcastFeed feed) async {
      if (feedEpisodesCache.containsKey(feed.id)) {
        return feedEpisodesCache[feed.id]!;
      }
      try {
        final eps = await podcastService.fetchEpisodes(feed);
        feedEpisodesCache[feed.id] = eps;
        return eps;
      } catch (_) {
        return [];
      }
    }

    for (final slot in config.slots) {
      if (slot.slotType == DailyMixSlotType.podcast) {
        // --- Process Podcast Slot ---
        List<PodcastFeed> candidateFeeds = [];
        if (slot.podcastSelectionType == PodcastSelectionType.specific) {
          if (slot.podcastFeedIds.isNotEmpty) {
            candidateFeeds = subscribedFeeds
                .where((f) => slot.podcastFeedIds.contains(f.id))
                .toList();
          }
        } else if (slot.podcastSelectionType == PodcastSelectionType.news) {
          candidateFeeds = subscribedFeeds
              .where((f) =>
                  f.category.toLowerCase() == 'news' ||
                  f.id == 'up_first' ||
                  f.id == 'marketplace')
              .toList();
        } else if (slot.podcastSelectionType == PodcastSelectionType.nonNews) {
          candidateFeeds = subscribedFeeds
              .where((f) =>
                  f.category.toLowerCase() != 'news' &&
                  f.id != 'up_first' &&
                  f.id != 'marketplace')
              .toList();
        } else {
          candidateFeeds = List.from(subscribedFeeds);
        }

        if (candidateFeeds.isEmpty && subscribedFeeds.isNotEmpty) {
          candidateFeeds = List.from(subscribedFeeds);
        }

        if (candidateFeeds.isNotEmpty) {
          // Shuffle candidate feeds so if multiple were selected, one is picked randomly
          final shuffledFeeds = List<PodcastFeed>.from(candidateFeeds)..shuffle(rng);
          int episodesAdded = 0;

          for (final feed in shuffledFeeds) {
            if (episodesAdded >= slot.podcastCount) break;

            final episodes = await getEpisodesForFeed(feed);
            if (episodes.isEmpty) continue;

            final sortedEps = List<PodcastEpisode>.from(episodes)
              ..sort((a, b) => b.pubDate.compareTo(a.pubDate));

            for (final ep in sortedEps) {
              if (episodesAdded >= slot.podcastCount) break;
              if (usedEpisodeGuids.contains(ep.guid)) continue;

              final isListened = listenedGuids.contains(ep.guid);
              if (slot.episodeSelection == EpisodeSelectionMode.latestUnheard && isListened) {
                continue;
              }

              usedEpisodeGuids.add(ep.guid);
              result.add(ep.toJellyfinTrack());
              episodesAdded++;
            }
          }
        }
      } else {
        // --- Process Music Slot ---
        final count = slot.isCountRange
            ? (slot.minCount + rng.nextInt(max(1, slot.maxCount - slot.minCount + 1)))
            : slot.fixedCount;

        if (count <= 0) continue;

        List<JellyfinTrack> candidatePool = [];

        switch (slot.musicSourceType) {
          case MusicSourceType.frequentlyPlayed:
            candidatePool = await getFrequentlyPlayedTracks(
              libraryTracks: libraryTracks,
              count: count,
            );
            break;

          case MusicSourceType.recentlyPlayed:
            final recent = libraryTracks.where((t) {
              final rec = recordMap[t.id];
              return rec != null && rec.playCount > 0;
            }).toList();
            recent.sort((a, b) {
              final dateA = recordMap[a.id]?.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final dateB = recordMap[b.id]?.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return dateB.compareTo(dateA);
            });
            candidatePool = recent;
            break;

          case MusicSourceType.undiscovered:
            final unplayed = libraryTracks.where((t) {
              final rec = recordMap[t.id];
              return rec == null || rec.playCount == 0;
            }).toList()..shuffle(rng);
            candidatePool = unplayed;
            break;

          case MusicSourceType.smartMix:
            candidatePool = await getSmartMix(
              count: count * 2,
              libraryTracks: libraryTracks,
            );
            break;

          case MusicSourceType.genre:
            if (slot.selectedGenres.isNotEmpty) {
              candidatePool = libraryTracks.where((t) {
                return t.genres.any((g) => slot.selectedGenres.any(
                    (sg) => g.toLowerCase().contains(sg.toLowerCase())));
              }).toList()..shuffle(rng);
            } else {
              candidatePool = List.from(libraryTracks)..shuffle(rng);
            }
            break;

          case MusicSourceType.playlist:
            if (slot.selectedPlaylistIds.isNotEmpty) {
              final playlistTracks = <JellyfinTrack>[];
              for (final pid in slot.selectedPlaylistIds) {
                try {
                  final tracks = await jellyfinService.getPlaylistTracks(pid);
                  playlistTracks.addAll(tracks);
                } catch (_) {}
              }
              candidatePool = playlistTracks..shuffle(rng);
            }
            break;

          case MusicSourceType.artist:
            if (slot.selectedArtistIds.isNotEmpty) {
              candidatePool = libraryTracks.where((t) {
                return t.artists.any((a) => slot.selectedArtistIds.any(
                    (sa) => a.toLowerCase().contains(sa.toLowerCase())));
              }).toList()..shuffle(rng);
            }
            break;
        }

        // Deduplicate against tracks already added
        final available = candidatePool.where((t) => !usedTrackIds.contains(t.id)).toList();
        final picked = available.take(count).toList();

        for (final t in picked) {
          usedTrackIds.add(t.id);
          result.add(t);
        }

        // If not enough unique candidates, pad from remaining library tracks
        if (picked.length < count) {
          final remaining = libraryTracks
              .where((t) => !usedTrackIds.contains(t.id))
              .toList()..shuffle(rng);
          final needed = count - picked.length;
          for (final t in remaining.take(needed)) {
            usedTrackIds.add(t.id);
            result.add(t);
          }
        }
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Genre Listen Recording & Affinity
  // ---------------------------------------------------------------------------

  Future<void> _recordGenrePlays(List<String> genres) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_genreStatsKey);
      final Map<String, dynamic> stats = jsonStr != null ? jsonDecode(jsonStr) : {};

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      for (final genre in genres) {
        final clean = genre.trim();
        if (clean.isEmpty) continue;

        final current = stats[clean] as Map<String, dynamic>? ?? {
          'count': 0,
          'lastPlayedAt': 0,
        };
        final currentCount = (current['count'] as int?) ?? 0;
        stats[clean] = {
          'count': currentCount + 1,
          'lastPlayedAt': nowMs,
        };
      }

      await prefs.setString(_genreStatsKey, jsonEncode(stats));
    } catch (_) {
      // Ignore error
    }
  }

  /// Returns user's top listened genres sorted by play count descending.
  Future<List<String>> getTopListenedGenres({int limit = 10}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_genreStatsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> stats = jsonDecode(jsonStr);
        final entries = stats.entries.toList();
        entries.sort((a, b) {
          final countA = (a.value['count'] as int?) ?? 0;
          final countB = (b.value['count'] as int?) ?? 0;
          return countB.compareTo(countA);
        });
        return entries.map((e) => e.key).take(limit).toList();
      }
    } catch (_) {
      // Ignore error
    }
    return [];
  }

  /// Returns user's recently listened genres.
  Future<List<String>> getRecentlyListenedGenres({int limit = 10}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_genreStatsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> stats = jsonDecode(jsonStr);
        final entries = stats.entries.toList();
        entries.sort((a, b) {
          final timeA = (a.value['lastPlayedAt'] as int?) ?? 0;
          final timeB = (b.value['lastPlayedAt'] as int?) ?? 0;
          return timeB.compareTo(timeA);
        });
        return entries.map((e) => e.key).take(limit).toList();
      }
    } catch (_) {
      // Ignore error
    }
    return [];
  }

  // ---------------------------------------------------------------------------
  // Server playlist management
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
    return success;
  }

  /// Removes a track from a playlist on the server and updates local database cache.
  Future<bool> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final success = await jellyfinService.removeTrackFromPlaylist(playlistId, trackId);
    // Update local database cache
    final existing = await db.getLocalPlaylist(playlistId);
    if (existing != null) {
      List<dynamic> ids = [];
      try {
        ids = jsonDecode(existing.trackIdsJson);
      } catch (_) {}
      ids.remove(trackId);
      await db.upsertLocalPlaylist(LocalPlaylistsCompanion(
        id: Value(existing.id),
        jellyfinId: Value(existing.jellyfinId),
        name: Value(existing.name),
        trackIdsJson: Value(jsonEncode(ids)),
        lastSyncedAt: Value(DateTime.now()),
      ));
    }
    return success;
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

  /// Records a play event for [jellyfinId], incrementing playCount and tracking genre and timestamp statistics.
  Future<void> recordPlay(String jellyfinId) async {
    await db.incrementPlayCount(jellyfinId);

    // Record timestamp for time-windowed frequency tracking
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyStr = prefs.getString(_playTimestampsKey);
      final Map<String, dynamic> history = historyStr != null ? jsonDecode(historyStr) : {};
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final List<dynamic> list = history[jellyfinId] != null ? List.from(history[jellyfinId] as List) : [];
      list.add(nowMs);

      // Keep plays from the last 90 days to avoid unbounded growth
      final cutoff90Days = DateTime.now().subtract(const Duration(days: 90)).millisecondsSinceEpoch;
      history[jellyfinId] = list.where((t) => (t as int) >= cutoff90Days).toList();
      await prefs.setString(_playTimestampsKey, jsonEncode(history));
    } catch (_) {
      // Ignore error
    }

    try {
      final local = await db.getLocalTrack(jellyfinId);
      if (local != null) {
        List<String> genres = [];
        try {
          genres = List<String>.from(jsonDecode(local.genresJson));
        } catch (_) {}
        if (genres.isNotEmpty) {
          await _recordGenrePlays(genres);
        }
      }
    } catch (_) {
      // Ignore error
    }
  }

  /// Returns map of track jellyfinId -> listen count in the given time window (default: last 3 weeks / 21 days).
  Future<Map<String, int>> getRecentPlayCounts({Duration window = const Duration(days: 21)}) async {
    final cutoff = DateTime.now().subtract(window).millisecondsSinceEpoch;
    final Map<String, int> result = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyStr = prefs.getString(_playTimestampsKey);
      if (historyStr != null && historyStr.isNotEmpty) {
        final Map<String, dynamic> history = jsonDecode(historyStr);
        for (final entry in history.entries) {
          final list = entry.value as List?;
          if (list != null) {
            final count = list.where((t) => (t as int) >= cutoff).length;
            if (count > 0) {
              result[entry.key] = count;
            }
          }
        }
      }
    } catch (_) {
      // Ignore error
    }

    // Also include database records where lastPlayedAt is within the 3-week window if not in history
    try {
      final records = await db.getAllPlaybackRecords();
      final cutoffDate = DateTime.now().subtract(window);
      for (final r in records) {
        if (!result.containsKey(r.jellyfinId) && r.playCount > 0 && r.lastPlayedAt.isAfter(cutoffDate)) {
          result[r.jellyfinId] = r.playCount;
        }
      }
    } catch (_) {}

    return result;
  }

  /// Selects frequently played tracks from the last 3 weeks.
  ///
  /// - If [count] <= 25: randomly selects [count] tracks from the top 25 most played in last 3 weeks.
  /// - If [count] > 25: selects the top [count] songs in the last 3 weeks, shuffled in order.
  Future<List<JellyfinTrack>> getFrequentlyPlayedTracks({
    required List<JellyfinTrack> libraryTracks,
    required int count,
  }) async {
    final recentCounts = await getRecentPlayCounts(window: const Duration(days: 21));
    final rng = Random();

    // Only include tracks with plays in the last 3 weeks
    final playedInLast3Weeks = libraryTracks.where((t) {
      final c = recentCounts[t.id];
      return c != null && c > 0;
    }).toList();

    // Sort descending by play count in the last 3 weeks
    playedInLast3Weeks.sort((a, b) {
      final countA = recentCounts[a.id] ?? 0;
      final countB = recentCounts[b.id] ?? 0;
      return countB.compareTo(countA);
    });

    List<JellyfinTrack> picked;
    if (count <= 25) {
      // Random selection of count from the top 25
      final top25 = playedInLast3Weeks.take(25).toList();
      top25.shuffle(rng);
      picked = top25.take(count).toList();
    } else {
      // If count > 25, take the top count songs and shuffle in order
      final topX = playedInLast3Weeks.take(count).toList();
      topX.shuffle(rng);
      picked = topX;
    }

    // If there aren't enough played tracks in the last 3 weeks, pad with other library tracks
    if (picked.length < count) {
      final usedIds = picked.map((t) => t.id).toSet();
      final remaining = libraryTracks.where((t) => !usedIds.contains(t.id)).toList()..shuffle(rng);
      picked.addAll(remaining.take(count - picked.length));
    }

    return picked;
  }

  /// Records a skip event for [jellyfinId], incrementing skipCount.
  Future<void> recordSkip(String jellyfinId) async {
    await db.incrementSkipCount(jellyfinId);
  }

  /// Returns recommended tracks for a playlist or track continuation based on its current tracks.
  /// Looks across the whole library for similar feel (primarily genre matching)
  /// and enforces artist diversity so it avoids continuing with the same artist.
  Future<List<JellyfinTrack>> getRecommendedTracksForPlaylist({
    required List<JellyfinTrack> playlistTracks,
    required List<JellyfinTrack> libraryTracks,
    Set<String> excludedTrackIds = const {},
    int count = 5,
  }) async {
    final playlistTrackIds = playlistTracks.map((t) => t.id).toSet();
    final allExcluded = {...playlistTrackIds, ...excludedTrackIds};

    final candidates = libraryTracks.where((t) => !allExcluded.contains(t.id)).toList();
    if (candidates.isEmpty) return [];

    final playlistArtists = <String>{};
    final playlistGenres = <String>{};

    // Primary seed is the most recent or active track
    final seedTrack = playlistTracks.isNotEmpty ? playlistTracks.last : null;
    final seedGenres = seedTrack?.genres.map((g) => g.toLowerCase().trim()).toSet() ?? {};

    for (final track in playlistTracks) {
      playlistArtists.addAll(track.artists.map((a) => a.toLowerCase().trim()));
      if (track.albumArtist.isNotEmpty) {
        playlistArtists.add(track.albumArtist.toLowerCase().trim());
      }
      playlistGenres.addAll(track.genres.map((g) => g.toLowerCase().trim()));
    }

    final rng = Random();

    if (playlistTracks.isEmpty) {
      final shuffled = List<JellyfinTrack>.from(candidates)..shuffle(rng);
      return shuffled.take(count).toList();
    }

    final scored = <({JellyfinTrack track, double score})>[];

    for (final track in candidates) {
      double score = 0;
      final trackGenres = track.genres.map((g) => g.toLowerCase().trim()).toSet();
      final trackArtists = track.artists.map((a) => a.toLowerCase().trim()).toSet();
      if (track.albumArtist.isNotEmpty) {
        trackArtists.add(track.albumArtist.toLowerCase().trim());
      }

      // Strongest signal for feel: genre matches against current seed track
      for (final g in trackGenres) {
        if (seedGenres.contains(g)) {
          score += 6.0;
        } else if (playlistGenres.contains(g)) {
          score += 3.0;
        }
      }

      // Very minor artist boost (max 1.0) so we don't fixate on the same artist
      for (final a in trackArtists) {
        if (playlistArtists.contains(a)) {
          score += 1.0;
          break;
        }
      }

      // Add random jitter (0.0 to 2.5) to explore the whole library with varied discoveries
      score += rng.nextDouble() * 2.5;

      scored.add((track: track, score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    // Enforce artist diversity: maximum 1 song per artist in the 5 recommendations
    final result = <JellyfinTrack>[];
    final selectedArtists = <String>{};

    for (final item in scored) {
      final primaryArtist = (item.track.artists.firstOrNull ?? item.track.albumArtist).toLowerCase().trim();
      if (primaryArtist.isNotEmpty && selectedArtists.contains(primaryArtist)) {
        continue; // Skip duplicate artist in this continuation batch
      }
      result.add(item.track);
      if (primaryArtist.isNotEmpty) {
        selectedArtists.add(primaryArtist);
      }
      if (result.length >= count) break;
    }

    // If diversity filter left us with fewer than count, fill with remaining scored tracks
    if (result.length < count) {
      final pickedIds = result.map((t) => t.id).toSet();
      for (final item in scored) {
        if (!pickedIds.contains(item.track.id)) {
          result.add(item.track);
          if (result.length >= count) break;
        }
      }
    }

    return result;
  }
}

