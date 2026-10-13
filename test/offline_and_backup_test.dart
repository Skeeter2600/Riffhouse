import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffhouse/database/app_database.dart';
import 'package:riffhouse/services/backup_service.dart';
import 'package:riffhouse/services/cache_service.dart';
import 'package:riffhouse/services/jellyfin_service.dart';
import 'package:riffhouse/services/offline_cache_interceptor.dart';
import 'package:riffhouse/services/play_reporter.dart';
import 'package:riffhouse/utils/app_paths.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Answers requests from a script instead of the network.
class _ScriptedAdapter implements HttpClientAdapter {
  /// Returns the JSON body to answer with, or throws to simulate a failure.
  Object? Function(RequestOptions options) respond;
  int calls = 0;

  _ScriptedAdapter(this.respond);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final body = respond(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DioException _offline(RequestOptions options) => DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
    );

/// A [MusicService] whose play reports are answered by the test.
class _ReportingService extends JellyfinService {
  ReportResult next = ReportResult.sent;
  final sent = <String>[];

  _ReportingService()
      : super(serverUrl: 'http://example.invalid', accessToken: 't', userId: 'u1');

  @override
  Future<ReportResult> markPlayed(String itemId, DateTime playedAt) async {
    if (next == ReportResult.sent) sent.add(itemId);
    return next;
  }
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('riffhouse_test_');
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {
      // Windows may still hold a handle briefly; the OS cleans temp up.
    }
  });

  group('Offline library cache', () {
    late _ScriptedAdapter adapter;
    late Dio dio;

    setUp(() {
      OfflineCacheInterceptor.resetReachability();
      adapter = _ScriptedAdapter((_) => {'Items': []});
      dio = Dio(BaseOptions(baseUrl: 'http://server.test/'))
        ..httpClientAdapter = adapter
        ..interceptors.add(OfflineCacheInterceptor('user', directory: temp));
    });

    test('serves the last good answer when the server is unreachable', () async {
      adapter.respond = (_) => {
            'Items': [
              {'Id': 'a1', 'Name': 'Album'}
            ]
          };
      await dio.get('Users/user/Items', queryParameters: {'x': 1});

      adapter.respond = (o) => throw _offline(o);
      final offline =
          await dio.get('Users/user/Items', queryParameters: {'x': 1});
      expect(offline.data['Items'][0]['Id'], 'a1');
      expect(offline.extra[OfflineCacheInterceptor.servedFromCache], isTrue);
    });

    test('a different request has no cached answer', () async {
      await dio.get('Users/user/Items', queryParameters: {'x': 1});
      adapter.respond = (o) => throw _offline(o);
      expect(
        () => dio.get('Users/user/Items', queryParameters: {'x': 2}),
        throwsA(isA<DioException>()),
      );
    });

    test('requests marked live are never answered from the cache', () async {
      final live =
          Options(extra: const {OfflineCacheInterceptor.skip: true});
      await dio.get('Users/user', options: live);
      adapter.respond = (o) => throw _offline(o);
      expect(
        () => dio.get('Users/user', options: live),
        throwsA(isA<DioException>()),
      );
    });

    test('while the server is down, cached answers skip the network',
        () async {
      await dio.get('Playlists/p1/Items');
      adapter.respond = (o) => throw _offline(o);
      await dio.get('Playlists/p1/Items');
      final callsAfterFailure = adapter.calls;

      await dio.get('Playlists/p1/Items');
      expect(adapter.calls, callsAfterFailure);
    });
  });

  group('Play reporting', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('plays made while unreachable are kept and sent later, in order',
        () async {
      final service = _ReportingService()..next = ReportResult.unreachable;
      await PlayReporter.report(service, 'one', DateTime(2026, 1, 1));
      await PlayReporter.report(service, 'two', DateTime(2026, 1, 2));
      expect(await PlayReporter.pendingCount(), 2);
      expect(service.sent, isEmpty);

      service.next = ReportResult.sent;
      await PlayReporter.flush(service);
      expect(service.sent, ['one', 'two']);
      expect(await PlayReporter.pendingCount(), 0);
    });

    test('a play the server refuses for good is dropped', () async {
      final service = _ReportingService()..next = ReportResult.rejected;
      await PlayReporter.report(service, 'gone', DateTime(2026, 1, 1));
      expect(await PlayReporter.pendingCount(), 0);
    });

    test('nothing is queued when reporting is switched off', () async {
      await PlayReporter.setEnabled(false);
      final service = _ReportingService();
      await PlayReporter.report(service, 'one', DateTime(2026, 1, 1));
      expect(service.sent, isEmpty);
      expect(await PlayReporter.pendingCount(), 0);
    });
  });

  group('Backup and restore', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> seed(String id, int plays, DateTime last) =>
        db.upsertPlaybackRecord(PlaybackRecordsCompanion(
          jellyfinId: Value(id),
          playCount: Value(plays),
          skipCount: const Value(1),
          lastPlayedAt: Value(last),
        ));

    test('round trip restores history and settings into a fresh install',
        () async {
      SharedPreferences.setMockInitialValues({
        'genre_playback_stats': '{"Rock":12}',
        'playback_crossfade_enabled': true,
        'playback_position_ms': 4200,
        'listened_podcast_episodes': ['a', 'b'],
        'jellyfin_device_id': 'this-install',
        'smart_mix_persisted_cache_v2_daily': 'big',
      });
      await seed('t1', 7, DateTime(2026, 5, 1));
      await seed('t2', 3, DateTime(2026, 6, 1));
      final backup =
          await BackupService(db).exportJson(await SharedPreferences.getInstance());

      // Install-specific and regenerable settings stay out of the file.
      final settings = jsonDecode(backup)['settings'] as Map;
      expect(settings.containsKey('jellyfin_device_id'), isFalse);
      expect(settings.containsKey('smart_mix_persisted_cache_v2_daily'), isFalse);

      final fresh = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(fresh.close);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final summary = await BackupService(fresh).restoreJson(backup, prefs);

      expect(summary.playbackRecords, 2);
      expect((await fresh.getPlaybackRecord('t1'))!.playCount, 7);
      expect((await fresh.getPlaybackRecord('t2'))!.lastPlayedAt,
          DateTime(2026, 6, 1));
      expect(prefs.getString('genre_playback_stats'), '{"Rock":12}');
      expect(prefs.getBool('playback_crossfade_enabled'), isTrue);
      expect(prefs.getInt('playback_position_ms'), 4200);
      expect(prefs.getStringList('listened_podcast_episodes'), ['a', 'b']);
    });

    test('restoring never lowers existing counts and is repeatable', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await seed('t1', 5, DateTime(2026, 5, 1));
      final backup = await BackupService(db).exportJson(prefs);

      // More listening happened after the backup was taken.
      await seed('t1', 9, DateTime(2026, 7, 1));
      await BackupService(db).restoreJson(backup, prefs);
      await BackupService(db).restoreJson(backup, prefs);

      final record = (await db.getPlaybackRecord('t1'))!;
      expect(record.playCount, 9);
      expect(record.lastPlayedAt, DateTime(2026, 7, 1));
    });

    test('files that are not Riffhouse backups are refused', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = BackupService(db);
      expect(() => service.restoreJson('not json', prefs),
          throwsA(isA<BackupFormatException>()));
      expect(() => service.restoreJson('{"app":"other"}', prefs),
          throwsA(isA<BackupFormatException>()));
      expect(
        () => service.restoreJson('{"app":"riffhouse","format":99}', prefs),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });

  group('Desktop data move', () {
    test('moves the database with its side files and the audio cache',
        () async {
      final from = Directory(p.join(temp.path, 'Documents'))..createSync();
      final to = Directory(p.join(temp.path, 'AppData', 'Riffhouse'));
      File(p.join(from.path, 'riffhouse.db')).writeAsStringSync('database');
      File(p.join(from.path, 'riffhouse.db-wal')).writeAsStringSync('wal');
      Directory(p.join(from.path, 'audio_cache')).createSync();
      File(p.join(from.path, 'audio_cache', 'a.audio')).writeAsStringSync('x');
      File(p.join(from.path, 'thesis.docx')).writeAsStringSync('mine');

      expect(await moveLegacyData(from, to), isTrue);

      expect(File(p.join(to.path, 'riffhouse.db')).readAsStringSync(),
          'database');
      expect(File(p.join(to.path, 'riffhouse.db-wal')).readAsStringSync(),
          'wal');
      expect(File(p.join(to.path, 'audio_cache', 'a.audio')).existsSync(),
          isTrue);
      expect(File(p.join(from.path, 'riffhouse.db')).existsSync(), isFalse);
      expect(File(p.join(from.path, 'riffhouse.db-wal')).existsSync(), isFalse);
      // Nothing else in Documents is touched.
      expect(File(p.join(from.path, 'thesis.docx')).existsSync(), isTrue);
    });

    test('never overwrites data already in the new location', () async {
      final from = Directory(p.join(temp.path, 'Documents'))..createSync();
      final to = Directory(p.join(temp.path, 'AppData'))..createSync();
      File(p.join(from.path, 'riffhouse.db')).writeAsStringSync('old');
      File(p.join(to.path, 'riffhouse.db')).writeAsStringSync('current');

      expect(await moveLegacyData(from, to), isFalse);
      expect(File(p.join(to.path, 'riffhouse.db')).readAsStringSync(),
          'current');
      expect(File(p.join(from.path, 'riffhouse.db')).readAsStringSync(), 'old');
    });

    test('finds the application folder used before the rename', () {
      expect(
        legacySupportDirectory(
          Directory(p.join('C:', 'Users', 'a', 'AppData', 'Roaming',
              'Riffhouse', 'Riffhouse')),
          windows: true,
        ).path,
        p.join('C:', 'Users', 'a', 'AppData', 'Roaming', 'com.example',
            'mobile_music_player'),
      );
      expect(
        legacySupportDirectory(
          Directory(p.join('home', 'a', '.local', 'share',
              'com.riffhouse.Riffhouse')),
          windows: false,
        ).path,
        p.join('home', 'a', '.local', 'share',
            'com.example.mobile_music_player'),
      );
    });

    test('settings follow the renamed application folder', () async {
      final from = Directory(p.join(temp.path, 'com.example', 'old'))
        ..createSync(recursive: true);
      final to = Directory(p.join(temp.path, 'Riffhouse', 'Riffhouse'));
      File(p.join(from.path, 'shared_preferences.json'))
          .writeAsStringSync('{"flutter.subscribed_podcast_feeds":"x"}');
      Directory(p.join(from.path, 'api_cache')).createSync();
      File(p.join(from.path, 'api_cache', 'a.json')).writeAsStringSync('{}');

      expect(await copyLegacySupportData(from, to), isTrue);
      expect(
          File(p.join(to.path, 'shared_preferences.json')).readAsStringSync(),
          contains('subscribed_podcast_feeds'));
      expect(File(p.join(to.path, 'api_cache', 'a.json')).existsSync(), isTrue);
      // The old folder is kept as a fallback.
      expect(File(p.join(from.path, 'shared_preferences.json')).existsSync(),
          isTrue);
    });

    test('settings already in the new folder are never overwritten', () async {
      final from = Directory(p.join(temp.path, 'old'))..createSync();
      final to = Directory(p.join(temp.path, 'new'))..createSync();
      File(p.join(from.path, 'shared_preferences.json')).writeAsStringSync('old');
      File(p.join(to.path, 'shared_preferences.json')).writeAsStringSync('new');

      expect(await copyLegacySupportData(from, to), isFalse);
      expect(File(p.join(to.path, 'shared_preferences.json')).readAsStringSync(),
          'new');
    });

    test('does nothing when there is no legacy data', () async {
      final from = Directory(p.join(temp.path, 'Documents'))..createSync();
      final to = Directory(p.join(temp.path, 'AppData'));
      expect(await moveLegacyData(from, to), isFalse);
      expect(to.existsSync(), isFalse);
    });
  });

  group('Resumable downloads', () {
    late AppDatabase db;
    late HttpServer server;
    late List<int> content;
    late String url;
    final rangesSeen = <String?>[];

    /// When set, the server drops the connection after this many bytes.
    int? cutAfter;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      content = List<int>.generate(200000, (i) => i % 251);
      rangesSeen.clear();
      cutAfter = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      url = 'http://127.0.0.1:${server.port}/track';
      server.listen((request) async {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        rangesSeen.add(range);
        var start = 0;
        if (range != null) {
          start = int.parse(range.substring('bytes='.length, range.length - 1));
          request.response.statusCode = HttpStatus.partialContent;
        }
        final body = content.sublist(start);
        final limit = cutAfter;
        if (limit != null) {
          // Promise the whole file, send part of it and drop the connection,
          // as a lost network would.
          final socket =
              await request.response.detachSocket(writeHeaders: false);
          socket.write('HTTP/1.1 200 OK\r\n'
              'Content-Type: application/octet-stream\r\n'
              'Content-Length: ${body.length}\r\n\r\n');
          socket.add(body.sublist(0, limit));
          await socket.flush();
          socket.destroy();
          return;
        }
        request.response.contentLength = body.length;
        request.response.add(body);
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await db.close();
    });

    test('an interrupted download continues from where it stopped', () async {
      final service = CacheService(db, audioDirectory: temp);

      cutAfter = 70000;
      await expectLater(service.downloadTrack('t1', url), throwsA(anything));
      final partial = File(p.join(temp.path, 't1.audio.part'));
      expect(partial.existsSync(), isTrue);
      final have = partial.lengthSync();
      expect(have, greaterThan(0));
      expect(service.isTrackCachedSync('t1'), isFalse);

      cutAfter = null;
      await service.downloadTrack('t1', url);

      expect(rangesSeen.last, 'bytes=$have-');
      final file = File(service.getCachedPathSync('t1')!);
      expect(file.readAsBytesSync(), content);
      expect(partial.existsSync(), isFalse);
      expect((await db.getCachedTrack('t1'))!.sizeBytes, content.length);
    });

    test('a cancelled download keeps its progress', () async {
      final service = CacheService(db, audioDirectory: temp);
      final token = CancelToken();
      final download = service.downloadTrack(
        't2',
        url,
        cancelToken: token,
        onProgress: (p) {
          if (p > 0.2 && !token.isCancelled) token.cancel();
        },
      );
      await expectLater(download, throwsA(anything));
      expect(service.isTrackCachedSync('t2'), isFalse);

      await service.downloadTrack('t2', url);
      expect(File(service.getCachedPathSync('t2')!).readAsBytesSync(), content);
    });

    test('files whose folder moved are found again by name', () async {
      final moved = File(p.join(temp.path, 't3.audio'))..writeAsStringSync('x');
      await db.upsertCachedTrack(CachedTracksCompanion(
        jellyfinId: const Value('t3'),
        localPath: Value(p.join(temp.path, 'old-place', 't3.audio')),
        sizeBytes: const Value(1),
        cachedAt: Value(DateTime(2026)),
      ));

      final service = CacheService(db, audioDirectory: temp);
      await service.init();

      expect(service.getCachedPathSync('t3'), moved.path);
      expect((await db.getCachedTrack('t3'))!.localPath, moved.path);
    });
  });
}
