import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../models/jellyfin_models.dart';
import 'music_service.dart';
import 'offline_cache_interceptor.dart';

/// An error the server reported inside an otherwise successful response.
class SubsonicError implements Exception {
  /// Subsonic error code: 40 wrong credentials, 41 token sign-in not
  /// supported, 70 not found, and so on.
  final int code;
  final String message;

  const SubsonicError(this.code, this.message);

  bool get isAuthFailure => code == 40 || code == 41 || code == 44;

  @override
  String toString() => 'SubsonicError($code, $message)';
}

/// Client for servers that speak the Subsonic API, including the
/// OpenSubsonic extensions: Navidrome, Gonic, Airsonic, LMS, Ampache,
/// Funkwhale, Nextcloud Music and others.
///
/// The password is never stored. Signing in derives a salted token from it,
/// which the API accepts on every request; that salt and token pair is what
/// [accessToken] holds (`salt:token`). Servers that cannot do token sign-in
/// (some LDAP setups) get the hex-encoded password instead (`enc:...`).
class SubsonicService extends MusicService {
  static const _apiVersion = '1.16.1';
  static const _client = 'Riffhouse';

  /// Songs requested per page when walking the whole library.
  static const _pageSize = 500;

  @override
  final String serverUrl;

  @override
  final String accessToken;

  @override
  final String userId;

  late final Dio _dio;
  late final String _restBase;

  SubsonicService({
    required this.serverUrl,
    required this.accessToken,
    this.userId = '',
    HttpClientAdapter? httpClientAdapter,
  }) {
    _restBase = '${MusicService.normalizeUrl(serverUrl)}rest/';
    _dio = Dio(
      BaseOptions(
        baseUrl: _restBase,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        queryParameters: _baseParams,
      ),
    );
    if (httpClientAdapter != null) _dio.httpClientAdapter = httpClientAdapter;
    // Library requests fall back to their last good answer when the server
    // cannot be reached, which is what makes offline browsing work.
    _dio.interceptors.add(OfflineCacheInterceptor(userId));
  }

  @override
  ServerType get type => ServerType.subsonic;

  /// Parameters every request carries: who is asking and in which format.
  Map<String, String> get _baseParams {
    final auth = <String, String>{'u': userId};
    if (accessToken.startsWith('enc:')) {
      auth['p'] = accessToken;
    } else {
      final split = accessToken.indexOf(':');
      if (split > 0) {
        auth['s'] = accessToken.substring(0, split);
        auth['t'] = accessToken.substring(split + 1);
      }
    }
    return {...auth, 'v': _apiVersion, 'c': _client, 'f': 'json'};
  }

  // ---------------------------------------------------------------------------
  // Signing in
  // ---------------------------------------------------------------------------

  /// Builds the stored credential for token sign-in: a random salt and the
  /// MD5 of the password followed by that salt, as the API defines it.
  static String tokenCredential(String password, String salt) =>
      '$salt:${md5.convert(utf8.encode('$password$salt'))}';

