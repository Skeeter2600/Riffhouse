import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffhouse/audio/audio_handler.dart';
import 'package:riffhouse/database/app_database.dart';
import 'package:riffhouse/models/jellyfin_models.dart';
import 'package:riffhouse/providers/library_provider.dart';
import 'package:riffhouse/services/favorites_store.dart';
import 'package:riffhouse/services/jellyfin_service.dart';
import 'package:riffhouse/services/local_cover_store.dart';
import 'package:riffhouse/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers requests from a script and records what was asked.
class _FakeServer implements HttpClientAdapter {
  /// Returns the JSON body to answer with, or throws.
  Object? Function(Uri uri) respond;
  final requests = <RequestOptions>[];

  _FakeServer(this.respond);

  Iterable<Uri> get uris => requests.map((r) => r.uri);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(respond(options.uri)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _ok([Map<String, dynamic> body = const {}]) => {
      'subsonic-response': {'status': 'ok', 'version': '1.16.1', ...body},
    };

Map<String, dynamic> _failed(int code) => {
      'subsonic-response': {
        'status': 'failed',
        'error': {'code': code, 'message': 'nope'},
      },
    };

String _endpoint(Uri uri) => uri.pathSegments.last.replaceAll('.view', '');

void main() {
  group('Server types', () {
    test('a sign-in saved without a type is Jellyfin', () {
      expect(ServerType.fromId(null), ServerType.jellyfin);
      expect(ServerType.fromId('jellyfin'), ServerType.jellyfin);
      expect(ServerType.fromId('emby'), ServerType.emby);
      expect(ServerType.fromId('subsonic'), ServerType.subsonic);
    });

    test('each type gets its own client', () {
      MusicService make(ServerType type) => MusicService.create(
          type: type, serverUrl: 'server:1', accessToken: 'a:b', userId: 'u');
      expect(make(ServerType.jellyfin), isA<JellyfinService>());
      expect(make(ServerType.emby).type, ServerType.emby);
      expect(make(ServerType.subsonic), isA<SubsonicService>());
      expect(MusicService.signedOut().isSignedIn, isFalse);
    });
  });

  group('Emby', () {
    test('uses the /emby API path; Jellyfin does not', () {
      final emby = JellyfinService(
          type: ServerType.emby, serverUrl: 'http://media:8096', accessToken: 'tok');
      final jellyfin =
          JellyfinService(serverUrl: 'http://media:8096', accessToken: 'tok');

      expect(emby.getStreamUrl('t1'),
          'http://media:8096/emby/Audio/t1/stream?static=true&api_key=tok');
      expect(jellyfin.getStreamUrl('t1'),
          'http://media:8096/Audio/t1/stream?static=true&api_key=tok');
      expect(emby.artworkUrl('a1', imageTag: 'x'),
          'http://media:8096/emby/Items/a1/Images/Primary?api_key=tok&tag=x');
      // Unchanged from before other servers existed, so cached artwork
      // keeps being found.
      expect(jellyfin.getImageUrl('a1', 'x'),
          'http://media:8096/Items/a1/Images/Primary?tag=x&api_key=tok');
      expect(jellyfin.getAlbumArtUrl('a1'),
          'http://media:8096/Items/a1/Images/Primary?api_key=tok');
    });

    test('reports plays with the date format each server expects', () async {
      final played = DateTime.utc(2026, 3, 9, 7, 5, 2);
      Future<Uri> report(ServerType type) async {
        final server = _FakeServer((_) => {});
        final service = JellyfinService(
          type: type,
          serverUrl: 'http://media',
          accessToken: 'tok',
          userId: 'u1',
          httpClientAdapter: server,
        );
        expect(await service.markPlayed('t1', played), ReportResult.sent);
        return server.uris.single;
      }

      final emby = await report(ServerType.emby);
      expect(emby.path, '/emby/Users/u1/PlayedItems/t1');
      expect(emby.queryParameters['DatePlayed'], '20260309070502');

      final jellyfin = await report(ServerType.jellyfin);
      expect(jellyfin.path, '/Users/u1/PlayedItems/t1');
      expect(jellyfin.queryParameters['DatePlayed'],
          played.toIso8601String());
    });
  });

  group('Subsonic sign-in', () {
    test('sends a salted token, never the password', () async {
      final server = _FakeServer((_) => _ok());
      final result = await SubsonicService.signIn(
          'music.home:4533', 'ana', 'hunter2',
          httpClientAdapter: server);

      final uri = server.uris.single;
      expect(uri.toString(), startsWith('http://music.home:4533/rest/ping.view'));
      final q = uri.queryParameters;
      expect(q['u'], 'ana');
      expect(q['f'], 'json');
      expect(q['c'], 'Riffhouse');
      expect(q.containsKey('p'), isFalse);
      expect(q['t'], md5.convert(utf8.encode('hunter2${q['s']}')).toString());
      expect(uri.toString(), isNot(contains('hunter2')));

      // The stored credential is that same salt and token.
      expect(result.service.accessToken, '${q['s']}:${q['t']}');
      expect(result.service.userId, 'ana');
      expect(result.service.type, ServerType.subsonic);
      expect(result.user.name, 'ana');
    });

    test('falls back to the password where tokens are not supported',
        () async {
      final server = _FakeServer(
          (uri) => uri.queryParameters.containsKey('t') ? _failed(41) : _ok());
      final result = await SubsonicService.signIn('http://s', 'ana', 'pw',
          httpClientAdapter: server);
      expect(result.service.accessToken, 'enc:7077');
      expect(server.uris.last.queryParameters['p'], 'enc:7077');
    });

    Future<LoginFailure> failure(Object? Function(Uri) respond) async {
      try {
        await SubsonicService.signIn('http://s', 'ana', 'pw',
            httpClientAdapter: _FakeServer(respond));
      } on LoginException catch (e) {
        return e.failure;
      }
      fail('sign-in should not have succeeded');
    }

    test('says what went wrong', () async {
      expect(await failure((_) => _failed(40)),
          LoginFailure.invalidCredentials);
      // Something that is not a Subsonic server (e.g. Jellyfin was picked
      // by mistake).
      expect(await failure((_) => {'Version': '10.10'}),
          LoginFailure.wrongServerType);
      expect(
        await failure((uri) => throw DioException(
              requestOptions: RequestOptions(path: '$uri'),
              type: DioExceptionType.connectionError,
            )),
        LoginFailure.unreachable,
      );
    });
  });

  group('Subsonic library', () {
    late _FakeServer server;
    late SubsonicService service;

    setUp(() {
      server = _FakeServer((_) => _ok());
      service = SubsonicService(
        serverUrl: 'http://s',
        accessToken: 'salt:token',
        userId: 'ana',
        httpClientAdapter: server,
      );
    });

    test('reads plain and OpenSubsonic song fields', () {
      final plain = SubsonicService.trackFromJson({
        'id': 42,
        'title': 'Song',
        'artist': 'Band',
        'album': 'Record',
        'albumId': 'al-1',
        'genre': 'Rock',
        'duration': 185,
        'coverArt': 'cover-1',
        'created': '2026-01-02T03:04:05Z',
      });
      expect(plain.id, '42');
      expect(plain.name, 'Song');
      expect(plain.artists, ['Band']);
      expect(plain.albumArtist, 'Band');
      expect(plain.albumId, 'al-1');
      expect(plain.genres, ['Rock']);
      expect(plain.durationMs, 185000);
      expect(plain.imageTag, 'cover-1');
      expect(plain.dateCreated, DateTime.utc(2026, 1, 2, 3, 4, 5));

      final open = SubsonicService.trackFromJson({
        'id': 't',
        'title': 'Duet',
        'artist': 'A & B',
        'artists': [
          {'id': '1', 'name': 'A'},
          {'id': '2', 'name': 'B'},
        ],
        'displayAlbumArtist': 'Various',
        'genres': [
          {'name': 'Pop'},
          {'name': 'Soul'},
        ],
      });
      expect(open.artists, ['A', 'B']);
      expect(open.albumArtist, 'Various');
      expect(open.genres, ['Pop', 'Soul']);
    });

    test('fetches the whole library a page at a time', () async {
      server.respond = (uri) {
        expect(_endpoint(uri), 'search3');
        expect(uri.queryParameters['query'], '');
        final offset = int.parse(uri.queryParameters['songOffset']!);
        final count = offset == 0 ? 500 : 3;
        return _ok({
          'searchResult3': {
            'song': [
              for (var i = 0; i < count; i++)
                {'id': 's${offset + i}', 'title': 'T'},
            ],
          },
        });
      };

      final tracks = await service.getTracks();
      expect(tracks, hasLength(503));
      expect(server.requests, hasLength(2));
      expect(tracks.last.id, 's502');
    });

    test('walks the albums when an empty search returns nothing', () async {
      server.respond = (uri) {
        switch (_endpoint(uri)) {
          case 'search3':
            return _ok({'searchResult3': {}});
          case 'getAlbumList2':
            return _ok({
              'albumList2': {
                'album': [
                  {'id': 'a1', 'name': 'One'},
                  {'id': 'a2', 'name': 'Two'},
                ],
              },
            });
          case 'getAlbum':
            final id = uri.queryParameters['id'];
            return _ok({
              'album': {
                'song': [
                  {'id': '$id-1', 'title': 'x'},
                  {'id': '$id-2', 'title': 'y'},
                ],
              },
            });
        }
        return _ok();
      };

      final tracks = await service.getTracks();
      expect(tracks.map((t) => t.id), ['a1-1', 'a1-2', 'a2-1', 'a2-2']);
    });

    test('a failed full fetch throws when the caller needs the whole library',
        () async {
      server.respond = (_) => _failed(0);
      expect(await service.getTracks(), isEmpty);
      expect(() => service.getTracks(throwOnError: true),
          throwsA(isA<SubsonicError>()));
    });

    test('looks for new tracks in the newest albums and stops at known ones',
        () async {
      server.respond = (uri) {
        switch (_endpoint(uri)) {
          case 'getAlbumList2':
            expect(uri.queryParameters['type'], 'newest');
            return _ok({
              'albumList2': {
                'album': [
                  {'id': 'new', 'name': 'New'},
                  {'id': 'old', 'name': 'Old'},
                  {'id': 'older', 'name': 'Older'},
                ],
              },
            });
          case 'getAlbum':
            final id = uri.queryParameters['id'];
            return _ok({
              'album': {
                'song': [
                  {'id': '$id-1', 'title': 'x'},
                ],
              },
            });
        }
        return _ok();
      };

      final added = await service.fetchNewTracks((id) async => id != 'new-1');
      expect(added.map((t) => t.id), ['new-1']);
      // The third album is never opened.
      expect(server.uris.where((u) => u.queryParameters['id'] == 'older'),
          isEmpty);
    });

    test('creates a playlist with every track', () async {
      server.respond = (_) => _ok({
            'playlist': {'id': 'p9', 'name': 'Mix'},
          });
      expect(await service.createPlaylist('Mix', ['a', 'b', 'c']), 'p9');
      final uri = server.uris.single;
      expect(_endpoint(uri), 'createPlaylist');
      expect(uri.queryParametersAll['songId'], ['a', 'b', 'c']);
    });

    test('removes a track by its positions in the playlist', () async {
      server.respond = (uri) => _endpoint(uri) == 'getPlaylist'
          ? _ok({
              'playlist': {
                'entry': [
                  {'id': 'x'},
                  {'id': 'gone'},
                  {'id': 'y'},
                  {'id': 'gone'},
                ],
              },
            })
          : _ok();

      expect(await service.removeTrackFromPlaylist('p1', 'gone'), isTrue);
      final update = server.uris.last;
      expect(_endpoint(update), 'updatePlaylist');
      expect(update.queryParameters['playlistId'], 'p1');
      expect(update.queryParametersAll['songIndexToRemove'], ['1', '3']);

      expect(await service.removeTrackFromPlaylist('p1', 'absent'), isFalse);
    });

    test('reports plays as scrobbles and tells failures apart', () async {
      final played = DateTime.utc(2026, 3, 9);
      expect(await service.markPlayed('t1', played), ReportResult.sent);
      final uri = server.uris.single;
      expect(_endpoint(uri), 'scrobble');
      expect(uri.queryParameters['id'], 't1');
      expect(uri.queryParameters['time'], '${played.millisecondsSinceEpoch}');
      expect(uri.queryParameters['submission'], 'true');

      server.respond = (_) => _failed(70); // not found
      expect(await service.markPlayed('t1', played), ReportResult.rejected);
      server.respond = (_) => _failed(40); // sign-in no longer accepted
      expect(await service.markPlayed('t1', played), ReportResult.unreachable);
    });

    test('checks the session without signing out on other errors', () async {
      expect(await service.checkSession(), SessionStatus.valid);
      server.respond = (_) => _failed(40);
      expect(await service.checkSession(), SessionStatus.unauthorized);
      server.respond = (_) => _failed(0);
      expect(await service.checkSession(), SessionStatus.unreachable);
    });

    test('stream and artwork URLs carry the sign-in', () {
      final stream = Uri.parse(service.getStreamUrl('t1'));
      expect(stream.path, '/rest/stream.view');
      expect(stream.queryParameters,
          containsPair('id', 't1'));
      expect(stream.queryParameters, containsPair('format', 'raw'));
      expect(stream.queryParameters, containsPair('u', 'ana'));
      expect(stream.queryParameters, containsPair('s', 'salt'));
      expect(stream.queryParameters, containsPair('t', 'token'));

      // The cover id from the model wins over the item id.
      expect(Uri.parse(service.getImageUrl('t1', 'cover-7')).queryParameters['id'],
          'cover-7');
      expect(Uri.parse(service.getAlbumArtUrl('al-1')).queryParameters['id'],
          'al-1');
    });
  });

  group('Covers kept on the device', () {
    late Directory temp;
    final subsonic = SubsonicService(
        serverUrl: 'http://s', accessToken: 'salt:token', userId: 'ana');

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('riffhouse_covers_');
      await LocalCoverStore.init(directory: temp);
    });

    tearDown(() async {
      try {
        await temp.delete(recursive: true);
      } catch (_) {
        // The OS cleans temp up.
      }
    });

    test('only servers without cover support use them', () {
      expect(subsonic.supportsCustomCovers, isFalse);
      expect(
          JellyfinService(serverUrl: 'http://j', accessToken: 't')
              .supportsCustomCovers,
          isTrue);
    });

    test('a saved cover is found again after a restart', () async {
      expect(LocalCoverStore.coverFor(subsonic, 'p1'), isNull);
      expect(await LocalCoverStore.save(subsonic, 'p1', [1, 2, 3]), isTrue);
      expect(LocalCoverStore.coverFor(subsonic, 'p1')!.readAsBytesSync(),
          [1, 2, 3]);

      await LocalCoverStore.init(directory: temp);
      expect(LocalCoverStore.coverFor(subsonic, 'p1')!.readAsBytesSync(),
          [1, 2, 3]);
    });

    test('replacing a cover uses a new file and removes the old one',
        () async {
      await LocalCoverStore.save(subsonic, 'p1', [1]);
      final first = LocalCoverStore.coverFor(subsonic, 'p1')!;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await LocalCoverStore.save(subsonic, 'p1', [2]);
      final second = LocalCoverStore.coverFor(subsonic, 'p1')!;

      expect(second.path, isNot(first.path));
      expect(first.existsSync(), isFalse);
      expect(second.readAsBytesSync(), [2]);
      expect(temp.listSync(), hasLength(1));
    });

    test('covers belong to one account on one server', () async {
      await LocalCoverStore.save(subsonic, 'p1', [1]);
      final otherUser = SubsonicService(
          serverUrl: 'http://s', accessToken: 'salt:token', userId: 'ben');
      final otherServer = SubsonicService(
          serverUrl: 'http://other', accessToken: 'salt:token', userId: 'ana');
      expect(LocalCoverStore.coverFor(otherUser, 'p1'), isNull);
      expect(LocalCoverStore.coverFor(otherServer, 'p1'), isNull);
      expect(LocalCoverStore.coverFor(subsonic, 'p2'), isNull);
    });

    test('removing a cover deletes its file', () async {
      await LocalCoverStore.save(subsonic, 'p1', [1]);
      await LocalCoverStore.remove(subsonic, 'p1');
      expect(LocalCoverStore.coverFor(subsonic, 'p1'), isNull);
      expect(temp.listSync(), isEmpty);
    });
  });

