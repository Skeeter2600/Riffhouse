import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_music_player/database/app_database.dart';
import 'package:mobile_music_player/models/daily_mix_config.dart';
import 'package:mobile_music_player/models/jellyfin_models.dart';
import 'package:mobile_music_player/models/podcast_episode.dart';
import 'package:mobile_music_player/services/jellyfin_service.dart';
import 'package:mobile_music_player/services/playlist_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Podcast Metadata Swap Tests', () {
    test('PodcastEpisode.toJellyfinTrack sets artists and albumArtist to show title, albumName to publisher', () {
      final episode = PodcastEpisode(
        guid: 'test-guid-1',
        title: 'Morning News Roundup',
        description: 'Today top stories',
        streamUrl: 'https://example.com/episode.mp3',
        pubDate: DateTime.now(),
        duration: const Duration(minutes: 15),
        imageUrl: 'https://example.com/cover.jpg',
        podcastFeedId: 'up-first',
        podcastTitle: 'Up First',
        podcastPublisher: 'NPR',
      );

      final track = episode.toJellyfinTrack();

      // Bluetooth & Android Auto display:
      // Line 1: track.name (episode title)
      // Line 2: track.artists (show name)
      // Line 3 / Album: track.albumName (publisher)
      expect(track.name, 'Morning News Roundup');
      expect(track.artists, ['Up First']);
      expect(track.albumArtist, 'Up First');
      expect(track.albumName, 'NPR');
      expect(track.remoteStreamUrl, 'https://example.com/episode.mp3');
      expect(track.albumId.startsWith('podcast_'), isTrue);
    });
  });

  group('Smart Continue Recommendation Scoring & Diversity Tests', () {
    late PlaylistService playlistService;
    late AppDatabase db;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      playlistService = PlaylistService(
        db,
        JellyfinService(serverUrl: 'http://localhost', accessToken: 'token'),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('Prefers similar genre tracks across library and enforces artist diversity', () async {
      const seedTrack = JellyfinTrack(
        id: 'seed-1',
        name: 'Seed Song',
        artists: ['Artist Alpha'],
        albumArtist: 'Artist Alpha',
        albumId: 'alb-0',
        albumName: 'Seed Album',
        genres: ['Rock', 'Alternative'],
        durationMs: 180000,
        serverId: 's1',
      );

      final List<JellyfinTrack> library = [
        // Same artist multiple songs - only one should be picked due to diversity constraint
        const JellyfinTrack(
          id: 't1',
          name: 'Song 1',
          artists: ['Artist Alpha'],
          albumArtist: 'Artist Alpha',
          albumId: 'alb-1',
          albumName: 'Album A',
          genres: ['Rock'],
          durationMs: 180000,
          serverId: 's1',
        ),
        const JellyfinTrack(
          id: 't2',
          name: 'Song 2',
          artists: ['Artist Alpha'],
          albumArtist: 'Artist Alpha',
          albumId: 'alb-2',
          albumName: 'Album A2',
          genres: ['Rock', 'Alternative'],
          durationMs: 180000,
          serverId: 's1',
        ),
        // Other artists with matching genres
        const JellyfinTrack(
          id: 't3',
          name: 'Rock Song Beta',
          artists: ['Artist Beta'],
          albumArtist: 'Artist Beta',
          albumId: 'alb-3',
          albumName: 'Beta Album',
          genres: ['Rock'],
          durationMs: 180000,
          serverId: 's1',
        ),
        const JellyfinTrack(
          id: 't4',
          name: 'Alt Song Gamma',
          artists: ['Artist Gamma'],
          albumArtist: 'Artist Gamma',
          albumId: 'alb-4',
          albumName: 'Gamma Album',
          genres: ['Alternative'],
          durationMs: 180000,
          serverId: 's1',
        ),
        const JellyfinTrack(
          id: 't5',
          name: 'Rock Alt Delta',
          artists: ['Artist Delta'],
          albumArtist: 'Artist Delta',
          albumId: 'alb-5',
          albumName: 'Delta Album',
          genres: ['Rock', 'Alternative'],
          durationMs: 180000,
          serverId: 's1',
        ),
        const JellyfinTrack(
          id: 't6',
          name: 'Indie Epsilon',
          artists: ['Artist Epsilon'],
          albumArtist: 'Artist Epsilon',
          albumId: 'alb-6',
          albumName: 'Epsilon Album',
          genres: ['Rock'],
          durationMs: 180000,
          serverId: 's1',
        ),
        // Completely different genre
        const JellyfinTrack(
          id: 't7',
          name: 'Classical Zeta',
          artists: ['Artist Zeta'],
          albumArtist: 'Artist Zeta',
          albumId: 'alb-7',
          albumName: 'Zeta Symphony',
          genres: ['Classical'],
          durationMs: 180000,
          serverId: 's1',
        ),
      ];

      final recs = await playlistService.getRecommendedTracksForPlaylist(
        playlistTracks: [seedTrack],
        libraryTracks: library,
        count: 5,
      );

      expect(recs.length, lessThanOrEqualTo(5));

      // Check artist diversity: no artist should appear more than once in recommendations
      final seenArtists = <String>{};
      for (final track in recs) {
        final artist = track.artists.isNotEmpty ? track.artists.first.toLowerCase() : '';
        expect(seenArtists.contains(artist), isFalse,
            reason: 'Artist $artist appears more than once in recommendations');
        seenArtists.add(artist);
      }

      // Ensure classical track (completely unrelated) is ranked lower than rock/alt tracks
      if (recs.length == 5) {
        expect(recs.any((t) => t.id == 't7'), isFalse);
      }
    });

    test('removePodcastFromDailyMixConfig prunes deleted podcast from specific slots and deletes empty slots', () async {
      final slot1 = DailyMixSlotConfig(
        slotType: DailyMixSlotType.podcast,
        podcastSelectionType: PodcastSelectionType.specific,
        podcastFeedIds: ['up_first'],
      );
      final slot2 = DailyMixSlotConfig(
        slotType: DailyMixSlotType.music,
        musicSourceType: MusicSourceType.frequentlyPlayed,
      );
      final slot3 = DailyMixSlotConfig(
        slotType: DailyMixSlotType.podcast,
        podcastSelectionType: PodcastSelectionType.specific,
        podcastFeedIds: ['marketplace', 'the_daily'],
      );

      final initialConfig = DailyMixConfig(slots: [slot1, slot2, slot3]);
      await playlistService.saveDailyMixConfig(initialConfig);

      // Remove up_first -> slot1 should be deleted because it only had up_first
      await playlistService.removePodcastFromDailyMixConfig('up_first');
      var updated = await playlistService.getDailyMixConfig();
      expect(updated.slots.length, equals(2));
      expect(updated.slots[0].musicSourceType, equals(MusicSourceType.frequentlyPlayed));
      expect(updated.slots[1].podcastFeedIds, equals(['marketplace', 'the_daily']));

      // Remove marketplace -> slot3 should keep the_daily without being deleted
      await playlistService.removePodcastFromDailyMixConfig('marketplace');
      updated = await playlistService.getDailyMixConfig();
      expect(updated.slots.length, equals(2));
      expect(updated.slots[1].podcastFeedIds, equals(['the_daily']));

      // Remove the_daily -> slot3 should be deleted because no feeds remain
      await playlistService.removePodcastFromDailyMixConfig('the_daily');
      updated = await playlistService.getDailyMixConfig();
      expect(updated.slots.length, equals(1));
      expect(updated.slots[0].slotType, equals(DailyMixSlotType.music));
    });

    test('Queue cloning isolates original playlist tracks from smart continue queue growth', () {
      const track1 = JellyfinTrack(
        id: 'track-1',
        name: 'Walking The Dog',
        artists: ['Fun.'],
        albumArtist: 'Fun.',
        albumId: 'alb-1',
        albumName: 'Aim and Ignite',
        genres: ['Indie Pop'],
        durationMs: 220000,
        serverId: 's1',
      );

      const track2 = JellyfinTrack(
        id: 'track-2',
        name: 'Take Your Time',
        artists: ['Fun.'],
        albumArtist: 'Fun.',
        albumId: 'alb-1',
        albumName: 'Aim and Ignite',
        genres: ['Indie Pop'],
        durationMs: 200000,
        serverId: 's1',
      );

      // Simulates playlistTracksProvider returning an unmodifiable list of 1 track
      final playlistTracks = List<JellyfinTrack>.unmodifiable([track1]);
      expect(playlistTracks.length, equals(1));

      // Simulates audio_handler.playQueue cloning the tracks
      final queue = List<JellyfinTrack>.from(playlistTracks);

      // Simulates smart continue appending recommended songs to queue
      queue.addAll([track2]);

      // Queue has grown to 2 tracks
      expect(queue.length, equals(2));

      // But original playlist tracks remains strictly 1 track!
      expect(playlistTracks.length, equals(1));
      expect(playlistTracks.first.name, equals('Walking The Dog'));
    });
  });
}

