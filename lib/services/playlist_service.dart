import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../models/jellyfin_models.dart';
import 'jellyfin_service.dart';

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
