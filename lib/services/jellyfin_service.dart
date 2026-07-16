import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import '../models/jellyfin_models.dart';

/// Wraps the Jellyfin REST API.
///
/// Construct with [serverUrl] and [accessToken] after authenticating.
/// Use the static [authenticate] method to obtain credentials.
class JellyfinService {
  final String serverUrl;
  final String accessToken;

  /// Jellyfin user ID of the authenticated user. Set by [authenticate].
  String userId;

  late final Dio _dio;

  JellyfinService({
    required this.serverUrl,
    required this.accessToken,
    this.userId = '',
  }) {
    String baseUrl = serverUrl.trim();
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'http://$baseUrl';
    }
    if (!baseUrl.endsWith('/')) {
      baseUrl = '$baseUrl/';
    }

    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Auth header
  // ---------------------------------------------------------------------------

  /// MediaBrowser authorization header value.
  String get _authHeader =>
      'MediaBrowser Client="Riffhouse", '
      'Device="Mobile", '
      'DeviceId="riffhouseplayer", '
      'Version="1.0.0", '
      'Token="$accessToken"';

  Map<String, String> get _headers => {
        'X-Emby-Authorization': _authHeader,
      };

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  /// Authenticates against a Jellyfin server.
  ///
  /// Returns a [JellyfinUser] on success, or `null` if authentication fails.
  static Future<JellyfinUser?> authenticate(
    String serverUrl,
    String username,
    String password,
  ) async {
    // Auto-prepend http:// if scheme is missing
    String baseUrl = serverUrl.trim();
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'http://$baseUrl';
    }

    if (!baseUrl.endsWith('/')) {
      baseUrl = '$baseUrl/';
    }

    print('Attempting Jellyfin authentication at: ${baseUrl}Users/AuthenticateByName');

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Emby-Authorization':
              'MediaBrowser Client="Riffhouse", Device="Mobile", '
              'DeviceId="riffhouseplayer", Version="1.0.0"',
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