  static String _newSalt() {
    final random = Random.secure();
    return List.generate(12, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  static String _hex(String value) => utf8
      .encode(value)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  /// Signs in and returns the service together with the user. Throws a
  /// [LoginException] saying what went wrong if it fails.
  static Future<({MusicService service, JellyfinUser user})> signIn(
    String serverUrl,
    String username,
    String password, {
    HttpClientAdapter? httpClientAdapter,
  }) async {
    Future<SubsonicService> attempt(String credential) async {
      final service = SubsonicService(
        serverUrl: serverUrl,
        accessToken: credential,
        userId: username,
        httpClientAdapter: httpClientAdapter,
      );
      await service._get('ping', live: true);
      return service;
    }

    try {
      SubsonicService service;
      try {
        service = await attempt(tokenCredential(password, _newSalt()));
      } on SubsonicError catch (e) {
        // 41: this server cannot check tokens; fall back to the password.
        if (e.code != 41) rethrow;
        service = await attempt('enc:${_hex(password)}');
      }
      return (
        service: service as MusicService,
        user: JellyfinUser(
          id: username,
          name: username,
          accessToken: service.accessToken,
          isAdmin: false,
        ),
      );
    } on SubsonicError catch (e) {
      throw LoginException(e.isAuthFailure
          ? LoginFailure.invalidCredentials
          : LoginFailure.wrongServerType);
    } on DioException catch (e) {
      throw LoginException(e.response == null
          ? LoginFailure.unreachable
          : LoginFailure.wrongServerType);
    } on LoginException {
      rethrow;
    } catch (_) {
      // Something answered, but not with a Subsonic response.
      throw const LoginException(LoginFailure.wrongServerType);
    }
  }

  // ---------------------------------------------------------------------------
  // Requests
  // ---------------------------------------------------------------------------

  /// Calls [endpoint] and returns the `subsonic-response` object. Throws a
  /// [DioException] if the server cannot be reached and a [SubsonicError] if
  /// it answers with a failure.
  ///
  /// [live] requests are never answered from the offline cache.
  Future<Map<String, dynamic>> _get(
    String endpoint, {
    Map<String, dynamic>? params,
    bool live = false,
  }) async {
    final response = await _dio.get<dynamic>(
      '$endpoint.view',
      queryParameters: params,
      options: live
          ? Options(extra: const {OfflineCacheInterceptor.skip: true})
          : null,
    );
    final data = response.data;
    final body = data is Map ? data['subsonic-response'] : null;
    if (body is! Map) {
      throw const FormatException('Not a Subsonic response');
    }
    if (body['status'] != 'ok') {
      final error = body['error'];
      throw SubsonicError(
        error is Map ? (error['code'] as num?)?.toInt() ?? 0 : 0,
        error is Map ? '${error['message'] ?? ''}' : '',
      );
    }
    return Map<String, dynamic>.from(body);
  }

  /// A full request URL with the sign-in included, for the player and for
  /// artwork loaders that cannot add parameters themselves.
  String _url(String endpoint, Map<String, String> params) =>
      Uri.parse('$_restBase$endpoint.view')
          .replace(queryParameters: {..._baseParams, ...params}).toString();

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
      : const [];

  // ---------------------------------------------------------------------------
  // Mapping to the app's models
  // ---------------------------------------------------------------------------

  static String? _text(Object? value) {
    final text = value?.toString();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// Names from an OpenSubsonic `[{name: ...}]` list, if the server sent one.
  static List<String> _names(Object? value) => _list(value)
      .map((e) => _text(e['name']))
      .whereType<String>()
      .toList();

  static List<String> _genres(Map<String, dynamic> json) {
    final many = _names(json['genres']);
    if (many.isNotEmpty) return many;
    final one = _text(json['genre']);
    return one == null ? const [] : [one];
  }

  static JellyfinTrack trackFromJson(Map<String, dynamic> json) {
    final artists = _names(json['artists']);
    final artist = _text(json['artist']);
    final albumArtists = _names(json['albumArtists']);
    return JellyfinTrack(
      id: '${json['id'] ?? ''}',
      name: _text(json['title']) ?? _text(json['name']) ?? '',
      artists: artists.isNotEmpty ? artists : [if (artist != null) artist],
      albumArtist: _text(json['displayAlbumArtist']) ??
          (albumArtists.isNotEmpty ? albumArtists.first : artist ?? ''),
      albumId: '${json['albumId'] ?? ''}',
      albumName: _text(json['album']) ?? '',
      genres: _genres(json),
      // Subsonic reports whole seconds.
      durationMs: (((json['duration'] as num?) ?? 0) * 1000).round(),
      serverId: '',
      imageTag: _text(json['coverArt']),
      dateCreated: DateTime.tryParse(_text(json['created']) ?? ''),
    );
  }

  static JellyfinAlbum albumFromJson(Map<String, dynamic> json) {
    return JellyfinAlbum(
      id: '${json['id'] ?? ''}',
      name: _text(json['name']) ?? _text(json['title']) ?? '',
      artist: _text(json['displayArtist']) ?? _text(json['artist']) ?? '',
      year: (json['year'] as num?)?.toInt(),
      imageTag: _text(json['coverArt']),
      trackCount: (json['songCount'] as num?)?.toInt() ?? 0,
      dateCreated: DateTime.tryParse(_text(json['created']) ?? ''),
      genres: _genres(json),
    );
  }

  static JellyfinArtist artistFromJson(Map<String, dynamic> json) {
    return JellyfinArtist(
      id: '${json['id'] ?? ''}',
      name: _text(json['name']) ?? '',
      imageTag: _text(json['coverArt']),
    );
  }

  static JellyfinPlaylist playlistFromJson(Map<String, dynamic> json) {
    return JellyfinPlaylist(
      id: '${json['id'] ?? ''}',
      name: _text(json['name']) ?? '',
      trackCount: (json['songCount'] as num?)?.toInt() ?? 0,
      imageTag: _text(json['coverArt']),
    );
  }

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  @override
  Future<SessionStatus> checkSession() async {
    try {
      await _get('ping', live: true);
      return SessionStatus.valid;
    } on SubsonicError catch (e) {
      return e.isAuthFailure
          ? SessionStatus.unauthorized
          : SessionStatus.unreachable;
    } catch (_) {
      return SessionStatus.unreachable;
    }
  }

  // ---------------------------------------------------------------------------
  // Library
  // ---------------------------------------------------------------------------

  Future<List<JellyfinAlbum>> _albumList(
    String listType, {
    required int size,
    int offset = 0,
    bool live = false,
  }) async {
    final body = await _get(
      'getAlbumList2',
      params: {'type': listType, 'size': size, 'offset': offset},
      live: live,
    );
    final list = body['albumList2'];
    return _list(list is Map ? list['album'] : null).map(albumFromJson).toList();
  }

  Future<List<JellyfinAlbum>> _allAlbums({bool live = false}) async {
    final albums = <JellyfinAlbum>[];
    while (true) {
      final page = await _albumList(
        'alphabeticalByName',
        size: _pageSize,
        offset: albums.length,
        live: live,
      );
      albums.addAll(page);
      if (page.length < _pageSize) return albums;
    }
  }

  Future<List<JellyfinTrack>> _albumSongs(String albumId,
      {bool live = false}) async {
    final body = await _get('getAlbum', params: {'id': albumId}, live: live);
    final album = body['album'];
    return _list(album is Map ? album['song'] : null)
        .map(trackFromJson)
        .toList();
  }

  @override
  Future<List<JellyfinTrack>> getTracks({bool throwOnError = false}) async {
    final tracks = <JellyfinTrack>[];
    try {
      // The API has no "all songs" call. An empty search returns everything
      // on Navidrome and other OpenSubsonic servers, a page at a time.
      while (true) {
        final body = await _get(
          'search3',
          params: {
            'query': '',
            'songCount': _pageSize,
            'songOffset': tracks.length,
            'albumCount': 0,
            'artistCount': 0,
          },
          live: true,
        );
        final result = body['searchResult3'];
        final page = _list(result is Map ? result['song'] : null);
        tracks.addAll(page.map(trackFromJson));
        if (page.length < _pageSize) break;
      }

      // Older servers answer an empty search with nothing; walk the albums.
      if (tracks.isEmpty) {
        for (final album in await _allAlbums(live: true)) {
          tracks.addAll(await _albumSongs(album.id, live: true));
        }
      }
      return tracks;
    } catch (_) {
      if (throwOnError) rethrow;
      return tracks;
    }
  }

  @override
  Future<List<JellyfinTrack>> fetchNewTracks(
    Future<bool> Function(String trackId) isKnown,
  ) async {
    // Songs cannot be listed by date, but albums can: go through the newest
    // albums until one has nothing new in it.
    const albumsPerPage = 20;
    const maxPages = 10;
    final added = <JellyfinTrack>[];
    try {
      for (var page = 0; page < maxPages; page++) {
        final albums = await _albumList(
          'newest',
          size: albumsPerPage,
          offset: page * albumsPerPage,
          live: true,
        );
        for (final album in albums) {
          var anyNew = false;
          for (final track in await _albumSongs(album.id, live: true)) {
            if (!await isKnown(track.id)) {
              added.add(track);
              anyNew = true;
            }
          }
          if (!anyNew) return added;
        }
        if (albums.length < albumsPerPage) break;
      }
    } catch (_) {
      // Return what was found; the next sync continues.
    }
    return added;
  }

  @override
  Future<List<JellyfinAlbum>> getAlbums() async {
    try {
      return await _allAlbums();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<JellyfinArtist>> getArtists() async {
    try {
      final body = await _get('getArtists');
      final artists = body['artists'];
      return [
        for (final index in _list(artists is Map ? artists['index'] : null))
          ..._list(index['artist']).map(artistFromJson),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _playlistsJson() async {
    final body = await _get('getPlaylists');
    final playlists = body['playlists'];
    return _list(playlists is Map ? playlists['playlist'] : null);
  }

  @override
  Future<List<JellyfinPlaylist>> getPlaylists() async {
    try {
      return (await _playlistsJson()).map(playlistFromJson).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<JellyfinTrack>> getPlaylistTracks(
    String playlistId, {
    bool throwOnError = false,
  }) async {
    try {
      final body = await _get('getPlaylist', params: {'id': playlistId});
      final playlist = body['playlist'];
      return _list(playlist is Map ? playlist['entry'] : null)
          .map(trackFromJson)
          .toList();
    } catch (_) {
      if (throwOnError) rethrow;
      return [];
    }
  }

  @override
  Future<JellyfinTrack?> getTrack(String trackId) async {
    try {
      final body = await _get('getSong', params: {'id': trackId});
      final song = body['song'];
      return song is Map
          ? trackFromJson(Map<String, dynamic>.from(song))
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<JellyfinTrack>> getAlbumTracks(String albumId) async {
    try {
      return await _albumSongs(albumId);
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<JellyfinAlbum>> getArtistAlbums(String artistId) async {
    try {
      final body = await _get('getArtist', params: {'id': artistId});
      final artist = body['artist'];
      return _list(artist is Map ? artist['album'] : null)
          .map(albumFromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<JellyfinTrack>> getArtistTracks(String artistId) async {
    final tracks = <JellyfinTrack>[];
    try {
      for (final album in await getArtistAlbums(artistId)) {
        tracks.addAll(await _albumSongs(album.id));
      }
    } catch (_) {
      // Return the albums that could be read.
    }
    return tracks;
  }

  @override
  Future<List<JellyfinAlbum>> getRecentAlbums({int limit = 12}) async {
    try {
      return await _albumList('recent', size: limit);
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<JellyfinArtist>> getRecentArtists({int limit = 10}) async {
    // There is no "recent artists" list; take them from recent albums.
    try {
      final body = await _get(
        'getAlbumList2',
        params: {'type': 'recent', 'size': limit * 3},
      );
      final list = body['albumList2'];
      final seen = <String>{};
      final artists = <JellyfinArtist>[];
      for (final album in _list(list is Map ? list['album'] : null)) {
        final id = _text(album['artistId']);
        final name = _text(album['artist']);
        if (id == null || name == null || !seen.add(id)) continue;
        artists.add(JellyfinArtist(id: id, name: name));
        if (artists.length >= limit) break;
      }
      return artists;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<JellyfinPlaylist>> getRecentPlaylists({int limit = 6}) async {
    try {
      final playlists = await _playlistsJson();
      // ISO timestamps sort correctly as text.
      playlists.sort((a, b) =>
          '${b['changed'] ?? ''}'.compareTo('${a['changed'] ?? ''}'));
      return playlists.take(limit).map(playlistFromJson).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<JellyfinAlbum>> getNewAlbums({int limit = 12}) async {
    try {
      return await _albumList('newest', size: limit);
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _search(
    String query, {
    int songs = 0,
    int albums = 0,
    int artists = 0,
  }) async {
    final body = await _get(
      'search3',
      params: {
        'query': query,
        'songCount': songs,
        'albumCount': albums,
        'artistCount': artists,
      },
      live: true,
    );
    final result = body['searchResult3'];
    return result is Map ? Map<String, dynamic>.from(result) : const {};
  }

  @override
  Future<List<JellyfinTrack>> searchTracks(String query,
      {int limit = 50}) async {
    try {
      final result = await _search(query, songs: limit);
      return _list(result['song']).map(trackFromJson).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<JellyfinAlbum>> searchAlbums(String query,
      {int limit = 20}) async {
    try {
      final result = await _search(query, albums: limit);
      return _list(result['album']).map(albumFromJson).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<JellyfinArtist>> searchArtists(String query,
      {int limit = 10}) async {
    try {
      final result = await _search(query, artists: limit);
      return _list(result['artist']).map(artistFromJson).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>> search(String query) async {
    try {
      final result = await _search(query, songs: 20, albums: 10);
      return {
        'tracks': _list(result['song']).map(trackFromJson).toList(),
        'albums': _list(result['album']).map(albumFromJson).toList(),
      };
    } catch (_) {
      return {'tracks': <JellyfinTrack>[], 'albums': <JellyfinAlbum>[]};
    }
  }

  // ---------------------------------------------------------------------------
  // Playlists
  // ---------------------------------------------------------------------------

  @override
  Future<String?> createPlaylist(String name, List<String> trackIds) async {
    try {
      final body = await _get(
        'createPlaylist',
        params: {
          'name': name,
          if (trackIds.isNotEmpty)
            'songId': ListParam<String>(trackIds, ListFormat.multi),
        },
        live: true,
      );
      final created = body['playlist'];
      final id = created is Map ? _text(created['id']) : null;
      if (id != null) return id;

      // Servers older than API 1.14 answer without the playlist; find it.
      final matches = (await _get('getPlaylists', live: true))['playlists'];
      final named = _list(matches is Map ? matches['playlist'] : null)
          .where((p) => p['name'] == name)
          .toList();
      return named.isEmpty ? null : _text(named.last['id']);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> addTrackToPlaylist(String playlistId, String trackId) async {
    try {
      await _get(
        'updatePlaylist',
        params: {'playlistId': playlistId, 'songIdToAdd': trackId},
        live: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> removeTrackFromPlaylist(
      String playlistId, String trackId) async {
    try {
      // Tracks are removed by their position in the playlist.
      final body =
          await _get('getPlaylist', params: {'id': playlistId}, live: true);
      final playlist = body['playlist'];
      final entries = _list(playlist is Map ? playlist['entry'] : null);
      final indexes = <String>[
        for (var i = 0; i < entries.length; i++)
          if ('${entries[i]['id']}' == trackId) '$i',
      ];
      if (indexes.isEmpty) return false;
      await _get(
        'updatePlaylist',
        params: {
          'playlistId': playlistId,
          'songIndexToRemove': ListParam<String>(indexes, ListFormat.multi),
        },
        live: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> deletePlaylist(String playlistId) async {
    try {
      await _get('deletePlaylist', params: {'id': playlistId}, live: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  bool get supportsCustomCovers => false;

  /// The Subsonic API has no way to set a playlist's cover.
  @override
  Future<bool> uploadItemImage(
          String itemId, List<int> imageBytes, String mimeType) async =>
      false;

  // ---------------------------------------------------------------------------
  // Likes
  // ---------------------------------------------------------------------------

  @override
  Future<Set<String>?> getFavoriteTrackIds() async {
    try {
      final body = await _get('getStarred2', live: true);
      final starred = body['starred2'];
      return _list(starred is Map ? starred['song'] : null)
          .map((song) => '${song['id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> setFavorite(String trackId, bool favorite) async {
    try {
      await _get(favorite ? 'star' : 'unstar',
          params: {'id': trackId}, live: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  @override
  Future<ReportResult> markPlayed(String itemId, DateTime playedAt) async {
    try {
      await _get(
        'scrobble',
        params: {
          'id': itemId,
          'time': playedAt.toUtc().millisecondsSinceEpoch,
          'submission': true,
        },
        live: true,
      );
      return ReportResult.sent;
    } on SubsonicError catch (e) {
      // An expired sign-in can recover; anything else will not.
      return e.isAuthFailure ? ReportResult.unreachable : ReportResult.rejected;
    } catch (_) {
      return ReportResult.unreachable;
    }
  }

  /// `format=raw` asks for the file as stored rather than a transcode, the
  /// same as the other server types.
  @override
  String getStreamUrl(String trackId) =>
      _url('stream', {'id': trackId, 'format': 'raw'});

  /// Subsonic artwork is addressed by a cover id, which the models carry in
  /// `imageTag`; without one the item's own id usually works.
  @override
  String artworkUrl(String itemId, {String? imageTag}) => _url('getCoverArt', {
        'id': (imageTag != null && imageTag.isNotEmpty) ? imageTag : itemId,
        'size': '600',
      });
}
