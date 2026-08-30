import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_music_player/models/daily_mix_config.dart';
import 'package:mobile_music_player/models/jellyfin_models.dart';

void main() {
  group('DailyMixConfig Tests', () {
    test('defaultConfig produces valid slots', () {
      final config = DailyMixConfig.defaultConfig();
      expect(config.slots.isNotEmpty, isTrue);
      expect(config.slots.length, equals(8));
      expect(config.slots.first.slotType, equals(DailyMixSlotType.podcast));
      expect(config.slots[1].slotType, equals(DailyMixSlotType.music));
      expect(config.slots[1].musicSourceType, equals(MusicSourceType.frequentlyPlayed));
    });

    test('getDisplayTitle formats known and map titles properly', () {
      final slot1 = DailyMixSlotConfig(
        slotType: DailyMixSlotType.podcast,
        podcastSelectionType: PodcastSelectionType.specific,
        podcastFeedIds: ['up_first'],
      );
      expect(slot1.getDisplayTitle(), equals('Podcast: Up First'));

      final slot2 = DailyMixSlotConfig(
        slotType: DailyMixSlotType.podcast,
        podcastSelectionType: PodcastSelectionType.specific,
        podcastFeedIds: ['custom_feed_123'],
      );
      expect(
        slot2.getDisplayTitle(feedTitleMap: {'custom_feed_123': 'Planet Money'}),
        equals('Podcast: Planet Money'),
      );
    });

    test('toJson and fromJson preserves all slot fields', () {
      final slot1 = DailyMixSlotConfig(
        slotType: DailyMixSlotType.podcast,
        podcastSelectionType: PodcastSelectionType.specific,
        podcastFeedIds: ['feed_a', 'feed_b', 'feed_c'],
        episodeSelection: EpisodeSelectionMode.latestUnheard,
        podcastCount: 2,
      );

      final slot2 = DailyMixSlotConfig(
        slotType: DailyMixSlotType.music,
        musicSourceType: MusicSourceType.genre,
        selectedGenres: ['Rock', 'Metal', 'Jazz'],
        isCountRange: true,
        minCount: 5,
        maxCount: 12,
      );

      final config = DailyMixConfig(slots: [slot1, slot2]);
      final jsonMap = config.toJson();
      final decoded = DailyMixConfig.fromJson(jsonMap);

      expect(decoded.slots.length, equals(2));

      final decodedSlot1 = decoded.slots[0];
      expect(decodedSlot1.slotType, equals(DailyMixSlotType.podcast));
      expect(decodedSlot1.podcastSelectionType, equals(PodcastSelectionType.specific));
      expect(decodedSlot1.podcastFeedIds, equals(['feed_a', 'feed_b', 'feed_c']));
      expect(decodedSlot1.episodeSelection, equals(EpisodeSelectionMode.latestUnheard));
      expect(decodedSlot1.podcastCount, equals(2));

      final decodedSlot2 = decoded.slots[1];
      expect(decodedSlot2.slotType, equals(DailyMixSlotType.music));
      expect(decodedSlot2.musicSourceType, equals(MusicSourceType.genre));
      expect(decodedSlot2.selectedGenres, equals(['Rock', 'Metal', 'Jazz']));
      expect(decodedSlot2.isCountRange, isTrue);
      expect(decodedSlot2.minCount, equals(5));
      expect(decodedSlot2.maxCount, equals(12));
    });
  });

  group('Smart Mix Midnight Persistence Tests', () {
    DateTime nextMidnight(DateTime from) {
      return DateTime(from.year, from.month, from.day + 1);
    }

    test('Mix generated at 10 AM is valid at 11:59 PM same day, invalid at 00:01 AM next day', () {
      final generatedAt = DateTime(2026, 8, 29, 10, 0);
      final midnight = nextMidnight(generatedAt);

      final sameDayLate = DateTime(2026, 8, 29, 23, 59);
      final nextDay = DateTime(2026, 8, 30, 0, 1);

      expect(sameDayLate.isBefore(midnight), isTrue);
      expect(nextDay.isBefore(midnight), isFalse);
    });

    test('JellyfinTrack serialization and deserialization works with podcast stream URLs', () {
      const original = JellyfinTrack(
        id: 'podcast_ep_123',
        name: 'Daily News Briefing',
        artists: ['NPR'],
        albumArtist: 'NPR',
        albumId: 'feed_up_first',
        albumName: 'Up First',
        genres: ['News', 'Podcast'],
        durationMs: 840000,
        serverId: '',
        imageTag: 'https://example.com/art.jpg',
        remoteStreamUrl: 'https://example.com/audio.mp3',
      );

      final map = original.toMap();
      final restored = JellyfinTrack.fromJson(map);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.artists, equals(original.artists));
      expect(restored.albumArtist, equals(original.albumArtist));
      expect(restored.albumName, equals(original.albumName));
      expect(restored.genres, equals(original.genres));
      expect(restored.durationMs, equals(original.durationMs));
      expect(restored.imageTag, equals(original.imageTag));
      expect(restored.remoteStreamUrl, equals(original.remoteStreamUrl));
    });
  });

  group('Frequently Played 3-Week Algorithm Simulation', () {
    test('X <= 25 randomly samples X from top 25', () {
      final mockPlayedInLast3Weeks = List.generate(40, (i) => 'track_$i');
      const count = 5;

      final top25 = mockPlayedInLast3Weeks.take(25).toList();
      top25.shuffle(Random(42));
      final picked = top25.take(count).toList();

      expect(picked.length, equals(5));
      for (final id in picked) {
        final index = int.parse(id.split('_')[1]);
        expect(index, lessThan(25));
      }
    });

    test('X > 25 takes top X and shuffles them', () {
      final mockPlayedInLast3Weeks = List.generate(40, (i) => 'track_$i');
      const count = 30;

      final topX = mockPlayedInLast3Weeks.take(count).toList();
      topX.shuffle(Random(42));

      expect(topX.length, equals(30));
      for (final id in topX) {
        final index = int.parse(id.split('_')[1]);
        expect(index, lessThan(30));
      }
    });
  });

  group('Listen Threshold Math Tests', () {
    Duration getListenThreshold(Duration duration) {
      if (duration <= const Duration(seconds: 30)) {
        return Duration(milliseconds: duration.inMilliseconds ~/ 2);
      } else {
        final half = Duration(milliseconds: duration.inMilliseconds ~/ 2);
        return half > const Duration(seconds: 30) ? half : const Duration(seconds: 30);
      }
    }

    test('3-minute song (180s) requires half (90s)', () {
      const duration = Duration(minutes: 3);
      final threshold = getListenThreshold(duration);
      expect(threshold, equals(const Duration(seconds: 90)));
    });

    test('40-second song requires 30s', () {
      const duration = Duration(seconds: 40);
      final threshold = getListenThreshold(duration);
      expect(threshold, equals(const Duration(seconds: 30)));
    });

    test('20-second short track requires half (10s)', () {
      const duration = Duration(seconds: 20);
      final threshold = getListenThreshold(duration);
      expect(threshold, equals(const Duration(seconds: 10)));
    });
  });
}