  group('Crossfade', () {
    const length = Duration(seconds: 4);
    ({double incoming, double outgoing}) at(int ms) =>
        JellyfinAudioHandler.crossfadeVolumes(
            Duration(milliseconds: ms), length);

    test('the old song falls from full to silent as the new one rises', () {
      expect(at(0), (incoming: 0.0, outgoing: 1.0));
      expect(at(1000), (incoming: 0.25, outgoing: 0.75));
      expect(at(2000), (incoming: 0.5, outgoing: 0.5));
      expect(at(4000), (incoming: 1.0, outgoing: 0.0));
    });

    test('the two volumes always add up to full and never overshoot', () {
      for (var ms = -500; ms <= 6000; ms += 37) {
        final v = at(ms);
        expect(v.incoming + v.outgoing, closeTo(1.0, 1e-9));
        expect(v.incoming, inInclusiveRange(0.0, 1.0));
      }
      expect(at(9000), (incoming: 1.0, outgoing: 0.0));
    });

    test('two seconds is the default length', () {
      expect(JellyfinAudioHandler.defaultCrossfadeSeconds, 2);
    });
  });

  group('Likes', () {
    late _FakeServer server;
    late SubsonicService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      server = _FakeServer((_) => _ok());
      service = SubsonicService(
        serverUrl: 'http://s',
        accessToken: 'salt:token',
        userId: 'ana',
        httpClientAdapter: server,
      );
      await FavoritesStore.load(service);
    });

