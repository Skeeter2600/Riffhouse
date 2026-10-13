import '../models/jellyfin_models.dart';
import 'jellyfin_service.dart';
import 'subsonic_service.dart';

/// The kinds of server Riffhouse can connect to.
enum ServerType {
  jellyfin('jellyfin', 'Jellyfin', 'http://192.168.1.100:8096'),
  emby('emby', 'Emby', 'http://192.168.1.100:8096'),

  /// Anything speaking the Subsonic API: Navidrome, Gonic, Airsonic, LMS,
  /// Ampache, Funkwhale, Nextcloud Music and other OpenSubsonic servers.
  subsonic('subsonic', 'Navidrome / Subsonic', 'http://192.168.1.100:4533');

  /// Value stored with the saved sign-in.
  final String id;

  /// Name shown to the user.
  final String label;

  /// Example address, with the server's usual port.
  final String urlHint;

  const ServerType(this.id, this.label, this.urlHint);

  /// Sign-ins saved before other servers were supported have no type and
  /// are Jellyfin.
  static ServerType fromId(String? id) =>
      values.firstWhere((t) => t.id == id, orElse: () => jellyfin);
}

/// Result of checking a stored sign-in against the server.
enum SessionStatus {
  valid,

  /// The server rejected the sign-in; the user has to sign in again.
  unauthorized,

  /// The server could not be reached (offline, server down, timeout). The
  /// sign-in may well still be good.
  unreachable,
}

/// Outcome of sending a play to the server.
enum ReportResult {
  sent,

  /// The server answered and refused it for good (e.g. the track is gone).
  rejected,

  /// The server could not be reached or the sign-in has expired; try later.
  unreachable,
}

/// Why signing in did not work.
enum LoginFailure {
  invalidCredentials,
  unreachable,

  /// Something answered at that address, but not the chosen kind of server.
  wrongServerType,
}

class LoginException implements Exception {
  final LoginFailure failure;
  const LoginException(this.failure);
}

/// A music server the app can browse, stream from and report plays to.
///
/// Everything outside `lib/services` talks to this interface, so the screens,
/// the player and Android Auto work the same whichever server is behind it.
/// Read methods return an empty result when the server cannot be reached,
/// unless they take `throwOnError`.
abstract class MusicService {
  ServerType get type;
  String get serverUrl;

  /// The stored credential. What it holds depends on the server type; an
  /// empty value means "not signed in".
  String get accessToken;

  /// The signed-in user (an id or, for Subsonic servers, the user name).
  String get userId;

  bool get isSignedIn => accessToken.isNotEmpty;

  // ---- Session -------------------------------------------------------------

  /// Checks the stored sign-in with a cheap request. Only an explicit
  /// rejection counts as [SessionStatus.unauthorized]; being offline must
  /// never sign the user out.
  Future<SessionStatus> checkSession();

  // ---- Library -------------------------------------------------------------

  /// Fetches every track in the library.
  ///
  /// If a request fails part-way the tracks fetched so far are returned,
  /// unless [throwOnError] is set. Callers that treat the result as the whole
  /// library (to remove tracks that are gone) must set it.
  Future<List<JellyfinTrack>> getTracks({bool throwOnError = false});

  /// Fetches tracks added to the server since the last sync: newest first,
  /// stopping once it reaches tracks [isKnown] already has.
  Future<List<JellyfinTrack>> fetchNewTracks(
    Future<bool> Function(String trackId) isKnown,
  );

  Future<List<JellyfinAlbum>> getAlbums();
  Future<List<JellyfinArtist>> getArtists();
  Future<List<JellyfinPlaylist>> getPlaylists();
  Future<List<JellyfinTrack>> getPlaylistTracks(
    String playlistId, {
    bool throwOnError = false,
  });
  Future<JellyfinTrack?> getTrack(String trackId);
  Future<List<JellyfinTrack>> getAlbumTracks(String albumId);
  Future<List<JellyfinAlbum>> getArtistAlbums(String artistId);
  Future<List<JellyfinTrack>> getArtistTracks(String artistId);

