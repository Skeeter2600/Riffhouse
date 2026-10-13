import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/jellyfin_models.dart';
import '../utils/log.dart';
import 'music_service.dart';
import 'offline_cache_interceptor.dart';

export 'music_service.dart';

/// Client for Jellyfin, and for Emby, whose API Jellyfin inherited.
///
/// The two differ in only a few places, each marked where [type] is checked.
/// Construct with [serverUrl] and [accessToken] after authenticating.
/// Use the static [authenticate] method to obtain credentials.
class JellyfinService extends MusicService {
  @override
  final ServerType type;

  @override
  final String serverUrl;

  @override
  final String accessToken;

  /// Id of the authenticated user. Set by [authenticate].
  @override
  String userId;

  late final Dio _dio;

  JellyfinService({
    this.type = ServerType.jellyfin,
    required this.serverUrl,
    required this.accessToken,
    this.userId = '',
    HttpClientAdapter? httpClientAdapter,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: _apiBase(serverUrl, type),
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    if (httpClientAdapter != null) _dio.httpClientAdapter = httpClientAdapter;
    // Library requests fall back to their last good answer when the server
    // cannot be reached, which is what makes offline browsing work.
    _dio.interceptors.add(OfflineCacheInterceptor(userId));
  }

  /// The address API paths are added to. Emby serves its API under `/emby`.
  static String _apiBase(String serverUrl, ServerType type) {
    final base = MusicService.normalizeUrl(serverUrl);
    return type == ServerType.emby ? '${base}emby/' : base;
  }

  /// [_apiBase] without the trailing slash, for building URLs by hand.
  String get _root {
    final base = _apiBase(serverUrl, type);
    return base.substring(0, base.length - 1);
  }

  /// Options for requests that must always reflect the server right now.
  Options get _liveOptions => Options(
        headers: _headers,
        extra: const {OfflineCacheInterceptor.skip: true},
      );

  // ---------------------------------------------------------------------------
  // Auth header
  // ---------------------------------------------------------------------------

  /// Device id used by installs that signed in before ids became per-install.
  static const legacyDeviceId = 'riffhouseplayer';

  /// Identifies this install to the server. Jellyfin signs a device's other
  /// users out when someone new signs in with the same id, so every install
  /// needs its own; `main()` loads it before the first request.
  static String deviceId = legacyDeviceId;

  /// Reported to the server; set from the package version at startup.
  static String appVersion = '1.0.0';

  static String _authorization([String? token]) {
    final platform = defaultTargetPlatform.name;
    final device = '${platform[0].toUpperCase()}${platform.substring(1)}';
    return 'MediaBrowser Client="Riffhouse", '
        'Device="$device", '
        'DeviceId="$deviceId", '
        'Version="$appVersion"'
        '${token == null ? '' : ', Token="$token"'}';
  }

  /// MediaBrowser authorization header value.
  String get _authHeader => _authorization(accessToken);

  Map<String, String> get _headers => {
        'X-Emby-Authorization': _authHeader,
      };

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  /// Authenticates against a Jellyfin or Emby server.
  ///
  /// Throws a [LoginException] saying what went wrong if it fails.
  static Future<JellyfinUser> authenticate(
    String serverUrl,
    String username,
    String password, {
    ServerType type = ServerType.jellyfin,
  }) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: _apiBase(serverUrl, type),
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Emby-Authorization': _authorization(),
        },
      ),
    );

    try {
      final response = await dio.post(
        'Users/AuthenticateByName',
        data: {
          'Username': username,
          'Pw': password,
        },
      );

      final data = response.data;
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        final user = JellyfinUser.fromJson(data);
        if (user.id.isNotEmpty && user.accessToken.isNotEmpty) return user;
      }
      throw const LoginException(LoginFailure.wrongServerType);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == null) {
        throw const LoginException(LoginFailure.unreachable);
      }
      throw LoginException(status == 401 || status == 403
          ? LoginFailure.invalidCredentials
          : LoginFailure.wrongServerType);
    } on LoginException {
      rethrow;
    } catch (_) {
      throw const LoginException(LoginFailure.wrongServerType);
    }
  }

  /// Checks the stored access token with a cheap request. Only an explicit
  /// rejection counts as [SessionStatus.unauthorized]; being offline must
  /// never sign the user out.
  @override
  Future<SessionStatus> checkSession() async {
    try {
      final response = await _dio.get(
        'Users/$userId',
        options: _liveOptions,
      );
      return response.statusCode == 200
          ? SessionStatus.valid
          : SessionStatus.unreachable;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      return status == 401 || status == 403
          ? SessionStatus.unauthorized
          : SessionStatus.unreachable;
    } catch (_) {
      return SessionStatus.unreachable;
    }
  }

  // ---------------------------------------------------------------------------
  // Tracks
  // ---------------------------------------------------------------------------

  /// Fetches ALL audio tracks for the authenticated user, paginating through
  /// the full library in batches of 500 to avoid the server's default cap.
  ///
  /// If a request fails part-way the tracks fetched so far are returned,
  /// unless [throwOnError] is set. Callers that treat the result as the whole
  /// library (to remove tracks that are gone) must set it.
  @override
  Future<List<JellyfinTrack>> getTracks({bool throwOnError = false}) async {
    const batchSize = 500;
    final allTracks = <JellyfinTrack>[];
    int startIndex = 0;
    int? totalCount;

    logDebug('[JellyfinService.getTracks] Starting fetch. baseUrl=${_dio.options.baseUrl}, userId=$userId');
    try {
      do {
        final response = await _dio.get(
          'Users/$userId/Items',
          queryParameters: {
            'IncludeItemTypes': 'Audio',
            'Fields': 'Artists,AlbumArtist,Genres,MediaSources,AlbumId,DateCreated',
            'Recursive': true,
            'Limit': batchSize,
            'StartIndex': startIndex,
          },
          options: _liveOptions,
        );

        totalCount ??= (response.data?['TotalRecordCount'] as int?) ?? 0;
        final items = (response.data?['Items'] as List?) ?? [];
        logDebug('[JellyfinService.getTracks] Page startIndex=$startIndex: got ${items.length} items, totalCount=$totalCount, statusCode=${response.statusCode}');
        allTracks.addAll(
          items.map((i) => JellyfinTrack.fromJson(i as Map<String, dynamic>)),
        );
        startIndex += items.length;
        if (items.isEmpty) break;
      } while (startIndex < totalCount);

      logDebug('[JellyfinService.getTracks] Done. Total tracks fetched: ${allTracks.length}');
      return allTracks;
    } on DioException catch (e) {
      logDebug('[JellyfinService.getTracks] DioException: ${e.type} ${e.message}, statusCode=${e.response?.statusCode}, data=${e.response?.data}');
      if (throwOnError) rethrow;
      return allTracks; // return whatever we got before the error
    }
  }

  @override
  Future<List<JellyfinTrack>> fetchNewTracks(
    Future<bool> Function(String trackId) isKnown,
  ) async {
    const batchSize = 200;
    var startIndex = 0;
    final newTracks = <JellyfinTrack>[];

    while (true) {
      final page = await getTracksPaged(
        startIndex: startIndex,
        limit: batchSize,
        sortBy: 'DateCreated',
        sortOrder: 'Descending',
      );
      if (page.isEmpty) break;

      for (final track in page) {
        // Newest first, so the first known track ends the search.
        if (await isKnown(track.id)) return newTracks;
        newTracks.add(track);
      }

      if (page.length < batchSize) break;
      startIndex += page.length;
    }
    return newTracks;
  }

  /// Fetches a single page of audio tracks.
  Future<List<JellyfinTrack>> getTracksPaged({
    required int startIndex,
    required int limit,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      final queryParams = {
        'IncludeItemTypes': 'Audio',
        'Fields': 'Artists,AlbumArtist,Genres,MediaSources,AlbumId,DateCreated',
        'Recursive': true,
        'Limit': limit,
        'StartIndex': startIndex,
      };
      if (sortBy != null) {
        queryParams['SortBy'] = sortBy;
      }
      if (sortOrder != null) {
        queryParams['SortOrder'] = sortOrder;
      }

      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: queryParams,
        options: _liveOptions,
      );

      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinTrack.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Server-side search  (fast — no full preload needed)
  // ---------------------------------------------------------------------------

  /// Searches for audio tracks matching [query] on the server.
  @override
  Future<List<JellyfinTrack>> searchTracks(String query, {int limit = 50}) async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'SearchTerm': query,
          'IncludeItemTypes': 'Audio',
          'Fields': 'Artists,AlbumArtist,Genres,MediaSources,AlbumId',
          'Recursive': true,
          'Limit': limit,
          'ImageTypeLimit': 1,
          'EnableTotalRecordCount': false,
        },
        options: _liveOptions,
      );
      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinTrack.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (_) {
      return [];
    }
  }

  /// Searches for albums matching [query] on the server.
  @override
  Future<List<JellyfinAlbum>> searchAlbums(String query, {int limit = 20}) async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'SearchTerm': query,
          'IncludeItemTypes': 'MusicAlbum',
          'Fields': 'ChildCount',
          'Recursive': true,
          'Limit': limit,
          'ImageTypeLimit': 1,
          'EnableTotalRecordCount': false,
        },
        options: _liveOptions,
      );
      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinAlbum.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (_) {
      return [];
    }
  }

  /// Searches for artists matching [query] on the server.
  @override
  Future<List<JellyfinArtist>> searchArtists(String query, {int limit = 10}) async {
    try {
      final response = await _dio.get(
        'Artists',
        queryParameters: {
          'SearchTerm': query,
          'UserId': userId,
          'Fields': 'Overview',
          'Limit': limit,
          'ImageTypeLimit': 1,
          'EnableTotalRecordCount': false,
        },
        options: _liveOptions,
      );
      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinArtist.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Albums
  // ---------------------------------------------------------------------------

  /// Fetches all music albums for the authenticated user.
  @override
  Future<List<JellyfinAlbum>> getAlbums() async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'IncludeItemTypes': 'MusicAlbum',
          'Fields': 'ChildCount,DateCreated,Genres',
          'Recursive': true,
        },
        options: Options(headers: _headers),
      );

      final items = (response.data?['Items'] as List?) ?? [];
      return items
          .map((i) => JellyfinAlbum.fromJson(i as Map<String, dynamic>))
          .toList();
    } on DioException catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Artists
  // ---------------------------------------------------------------------------

  /// Fetches album artists from the Jellyfin server.
  @override
  Future<List<JellyfinArtist>> getArtists() async {
    try {
      final response = await _dio.get(
        'Artists/AlbumArtists',
        queryParameters: {
          'UserId': userId,
          'Fields': 'Overview',
        },
        options: Options(headers: _headers),
      );

      final items = (response.data?['Items'] as List?) ?? [];
      return items
          .map((i) => JellyfinArtist.fromJson(i as Map<String, dynamic>))
          .toList();
    } on DioException catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Playlists
  // ---------------------------------------------------------------------------

  /// Fetches all playlists visible to the authenticated user.
  @override
  Future<List<JellyfinPlaylist>> getPlaylists() async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'IncludeItemTypes': 'Playlist',
          'Fields': 'ChildCount',
          'Recursive': true,
        },
        options: Options(headers: _headers),
      );

      final items = (response.data?['Items'] as List?) ?? [];
      final directList = items
          .map((i) => JellyfinPlaylist.fromJson(i as Map<String, dynamic>))
          .toList();

      if (directList.isNotEmpty) return directList;

      // Fallback: If recursive search returns empty, check for virtual 'Playlists' UserView
      try {
        final viewsResp = await _dio.get(
          'Users/$userId/Views',
          options: Options(headers: _headers),
        );
        final views = (viewsResp.data?['Items'] as List?) ?? [];
        for (final v in views) {
          final cType = (v['CollectionType'] as String?)?.toLowerCase();
          final name = (v['Name'] as String?)?.toLowerCase();
          if (cType == 'playlists' || name == 'playlists') {
            final folderId = v['Id'] as String?;
            if (folderId != null) {
              final folderResp = await _dio.get(
                'Users/$userId/Items',
                queryParameters: {
                  'ParentId': folderId,
                  'Fields': 'ChildCount',
                },
                options: Options(headers: _headers),
              );
              final folderItems = (folderResp.data?['Items'] as List?) ?? [];
              final folderList = folderItems
                  .map((i) => JellyfinPlaylist.fromJson(i as Map<String, dynamic>))
                  .toList();
              if (folderList.isNotEmpty) return folderList;
            }
          }
        }
      } catch (_) {}

      return directList;
    } on DioException catch (_) {
      return [];
    }
  }

  /// Fetches tracks contained within a specific playlist.
  @override
  Future<List<JellyfinTrack>> getPlaylistTracks(
    String playlistId, {
    bool throwOnError = false,
  }) async {
    try {
      final response = await _dio.get(
        'Playlists/$playlistId/Items',
        queryParameters: {
          'UserId': userId,
          'Fields': 'Artists,AlbumArtist,Genres,MediaSources,AlbumId,ImageTags',
        },
        options: Options(headers: _headers),
      );

      final items = (response.data?['Items'] as List?) ?? [];
      return items
          .map((i) => JellyfinTrack.fromJson(i as Map<String, dynamic>))
          .toList();
    } on DioException catch (_) {
      if (throwOnError) rethrow;
      return [];
    }
  }

  @override
  Future<Set<String>?> getFavoriteTrackIds() async {
    const batchSize = 1000;
    final ids = <String>{};
    try {
      while (true) {
        final response = await _dio.get(
          'Users/$userId/Items',
          queryParameters: {
            'Filters': 'IsFavorite',
            'IncludeItemTypes': 'Audio',
            'Recursive': true,
            'EnableImages': false,
            'EnableUserData': false,
            'Limit': batchSize,
            'StartIndex': ids.length,
          },
          options: _liveOptions,
        );
        final items = (response.data?['Items'] as List?) ?? [];
        final before = ids.length;
        ids.addAll(items
            .whereType<Map>()
            .map((i) => i['Id'])
            .whereType<String>());
        if (items.length < batchSize || ids.length == before) return ids;
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> setFavorite(String trackId, bool favorite) async {
    try {
      final path = 'Users/$userId/FavoriteItems/$trackId';
      final options = Options(headers: _headers);
      if (favorite) {
        await _dio.post(path, options: options);
      } else {
        await _dio.delete(path, options: options);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Jellyfin reads an ISO 8601 date; Emby wants `yyyyMMddHHmmss`.
  String _datePlayed(DateTime playedAt) {
    final utc = playedAt.toUtc();
    if (type != ServerType.emby) return utc.toIso8601String();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}${two(utc.day)}'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
  }

  /// Tells the server that [itemId] was played at [playedAt], which raises
  /// its play count and sets its "last played" date for this user.
  @override
  Future<ReportResult> markPlayed(String itemId, DateTime playedAt) async {
    try {
      await _dio.post(
        'Users/$userId/PlayedItems/$itemId',
        queryParameters: {'DatePlayed': _datePlayed(playedAt)},
        options: Options(headers: _headers),
      );
      return ReportResult.sent;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // No answer, a server fault or an expired sign-in can all recover.
      if (status == null || status >= 500 || status == 401 || status == 403) {
        return ReportResult.unreachable;
      }
      return ReportResult.rejected;
    } catch (_) {
      return ReportResult.unreachable;
    }
  }

  /// Fetches details for a single track.
  @override
  Future<JellyfinTrack?> getTrack(String trackId) async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items/$trackId',
        options: Options(headers: _headers),
      );
      if (response.data != null) {
        return JellyfinTrack.fromJson(response.data as Map<String, dynamic>);
      }
    } on DioException catch (_) {
    }
    return null;
  }

  /// Fetches tracks contained within a specific album.
  @override
  Future<List<JellyfinTrack>> getAlbumTracks(String albumId) async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'ParentId': albumId,
          'IncludeItemTypes': 'Audio',
          'Fields': 'Artists,AlbumArtist,Genres,MediaSources,AlbumId,ImageTags',
          'Recursive': true,
        },
        options: Options(headers: _headers),
      );

      final items = (response.data?['Items'] as List?) ?? [];
      return items
          .map((i) => JellyfinTrack.fromJson(i as Map<String, dynamic>))
          .toList();
    } on DioException catch (_) {
      return [];
    }
  }

  /// Fetches albums belonging to a specific artist.
  @override
  Future<List<JellyfinAlbum>> getArtistAlbums(String artistId) async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'ArtistIds': artistId,
          'IncludeItemTypes': 'MusicAlbum',
          'Recursive': true,
        },
        options: Options(headers: _headers),
      );

      final items = (response.data?['Items'] as List?) ?? [];
      return items
          .map((i) => JellyfinAlbum.fromJson(i as Map<String, dynamic>))
          .toList();
    } on DioException catch (_) {
      return [];
    }
  }

  /// Fetches tracks belonging to a specific artist.
  @override
  Future<List<JellyfinTrack>> getArtistTracks(String artistId) async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'ArtistIds': artistId,
          'IncludeItemTypes': 'Audio',
          'Fields': 'Artists,AlbumArtist,Genres,MediaSources,AlbumId',
          'Recursive': true,
          'Limit': 20,
        },
        options: Options(headers: _headers),
      );

      final items = (response.data?['Items'] as List?) ?? [];
      return items
          .map((i) => JellyfinTrack.fromJson(i as Map<String, dynamic>))
          .toList();
    } on DioException catch (_) {
      return [];
    }
  }

  /// Creates a new playlist on the server.
  ///
  /// Returns the newly created playlist's ID on success, or `null`.
  @override
  Future<String?> createPlaylist(String name, List<String> trackIds) async {
    try {
      final queryParams = <String, dynamic>{
        'Name': name,
        'name': name,
        'UserId': userId,
        'userId': userId,
      };
      if (trackIds.isNotEmpty) {
        queryParams['Ids'] = trackIds.join(',');
        queryParams['ids'] = trackIds.join(',');
      }

      final response = await _dio.post(
        'Playlists',
        queryParameters: queryParams,
        data: {
          'Name': name,
          'Ids': trackIds,
          'UserId': userId,
        },
        options: Options(headers: _headers),
      );

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data != null) {
        final data = response.data;
        if (data is Map) {
          return (data['Id'] ?? data['id']) as String?;
        } else if (data is String && data.isNotEmpty) {
          return data;
        }
      }
      return null;
    } on DioException catch (_) {
      return null;
    }
  }

  /// Adds a track to an existing playlist on the server.
  @override
  Future<bool> addTrackToPlaylist(String playlistId, String trackId) async {
    try {
      final response = await _dio.post(
        'Playlists/$playlistId/Items',
        queryParameters: {
          'Ids': trackId,
          'ids': trackId,
          'UserId': userId,
          'userId': userId,
        },
        options: Options(headers: _headers),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (_) {
      return false;
    }
  }

  /// Removes a track from an existing playlist on the server.
  @override
  Future<bool> removeTrackFromPlaylist(String playlistId, String trackId) async {
    try {
      final response = await _dio.delete(
        'Playlists/$playlistId/Items',
        queryParameters: {
          'EntryIds': trackId,
          'entryIds': trackId,
          'Ids': trackId,
          'ids': trackId,
          'UserId': userId,
        },
        options: Options(headers: _headers),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (_) {
      return false;
    }
  }

  /// Uploads a custom primary image for an item (e.g. playlist).
  @override
  Future<bool> uploadItemImage(String itemId, List<int> imageBytes, String mimeType) async {
    try {
      final base64String = base64Encode(imageBytes);
      final response = await _dio.post(
        'Items/$itemId/Images/Primary',
        data: base64String,
        options: Options(
          headers: {
            ..._headers,
            'Content-Type': mimeType,
          },
        ),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (_) {
      return false;
    }
  }

  /// Deletes a playlist from the server.
  @override
  Future<bool> deletePlaylist(String playlistId) async {
    try {
      final response = await _dio.delete(
        'Items/$playlistId',
        options: Options(headers: _headers),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // URL Builders
  // ---------------------------------------------------------------------------

  /// Returns the streaming URL for a given track ID.
  @override
  String getStreamUrl(String trackId) =>
      '$_root/Audio/$trackId/stream?static=true&api_key=$accessToken';

  /// Returns the primary image URL for an item (includes api_key for unauthenticated fetchers like Android Auto).
  @override
  String getImageUrl(String itemId, String imageTag) =>
      '$_root/Items/$itemId/Images/Primary?tag=$imageTag&api_key=$accessToken';

  /// Returns the primary album art URL for an album (includes api_key for unauthenticated fetchers like Android Auto).
  @override
  String getAlbumArtUrl(String albumId) =>
      '$_root/Items/$albumId/Images/Primary?api_key=$accessToken';

  /// When [imageTag] is provided it is appended for cache-busting and makes
  /// sure the right image variant is fetched.
  @override
  String artworkUrl(String itemId, {String? imageTag}) {
    final tag =
        (imageTag != null && imageTag.isNotEmpty) ? '&tag=$imageTag' : '';
    return '$_root/Items/$itemId/Images/Primary?api_key=$accessToken$tag';
  }

  // ---------------------------------------------------------------------------
  // Recently played / New content
  // ---------------------------------------------------------------------------

  /// Fetches recently-played albums sorted by last play date.
  @override
  Future<List<JellyfinAlbum>> getRecentAlbums({int limit = 12}) async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'IncludeItemTypes': 'MusicAlbum',
          'SortBy': 'DatePlayed',
          'SortOrder': 'Descending',
          'Filters': 'IsPlayed',
          'Fields': 'ChildCount',
          'Recursive': true,
          'Limit': limit,
        },
        options: Options(headers: _headers),
      );
      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinAlbum.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (_) {
      return [];
    }
  }

  /// Fetches recently-played artists sorted by last play date.
  @override
  Future<List<JellyfinArtist>> getRecentArtists({int limit = 10}) async {
    try {
      final response = await _dio.get(
        'Artists/AlbumArtists',
        queryParameters: {
          'UserId': userId,
          'SortBy': 'DatePlayed',
          'SortOrder': 'Descending',
          'Filters': 'IsPlayed',
          'Limit': limit,
        },
        options: Options(headers: _headers),
      );
      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinArtist.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (_) {
      return [];
    }
  }

  /// Fetches recently-played playlists.
  @override
  Future<List<JellyfinPlaylist>> getRecentPlaylists({int limit = 6}) async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'IncludeItemTypes': 'Playlist',
          'SortBy': 'DatePlayed',
          'SortOrder': 'Descending',
          'Filters': 'IsPlayed',
          'Fields': 'ChildCount',
          'Recursive': true,
          'Limit': limit,
        },
        options: Options(headers: _headers),
      );
      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinPlaylist.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (_) {
      return [];
    }
  }

  /// Fetches recently-added albums that the user hasn't played yet (New For You).
  @override
  Future<List<JellyfinAlbum>> getNewAlbums({int limit = 12}) async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'IncludeItemTypes': 'MusicAlbum',
          'SortBy': 'DateCreated',
          'SortOrder': 'Descending',
          'Filters': 'IsUnplayed',
          'Fields': 'ChildCount,DateCreated,Genres',
          'Recursive': true,
          'Limit': limit,
        },
        options: Options(headers: _headers),
      );
      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinAlbum.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (_) {
      return [];
    }
  }

  /// Search for tracks, albums, and artists matching [query].
  @override
  Future<Map<String, dynamic>> search(String query) async {
    try {
      final tracksResp = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'SearchTerm': query,
          'IncludeItemTypes': 'Audio',
          'Fields': 'Artists,AlbumArtist,Genres,MediaSources,AlbumId',
          'Recursive': true,
          'Limit': 20,
        },
        options: _liveOptions,
      );
      final albumsResp = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'SearchTerm': query,
          'IncludeItemTypes': 'MusicAlbum',
          'Fields': 'ChildCount',
          'Recursive': true,
          'Limit': 10,
        },
        options: _liveOptions,
      );
      final tracks = ((tracksResp.data?['Items'] as List?) ?? [])
          .map((i) => JellyfinTrack.fromJson(i as Map<String, dynamic>))
          .toList();
      final albums = ((albumsResp.data?['Items'] as List?) ?? [])
          .map((i) => JellyfinAlbum.fromJson(i as Map<String, dynamic>))
          .toList();
      return {'tracks': tracks, 'albums': albums};
    } on DioException catch (_) {
      return {'tracks': <JellyfinTrack>[], 'albums': <JellyfinAlbum>[]};
    }
  }
}