      if (response.statusCode == 200 && response.data != null) {
        final rawData = response.data as Map<String, dynamic>;
        print('Jellyfin auth success for user: ${rawData['User']?['Name']}');
        return JellyfinUser.fromJson(rawData);
      }
      print('Jellyfin auth failed with status code: ${response.statusCode}');
      return null;
    } on DioException catch (e) {
      print('Jellyfin auth failed: ${e.message}');
      if (e.response != null) {
        print('Jellyfin auth error response status: ${e.response?.statusCode}');
        print('Jellyfin auth error response body: ${e.response?.data}');
      }
      return null;
    } catch (e) {
      print('Unexpected Jellyfin auth error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Tracks
  // ---------------------------------------------------------------------------

  /// Fetches ALL audio tracks for the authenticated user, paginating through
  /// the full library in batches of 500 to avoid the server's default cap.
  Future<List<JellyfinTrack>> getTracks() async {
    const batchSize = 500;
    final allTracks = <JellyfinTrack>[];
    int startIndex = 0;
    int? totalCount;

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
          options: Options(headers: _headers),
        );

        totalCount ??= (response.data?['TotalRecordCount'] as int?) ?? 0;
        final items = (response.data?['Items'] as List?) ?? [];
        allTracks.addAll(
          items.map((i) => JellyfinTrack.fromJson(i as Map<String, dynamic>)),
        );
        startIndex += items.length;
        if (items.isEmpty) break;
      } while (startIndex < (totalCount ?? 0));

      return allTracks;
    } on DioException catch (e) {
      print('getTracks failed: ${e.message}');
      return allTracks; // return whatever we got before the error
    }
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
        options: Options(headers: _headers),
      );

      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinTrack.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      print('getTracksPaged failed: ${e.message}');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Server-side search  (fast — no full preload needed)
  // ---------------------------------------------------------------------------

  /// Searches for audio tracks matching [query] on the server.
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
        options: Options(headers: _headers),
      );
      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinTrack.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      print('searchTracks failed: ${e.message}');
      return [];
    }
  }

  /// Searches for albums matching [query] on the server.
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
        options: Options(headers: _headers),
      );
      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinAlbum.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      print('searchAlbums failed: ${e.message}');
      return [];
    }
  }

  /// Searches for artists matching [query] on the server.
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
        options: Options(headers: _headers),
      );
      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinArtist.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      print('searchArtists failed: ${e.message}');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Albums
  // ---------------------------------------------------------------------------

  /// Fetches all music albums for the authenticated user.
  Future<List<JellyfinAlbum>> getAlbums() async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'IncludeItemTypes': 'MusicAlbum',
          'Fields': 'ChildCount',
          'Recursive': true,
        },
        options: Options(headers: _headers),
      );

      final items = (response.data?['Items'] as List?) ?? [];
      return items
          .map((i) => JellyfinAlbum.fromJson(i as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      print('getAlbums failed: ${e.message}');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Artists
  // ---------------------------------------------------------------------------

  /// Fetches album artists from the Jellyfin server.
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
    } on DioException catch (e) {
      print('getArtists failed: ${e.message}');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Playlists
  // ---------------------------------------------------------------------------

  /// Fetches all playlists visible to the authenticated user.
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
      return items
          .map((i) => JellyfinPlaylist.fromJson(i as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      print('getPlaylists failed: ${e.message}');
      return [];
    }
  }

  /// Fetches tracks contained within a specific playlist.
  Future<List<JellyfinTrack>> getPlaylistTracks(String playlistId) async {
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
    } on DioException catch (e) {
      print('getPlaylistTracks failed: ${e.message}');
      return [];
    }
  }

  /// Fetches details for a single track.
  Future<JellyfinTrack?> getTrack(String trackId) async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items/$trackId',
        options: Options(headers: _headers),
      );
      if (response.data != null) {
        return JellyfinTrack.fromJson(response.data as Map<String, dynamic>);
      }
    } on DioException catch (e) {
      print('getTrack failed: ${e.message}');
    }
    return null;
  }

  /// Fetches tracks contained within a specific album.
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
    } on DioException catch (e) {
      print('getAlbumTracks failed: ${e.message}');
      return [];
    }
  }

  /// Fetches albums belonging to a specific artist.
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
    } on DioException catch (e) {
      print('getArtistAlbums failed: ${e.message}');
      return [];
    }
  }

  /// Fetches tracks belonging to a specific artist.
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
    } on DioException catch (e) {
      print('getArtistTracks failed: ${e.message}');
      return [];
    }
  }

  /// Creates a new playlist on the server.
  ///
  /// Returns the newly created playlist's ID on success, or `null`.
  Future<String?> createPlaylist(String name, List<String> trackIds) async {
    try {
      final response = await _dio.post(
        'Playlists',
        queryParameters: {
          'Name': name,
          'Ids': trackIds.join(','),
          'UserId': userId,
        },
        options: Options(headers: _headers),
      );

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data != null) {
        return response.data['Id'] as String?;
      }
      return null;
    } on DioException catch (e) {
      print('createPlaylist failed: ${e.message}');
      return null;
    }
  }

  /// Adds a track to an existing playlist on the server.
  Future<bool> addTrackToPlaylist(String playlistId, String trackId) async {
    try {
      final response = await _dio.post(
        'Playlists/$playlistId/Items',
        queryParameters: {
          'Ids': trackId,
          'UserId': userId,
        },
        options: Options(headers: _headers),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (e) {
      print('addTrackToPlaylist failed: ${e.message}');
      return false;
    }
  }

  /// Uploads a custom primary image for an item (e.g. playlist).
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
    } on DioException catch (e) {
      print('uploadItemImage failed: ${e.message}');
      return false;
    }
  }

  /// Deletes a playlist from the server.
  Future<bool> deletePlaylist(String playlistId) async {
    try {
      final response = await _dio.delete(
        'Items/$playlistId',
        options: Options(headers: _headers),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (e) {
      print('deletePlaylist failed: ${e.message}');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // URL Builders
  // ---------------------------------------------------------------------------

  /// Returns the streaming URL for a given track ID.
  String getStreamUrl(String trackId) {
    final cleanBase = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    return '$cleanBase/Audio/$trackId/stream?static=true&api_key=$accessToken';
  }

  /// Returns the primary image URL for an item (includes api_key for unauthenticated fetchers like Android Auto).
  String getImageUrl(String itemId, String imageTag) {
    final cleanBase = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    return '$cleanBase/Items/$itemId/Images/Primary?tag=$imageTag&api_key=$accessToken';
  }

  /// Returns the primary album art URL for an album (includes api_key for unauthenticated fetchers like Android Auto).
  String getAlbumArtUrl(String albumId) {
    final cleanBase = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    return '$cleanBase/Items/$albumId/Images/Primary?api_key=$accessToken';
  }

  // ---------------------------------------------------------------------------
  // Recently played / New content
  // ---------------------------------------------------------------------------

  /// Fetches recently-played albums sorted by last play date.
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
    } on DioException catch (e) {
      print('getRecentAlbums failed: ${e.message}');
      return [];
    }
  }

  /// Fetches recently-played artists sorted by last play date.
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
    } on DioException catch (e) {
      print('getRecentArtists failed: ${e.message}');
      return [];
    }
  }

  /// Fetches recently-played playlists.
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
    } on DioException catch (e) {
      print('getRecentPlaylists failed: ${e.message}');
      return [];
    }
  }

  /// Fetches recently-added albums that the user hasn't played yet (New For You).
  Future<List<JellyfinAlbum>> getNewAlbums({int limit = 12}) async {
    try {
      final response = await _dio.get(
        'Users/$userId/Items',
        queryParameters: {
          'IncludeItemTypes': 'MusicAlbum',
          'SortBy': 'DateCreated',
          'SortOrder': 'Descending',
          'Filters': 'IsUnplayed',
          'Fields': 'ChildCount',
          'Recursive': true,
          'Limit': limit,
        },
        options: Options(headers: _headers),
      );
      final items = (response.data?['Items'] as List?) ?? [];
      return items.map((i) => JellyfinAlbum.fromJson(i as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      print('getNewAlbums failed: ${e.message}');
      return [];
    }
  }

  /// Search for tracks, albums, and artists matching [query].
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
        options: Options(headers: _headers),
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
        options: Options(headers: _headers),
      );
      final tracks = ((tracksResp.data?['Items'] as List?) ?? [])
          .map((i) => JellyfinTrack.fromJson(i as Map<String, dynamic>))
          .toList();
      final albums = ((albumsResp.data?['Items'] as List?) ?? [])
          .map((i) => JellyfinAlbum.fromJson(i as Map<String, dynamic>))
          .toList();
      return {'tracks': tracks, 'albums': albums};
    } on DioException catch (e) {
      print('search failed: ${e.message}');
      return {'tracks': <JellyfinTrack>[], 'albums': <JellyfinAlbum>[]};
    }
  }
}