  Future<List<JellyfinAlbum>> getRecentAlbums({int limit = 12});
  Future<List<JellyfinArtist>> getRecentArtists({int limit = 10});
  Future<List<JellyfinPlaylist>> getRecentPlaylists({int limit = 6});
  Future<List<JellyfinAlbum>> getNewAlbums({int limit = 12});

  // ---- Search --------------------------------------------------------------

  Future<List<JellyfinTrack>> searchTracks(String query, {int limit = 50});
  Future<List<JellyfinAlbum>> searchAlbums(String query, {int limit = 20});
  Future<List<JellyfinArtist>> searchArtists(String query, {int limit = 10});

  /// Tracks and albums matching [query], under the keys `tracks` and `albums`.
  Future<Map<String, dynamic>> search(String query);

  // ---- Playlists -----------------------------------------------------------

  /// Creates a playlist and returns its id, or null if that failed.
  Future<String?> createPlaylist(String name, List<String> trackIds);
  Future<bool> addTrackToPlaylist(String playlistId, String trackId);
  Future<bool> removeTrackFromPlaylist(String playlistId, String trackId);
  Future<bool> deletePlaylist(String playlistId);

  /// Whether [uploadItemImage] can work on this kind of server. Where it
  /// cannot, custom covers are kept on the device instead.
  bool get supportsCustomCovers => true;

  /// Sets a custom cover for an item. Not every server supports this.
  Future<bool> uploadItemImage(
      String itemId, List<int> imageBytes, String mimeType);

  // ---- Likes ---------------------------------------------------------------

  /// Ids of every track the user has liked ("favorite" on Jellyfin and Emby,
  /// "starred" on Subsonic), or null if the server could not be asked.
  Future<Set<String>?> getFavoriteTrackIds();

  /// Likes or unlikes a track on the server. Returns whether it worked.
  Future<bool> setFavorite(String trackId, bool favorite);

  // ---- Playback ------------------------------------------------------------

  /// Tells the server that [itemId] was played at [playedAt].
  Future<ReportResult> markPlayed(String itemId, DateTime playedAt);

  /// A URL the player (and downloads) can fetch the audio from without
  /// further headers.
  String getStreamUrl(String trackId);

  /// A URL for an item's artwork that needs no further headers, so Android
  /// Auto and the system media controls can load it. [imageTag] is the
  /// model's `imageTag`, when it has one.
  String artworkUrl(String itemId, {String? imageTag});

  String getImageUrl(String itemId, String imageTag) =>
      artworkUrl(itemId, imageTag: imageTag);

  String getAlbumArtUrl(String albumId) => artworkUrl(albumId);

  // ---- Construction --------------------------------------------------------

  /// Adds a scheme if the user left it out and makes sure the address ends
  /// with a slash.
  static String normalizeUrl(String serverUrl) {
    var url = serverUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url.endsWith('/') ? url : '$url/';
  }

  /// A service for a saved sign-in.
  static MusicService create({
    required ServerType type,
    required String serverUrl,
    required String accessToken,
    required String userId,
  }) {
    switch (type) {
      case ServerType.jellyfin:
      case ServerType.emby:
        return JellyfinService(
          type: type,
          serverUrl: serverUrl,
          accessToken: accessToken,
          userId: userId,
        );
      case ServerType.subsonic:
        return SubsonicService(
          serverUrl: serverUrl,
          accessToken: accessToken,
          userId: userId,
        );
    }
  }

  /// Placeholder used while nobody is signed in.
  static MusicService signedOut() => JellyfinService(
        serverUrl: 'http://localhost',
        accessToken: '',
        userId: '',
      );

  /// Signs in to a server of the given [type]. Throws a [LoginException]
  /// saying what went wrong if it fails.
  static Future<({MusicService service, JellyfinUser user})> signIn(
    ServerType type,
    String serverUrl,
    String username,
    String password,
  ) async {
    switch (type) {
      case ServerType.jellyfin:
      case ServerType.emby:
        final user = await JellyfinService.authenticate(
          serverUrl,
          username,
          password,
          type: type,
        );
        return (
          service: create(
            type: type,
            serverUrl: serverUrl,
            accessToken: user.accessToken,
            userId: user.id,
          ),
          user: user,
        );
      case ServerType.subsonic:
        return SubsonicService.signIn(serverUrl, username, password);
    }
  }
}