    test('liking stars the track on the server and is remembered', () async {
      expect(FavoritesStore.isFavorite('t1'), isFalse);
      expect(await FavoritesStore.toggle(service, 't1'), isTrue);
      expect(FavoritesStore.isFavorite('t1'), isTrue);
      expect(_endpoint(server.uris.last), 'star');
      expect(server.uris.last.queryParameters['id'], 't1');

      // Still liked after a restart.
      await FavoritesStore.load(service);
      expect(FavoritesStore.isFavorite('t1'), isTrue);

      expect(await FavoritesStore.toggle(service, 't1'), isTrue);
      expect(FavoritesStore.isFavorite('t1'), isFalse);
      expect(_endpoint(server.uris.last), 'unstar');
    });

    test('a like the server did not accept is undone', () async {
      server.respond = (_) => _failed(0);
      expect(await FavoritesStore.toggle(service, 't1'), isFalse);
      expect(FavoritesStore.isFavorite('t1'), isFalse);
    });

    test('likes made in other apps are picked up from the server', () async {
      server.respond = (uri) => _endpoint(uri) == 'getStarred2'
          ? _ok({
              'starred2': {
                'song': [
                  {'id': 'a'},
                  {'id': 'b'},
                ],
              },
            })
          : _ok();
      await FavoritesStore.sync(service);
      expect(FavoritesStore.isFavorite('a'), isTrue);
      expect(FavoritesStore.isFavorite('b'), isTrue);

      // Unreachable server: keep what we have.
      server.respond = (uri) => throw DioException(
            requestOptions: RequestOptions(path: '$uri'),
            type: DioExceptionType.connectionError,
          );
      await FavoritesStore.sync(service);
      expect(FavoritesStore.isFavorite('a'), isTrue);
    });

