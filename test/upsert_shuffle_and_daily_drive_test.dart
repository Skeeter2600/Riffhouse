import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffhouse/audio/android_auto_handler.dart';
import 'package:riffhouse/audio/queue_order.dart';
import 'package:riffhouse/database/app_database.dart';
import 'package:riffhouse/models/daily_mix_config.dart';
import 'package:riffhouse/models/jellyfin_models.dart';
import 'package:riffhouse/providers/library_provider.dart';
import 'package:riffhouse/services/jellyfin_service.dart';
import 'package:riffhouse/services/playlist_service.dart';
import 'package:riffhouse/services/podcast_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

JellyfinTrack _track(String id, {String? name}) => JellyfinTrack(
      id: id,
      name: name ?? 'Track $id',
      artists: ['Artist $id'],
      albumArtist: 'Artist $id',
      albumId: 'album',
      albumName: 'Album',
      genres: const ['Rock'],
      durationMs: 1000,
      serverId: 'server',
    );

List<String> _ids(List<JellyfinTrack> tracks) => tracks.map((t) => t.id).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Upserts keyed on jellyfinId', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('bulkInsertLocalTracks updates an existing track instead of failing', () async {
      await db.bulkInsertLocalTracks([
        jellyfinTrackToCompanion(_track('a')),
        jellyfinTrackToCompanion(_track('b')),
      ]);
      await db.bulkInsertLocalTracks([
        jellyfinTrackToCompanion(_track('a', name: 'Renamed')),
        jellyfinTrackToCompanion(_track('c')),
      ]);

      final all = await db.getAllLocalTracks();
      expect(all.map((t) => t.jellyfinId).toSet(), {'a', 'b', 'c'});
      expect((await db.getLocalTrack('a'))!.name, 'Renamed');
    });

    test('upsertLocalTrack updates an existing track instead of failing', () async {
      await db.upsertLocalTrack(jellyfinTrackToCompanion(_track('a')));
      await db.upsertLocalTrack(jellyfinTrackToCompanion(_track('a', name: 'Renamed')));

      final all = await db.getAllLocalTracks();
      expect(all, hasLength(1));
      expect(all.single.name, 'Renamed');
    });

    test('cached track, playback record and playlist upserts tolerate repeats', () async {
      for (final path in ['/one', '/two']) {
        await db.upsertCachedTrack(CachedTracksCompanion(
          jellyfinId: const Value('a'),
          localPath: Value(path),
          sizeBytes: const Value(1),
          cachedAt: Value(DateTime(2026)),
        ));
      }
      expect((await db.getAllCachedTracks()).single.localPath, '/two');

      for (final count in [1, 2]) {
        await db.upsertPlaybackRecord(PlaybackRecordsCompanion(
          jellyfinId: const Value('a'),
          playCount: Value(count),
          lastPlayedAt: Value(DateTime(2026)),
        ));
      }
      expect((await db.getAllPlaybackRecords()).single.playCount, 2);

      for (final name in ['First', 'Second']) {
        await db.upsertLocalPlaylist(LocalPlaylistsCompanion(
          jellyfinId: const Value('p'),
          name: Value(name),
          trackIdsJson: const Value('[]'),
          lastSyncedAt: Value(DateTime(2026)),
        ));
      }
      expect((await db.getAllLocalPlaylists()).single.name, 'Second');
    });
  });

  group('Queue order helpers', () {
    final source = [for (var i = 0; i < 10; i++) _track('s$i')];
    final tail = [_track('t0'), _track('t1')];

    test('shuffledForPlay keeps every track and honours the start track', () {
      final shuffled = shuffledForPlay(source, startIndex: 4, random: Random(1));
      expect(shuffled.first.id, 's4');
      expect(_ids(shuffled).toSet(), _ids(source).toSet());
      expect(shuffled, hasLength(source.length));
    });

    test('shuffleUpcoming leaves played tracks, the current track and the tail alone', () {
      final queue = [...source, ...tail];
      final shuffled = shuffleUpcoming(queue, 3, source.length, random: Random(1));

      expect(_ids(shuffled.sublist(0, 4)), _ids(queue.sublist(0, 4)));
      expect(_ids(shuffled.sublist(10)), ['t0', 't1']);
      expect(_ids(shuffled.sublist(4, 10)).toSet(), _ids(queue.sublist(4, 10)).toSet());
      expect(_ids(shuffled.sublist(4, 10)), isNot(_ids(queue.sublist(4, 10))));
    });

    test('shuffleUpcoming is a no-op once playback is in the smart-continue tail', () {
      final queue = [...source, ...tail];
      expect(_ids(shuffleUpcoming(queue, 10, source.length)), _ids(queue));
    });

    test('restoreSourceOrder returns the original order and follows the current track', () {
      final shuffledSource = shuffledForPlay(source, random: Random(2));
      final queue = [...shuffledSource, ...tail];
      final current = queue[5];

      final restored = restoreSourceOrder(queue, 5, source, source.length);

      expect(_ids(restored.queue), _ids([...source, ...tail]));
      expect(restored.queue[restored.currentIndex].id, current.id);
    });

    test('restoreSourceOrder leaves the queue alone when playing a tail track', () {
      final queue = [...shuffledForPlay(source, random: Random(3)), ...tail];
      final restored = restoreSourceOrder(queue, 11, source, source.length);
      expect(_ids(restored.queue), _ids(queue));
      expect(restored.currentIndex, 11);
    });
  });

  group('Android Auto browse tree', () {
    AndroidAutoHandler buildHandler() => AndroidAutoHandler(
          service: JellyfinService(
              serverUrl: 'http://server', accessToken: 'token'),
          getCachedArtPath: (_) => null,
          requestArtDownload: (_, __) {},
          toContentUri: (path) => path,
        );

    test('playlist tracks can be loaded after a sync that passed a const map', () {
      final handler = buildHandler();
      handler.updateLibrary(const [], const [], const [], const {});

      handler.updateContainer('${kPrefixPlaylist}p1', [_track('a'), _track('b')]);

      final children = handler.getChildren('${kPrefixPlaylist}p1', null);
      expect(children.map((c) => c.id), ['a', 'b']);
      expect(children.every((c) => c.playable == true), isTrue);
    });

    test('a library sync keeps containers that were already loaded', () {
      final handler = buildHandler();
      handler.updateContainer('${kPrefixPlaylist}p1', [_track('a')]);
      handler.updateLibrary(const [], const [], const [], const {});
      expect(handler.hasContainer('${kPrefixPlaylist}p1'), isTrue);
    });

    test('long playlists are capped for browsing but kept whole for playback', () {
      final handler = buildHandler();
      final tracks = [for (var i = 0; i < kMaxBrowseTracks + 50; i++) _track('t$i')];
      handler.updateContainer('${kPrefixPlaylist}big', tracks);

      expect(handler.getChildren('${kPrefixPlaylist}big', null), hasLength(kMaxBrowseTracks));
      expect(handler.getTracksForContainer('${kPrefixPlaylist}big'), hasLength(tracks.length));
    });

    test('home lists the same four mixes as the app, each with a cache key', () {
      final home = buildHandler().getChildren(kRootHome, null);
      expect(home.take(4).map((m) => m.title),
          ['Daily Mix', 'Daily Drive', 'Heavy Rotation', 'Undiscovered']);
      expect(home.take(4).every((m) => kSmartMixes.containsKey(m.id)), isTrue);
    });
  });

  group('Daily Drive generation', () {
    late AppDatabase db;
    late PlaylistService playlistService;
    final library = [for (var i = 0; i < 40; i++) _track('lib$i')];

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      playlistService = PlaylistService(
        db,
        JellyfinService(serverUrl: 'http://localhost', accessToken: 'token'),
      );
    });
    tearDown(() async => db.close());

    test('a playlist slot that cannot load is left empty and reported, not padded', () async {
      var incomplete = false;
      final result = await playlistService.generateCustomDailyMix(
        config: DailyMixConfig(slots: [
          DailyMixSlotConfig(
            slotType: DailyMixSlotType.music,
            musicSourceType: MusicSourceType.playlist,
            selectedPlaylistIds: const ['missing'],
            fixedCount: 5,
          ),
          DailyMixSlotConfig(
            slotType: DailyMixSlotType.music,
            musicSourceType: MusicSourceType.undiscovered,
            fixedCount: 3,
          ),
        ]),
        libraryTracks: library,
        podcastService: PodcastService(),
        onIncomplete: () => incomplete = true,
      );

      // Only the open-ended slot contributes; the playlist slot is not filled
      // with unrelated library tracks.
      expect(result, hasLength(3));
      expect(incomplete, isTrue);
    });

    test('open-ended slots are still filled and do not report incompleteness', () async {
      var incomplete = false;
      final result = await playlistService.generateCustomDailyMix(
        config: DailyMixConfig(slots: [
          DailyMixSlotConfig(
            slotType: DailyMixSlotType.music,
            musicSourceType: MusicSourceType.frequentlyPlayed,
            fixedCount: 4,
          ),
          DailyMixSlotConfig(
            slotType: DailyMixSlotType.music,
            musicSourceType: MusicSourceType.undiscovered,
            fixedCount: 6,
          ),
        ]),
        libraryTracks: library,
        podcastService: PodcastService(),
        onIncomplete: () => incomplete = true,
      );

      expect(result, hasLength(10));
      expect(_ids(result).toSet(), hasLength(10));
      expect(incomplete, isFalse);
    });
  });
}