    test('Liked Songs holds the liked tracks, in library order', () async {
      JellyfinTrack track(String id) => SubsonicService.trackFromJson(
          {'id': id, 'title': 'Song $id'});
      final library = [track('a'), track('b'), track('c'), track('d')];

      expect(FavoritesStore.likedTracks(library), isEmpty);
      await FavoritesStore.toggle(service, 'c');
      await FavoritesStore.toggle(service, 'a');
      expect(FavoritesStore.count, 2);
      expect(FavoritesStore.likedTracks(library).map((t) => t.id), ['a', 'c']);

      await FavoritesStore.toggle(service, 'a');
      expect(FavoritesStore.likedTracks(library).map((t) => t.id), ['c']);
    });

    test('another account does not see these likes', () async {
      await FavoritesStore.toggle(service, 't1');
      final other = SubsonicService(
        serverUrl: 'http://s',
        accessToken: 'salt:token',
        userId: 'ben',
        httpClientAdapter: server,
      );
      await FavoritesStore.load(other);
      expect(FavoritesStore.isFavorite('t1'), isFalse);
    });

    test('Jellyfin and Emby use the favorites endpoint', () async {
      final jf = _FakeServer((_) => {});
      final jellyfin = JellyfinService(
        serverUrl: 'http://media',
        accessToken: 'tok',
        userId: 'u1',
        httpClientAdapter: jf,
      );
      expect(await jellyfin.setFavorite('t1', true), isTrue);
      expect(jf.requests.last.method, 'POST');
      expect(jf.uris.last.path, '/Users/u1/FavoriteItems/t1');
      expect(await jellyfin.setFavorite('t1', false), isTrue);
      expect(jf.requests.last.method, 'DELETE');

      jf.respond = (_) => {
            'Items': [
              {'Id': 'x'},
              {'Id': 'y'},
            ],
          };
      expect(await jellyfin.getFavoriteTrackIds(), {'x', 'y'});
      expect(jf.uris.last.queryParameters['Filters'], 'IsFavorite');
    });
  });

  group('Media controls', () {
    test('the repeat button steps through off, all, one', () {
      var mode = AudioServiceRepeatMode.none;
      mode = JellyfinAudioHandler.nextRepeatMode(mode);
      expect(mode, AudioServiceRepeatMode.all);
      mode = JellyfinAudioHandler.nextRepeatMode(mode);
      expect(mode, AudioServiceRepeatMode.one);
      mode = JellyfinAudioHandler.nextRepeatMode(mode);
      expect(mode, AudioServiceRepeatMode.none);
    });
  });

  group('Library sync', () {
    final now = DateTime(2026, 10, 12, 20);

    test('a full sync runs the first time and then at most once a day', () {
      expect(TracksNotifier.isFullSyncDue(null, now), isTrue);
      expect(
          TracksNotifier.isFullSyncDue(
              now.subtract(const Duration(minutes: 5)), now),
          isFalse);
      expect(
          TracksNotifier.isFullSyncDue(
              now.subtract(const Duration(hours: 23, minutes: 59)), now),
          isFalse);
      expect(
          TracksNotifier.isFullSyncDue(
              now.subtract(const Duration(hours: 24)), now),
          isTrue);
    });
  });

  group('Database upgrade', () {
    test('adds the server type to an existing sign-in without touching data',
        () async {
      // The schema as it is on installs made before other servers existed.
      final db = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
        raw.execute('CREATE TABLE "cached_tracks" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "jellyfin_id" TEXT NOT NULL UNIQUE, "local_path" TEXT NOT NULL, "size_bytes" INTEGER NOT NULL, "cached_at" INTEGER NOT NULL);');
        raw.execute('CREATE TABLE "playback_records" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "jellyfin_id" TEXT NOT NULL UNIQUE, "play_count" INTEGER NOT NULL DEFAULT 0, "skip_count" INTEGER NOT NULL DEFAULT 0, "last_played_at" INTEGER NOT NULL);');
        raw.execute('CREATE TABLE "local_playlists" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "jellyfin_id" TEXT NOT NULL UNIQUE, "name" TEXT NOT NULL, "track_ids_json" TEXT NOT NULL, "last_synced_at" INTEGER NOT NULL);');
        raw.execute('CREATE TABLE "server_configs" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "server_url" TEXT NOT NULL, "user_id" TEXT NOT NULL, "username" TEXT NOT NULL, "access_token" TEXT NOT NULL);');
        raw.execute('CREATE TABLE "local_tracks" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "jellyfin_id" TEXT NOT NULL UNIQUE, "name" TEXT NOT NULL, "artists_json" TEXT NOT NULL, "album_artist" TEXT NOT NULL, "album_id" TEXT NOT NULL, "album_name" TEXT NOT NULL, "genres_json" TEXT NOT NULL, "duration_ms" INTEGER NOT NULL, "server_id" TEXT NOT NULL, "image_tag" TEXT NULL, "date_created" INTEGER NULL);');
        raw.execute("INSERT INTO server_configs (server_url, user_id, username, access_token) VALUES ('http://jf', 'u1', 'ana', 'tok');");
        raw.execute("INSERT INTO playback_records (jellyfin_id, play_count, skip_count, last_played_at) VALUES ('t1', 9, 2, 1700000000);");
        raw.execute('PRAGMA user_version = 2;');
      }));
      addTearDown(db.close);

      final session = (await db.getServerConfig())!;
      expect(session.serverType, 'jellyfin');
      expect(session.serverUrl, 'http://jf');
      expect(session.accessToken, 'tok');

      final record = (await db.getPlaybackRecord('t1'))!;
      expect(record.playCount, 9);
      expect(record.skipCount, 2);
    });
  });
}
