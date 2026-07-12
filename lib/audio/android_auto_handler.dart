import 'package:audio_service/audio_service.dart';

import '../models/jellyfin_models.dart';
import '../providers/library_provider.dart';

// ---------------------------------------------------------------------------
// Root media IDs (public so the audio handler can reference them)
// ---------------------------------------------------------------------------

const String kRootHome = 'root_home';
const String kRootPlaylists = 'root_playlists';
const String kRootAlbums = 'root_albums';
const String kRootArtists = 'root_artists';
const String kRootSmartMixes = 'root_smart_mixes';

const String kPrefixPlaylist = 'playlist_';
const String kPrefixAlbum = 'album_';
const String kPrefixArtist = 'artist_';

/// Package name used to build android.resource:// URIs for bundled drawables.
const String _kPackage = 'com.riffhouse.mobile_music_player';

// ---------------------------------------------------------------------------
// Android Auto content-style constants
// https://developer.android.com/training/cars/media#apply-content-style
// ---------------------------------------------------------------------------

/// Set this to true on the root MediaItem extras to opt into content styling.
const String kContentStyleSupported =
    'android.media.browse.CONTENT_STYLE_SUPPORTED';

/// Hint applied to browsable (container) children of a node.
const String kContentStyleBrowsableHint =
    'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';

/// Hint applied to playable (leaf) children of a node.
const String kContentStylePlayableHint =
    'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';

/// Display as a grid of cards with large artwork.
const int kContentStyleGrid = 2;

/// Display as a list with smaller artwork on the left.
const int kContentStyleList = 1;

// Extras map reused by all browsable container nodes (shows children as grid)
const Map<String, dynamic> _kGridExtras = {
  kContentStyleSupported: true,
  kContentStyleBrowsableHint: kContentStyleGrid,
  kContentStylePlayableHint: kContentStyleList,
};

/// Extra used by Android Auto to display a MediaItem as a non-clickable section header.
const String kAndroidMediaBrowseHeader = 'android.media.browse.extra.HEADER';

const Map<String, dynamic> _kHeaderExtras = {
  kAndroidMediaBrowseHeader: true,
};

// Extras map for nodes whose children are tracks (list only)
const Map<String, dynamic> _kListExtras = {
  kContentStyleSupported: true,
  kContentStyleBrowsableHint: kContentStyleList,
  kContentStylePlayableHint: kContentStyleList,
};

// ---------------------------------------------------------------------------
// AndroidAutoHandler
// ---------------------------------------------------------------------------

/// Manages the MediaBrowser content tree exposed to Android Auto / Automotive OS.
///
/// Call [updateLibrary] whenever the Jellyfin library changes. Android Auto
/// will re-query [getChildren] to refresh its browse view.

class AndroidAutoHandler {
  List<JellyfinPlaylist> _playlists = [];
  List<JellyfinAlbum> _albums = [];
  List<JellyfinArtist> _artists = [];
  List<JellyfinTrack> _recentTracks = [];
  List<RecentlyPlayedItem> _recentlyPlayed = [];
  List<JellyfinAlbum> _newAlbums = [];

  /// Jellyfin server base URL and token — needed to build artwork URIs
  /// that Android Auto can fetch without a browser auth session.
  String serverUrl;
  String accessToken;

  /// Map of container id → track list.
  ///
  /// Keys follow the pattern `playlist_<id>` or `album_<id>`.
  Map<String, List<JellyfinTrack>> _tracksByContainer = {};

  /// Callback to get cached artwork local file path
  final String? Function(String remoteUrl) getCachedArtPath;

  /// Callback to request background download of artwork for a remote URL
  final void Function(String remoteUrl, String parentId) requestArtDownload;

  /// Callback to translate local file path to a content:// URI
  final String Function(String localPath) toContentUri;

  AndroidAutoHandler({
    required this.serverUrl,
    required this.accessToken,
    required this.getCachedArtPath,
    required this.requestArtDownload,
    required this.toContentUri,
  });

  /// Resolves the most reliable art URI for a browse item, caching in background if needed.
  Uri? _resolveArtUri(String itemId, String? imageTag, String parentId) {
    if (serverUrl == 'http://localhost' || accessToken.isEmpty) return null;
    final remoteUrl = _artUrl(itemId, imageTag: imageTag);
    final cachedPath = getCachedArtPath(remoteUrl);
    if (cachedPath != null) {
      final contentUriStr = toContentUri(cachedPath);
      return Uri.parse(contentUriStr);
    } else {
      // Trigger background download and return the remote URL as fallback
      requestArtDownload(remoteUrl, parentId);
      return Uri.parse(remoteUrl);
    }
  }
  void updateCredentials(String url, String token) {
    serverUrl = url;
    accessToken = token;
  }

  bool hasContainer(String containerId) {
    return _tracksByContainer.containsKey(containerId) &&
        _tracksByContainer[containerId]!.isNotEmpty;
  }

  void updateContainer(String containerId, List<JellyfinTrack> tracks) {
    _tracksByContainer[containerId] = tracks;
  }

  // ---------------------------------------------------------------------------
  // Library update
  // ---------------------------------------------------------------------------

  /// Replace the cached library data. Should be called after every sync with
  /// the Jellyfin server.
  void updateLibrary(
    List<JellyfinPlaylist> playlists,
    List<JellyfinAlbum> albums,
    List<JellyfinArtist> artists,
    Map<String, List<JellyfinTrack>> tracksByContainer, {
    List<JellyfinTrack> recentTracks = const [],
    List<RecentlyPlayedItem> recentlyPlayed = const [],
    List<JellyfinAlbum> newAlbums = const [],
  }) {
    _playlists = playlists;
    _albums = albums;
    _artists = artists;
    _tracksByContainer = tracksByContainer;
    _recentTracks = recentTracks;
    _recentlyPlayed = recentlyPlayed;
    _newAlbums = newAlbums;
  }

  // ---------------------------------------------------------------------------
  // URL helpers
  // ---------------------------------------------------------------------------

  /// Builds an image URL for [itemId]. When [imageTag] is provided it is
  /// appended for proper cache-busting and ensures the correct image variant
  /// is fetched. The [api_key] param allows background fetchers (Android Auto,
  /// notification shade) to load artwork without browser session cookies.
  String _artUrl(String itemId, {String? imageTag}) {
    final clean = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    final tag = (imageTag != null && imageTag.isNotEmpty) ? '&tag=$imageTag' : '';
    return '$clean/Items/$itemId/Images/Primary?api_key=$accessToken$tag';
  }

  // ---------------------------------------------------------------------------
  // MediaBrowser tree
  // ---------------------------------------------------------------------------

  /// Returns the list of [MediaItem]s that are children of [parentMediaId].
  ///
  /// This method is called by Android Auto when the user navigates the browse
  /// tree. [options] contains pagination hints (ignored here for simplicity).
  List<MediaItem> getChildren(
    String parentMediaId,
    Map<String, dynamic>? options,
  ) {
    // ── Root ──────────────────────────────────────────────────────────────────
    if (parentMediaId == AudioService.browsableRootId) {
      return _buildRoot();
    }

    // ── Home ──────────────────────────────────────────────────────────────────
    if (parentMediaId == kRootHome) {
      return _buildHome();
    }

    // ── Playlists ─────────────────────────────────────────────────────────────
    if (parentMediaId == kRootPlaylists) {
      return _buildPlaylistBrowse();
    }

    if (parentMediaId.startsWith(kPrefixPlaylist)) {
      return _buildTrackList(parentMediaId);
    }

    // ── Albums ────────────────────────────────────────────────────────────────
    if (parentMediaId == kRootAlbums) {
      return _buildAlbumBrowse();
    }

    if (parentMediaId.startsWith(kPrefixAlbum)) {
      return _buildTrackList(parentMediaId);
    }

    // ── Artists ───────────────────────────────────────────────────────────────
    if (parentMediaId == kRootArtists) {
      return _buildArtistBrowse();
    }

    if (parentMediaId.startsWith(kPrefixArtist)) {
      return _buildArtistAlbums(parentMediaId);
    }

    if (parentMediaId == kRootSmartMixes) {
      return _buildSmartMixes();
    }

    if (parentMediaId.startsWith('smart_mix_')) {
      return _buildTrackList(parentMediaId);
    }

    return const [];
  }

  List<MediaItem> _buildRoot() {
    return [
      MediaItem(
        id: kRootHome,
        title: 'Home',
        playable: false,
        artUri: Uri.parse('android.resource://$_kPackage/drawable/ic_home'),
        extras: _kGridExtras,
      ),
      MediaItem(
        id: kRootPlaylists,
        title: 'Playlists',
        playable: false,
        artUri: Uri.parse('android.resource://$_kPackage/drawable/ic_playlist'),
        extras: _kGridExtras,
      ),
      MediaItem(
        id: kRootAlbums,
        title: 'Albums',
        playable: false,
        artUri: Uri.parse('android.resource://$_kPackage/drawable/ic_album'),
        extras: _kGridExtras,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Home — smart mixes first, then recent albums + playlists as a grid
  // ---------------------------------------------------------------------------

  List<MediaItem> _buildHome() {
    final items = <MediaItem>[];

    // ── Smart Mixes (pinned items directly at the top) ────────────────────────
    items.addAll([
      MediaItem(
        id: 'smart_mix_daily',
        title: 'Daily Mix',
        displaySubtitle: 'Curated just for you',
        artUri: Uri.parse('android.resource://$_kPackage/drawable/mix_daily'),
        playable: false,
        extras: _kGridExtras,
      ),
      MediaItem(
        id: 'smart_mix_heavy_rotation',
        title: 'Heavy Rotation',
        displaySubtitle: 'Your most-played tracks',
        artUri: Uri.parse('android.resource://$_kPackage/drawable/mix_heavy'),
        playable: false,
        extras: _kGridExtras,
      ),
      MediaItem(
        id: 'smart_mix_undiscovered',
        title: 'Undiscovered',
        displaySubtitle: "Music you haven't explored yet",
        artUri: Uri.parse('android.resource://$_kPackage/drawable/mix_undiscovered'),
        playable: false,
        extras: _kGridExtras,
      ),
    ]);

    // ── Recently Played (from local selection history) ───────────────────────
    for (final item in _recentlyPlayed.take(8)) {
      final containerId = item.type == RecentlyPlayedType.album
          ? '$kPrefixAlbum${item.id}'
          : item.type == RecentlyPlayedType.playlist
              ? '$kPrefixPlaylist${item.id}'
              : item.type == RecentlyPlayedType.artist
                  ? '$kPrefixArtist${item.id}'
                  : item.id;
      
      items.add(MediaItem(
        id: containerId,
        title: item.title,
        displaySubtitle: item.subtitle,
        artUri: _resolveArtUri(item.id, item.imageTag, kRootHome),
        playable: item.type == RecentlyPlayedType.track,
        extras: _kGridExtras,
      ));
    }

    // ── Newly Added (New For You) ───────────────────────────────────────────
    for (final album in _newAlbums.take(6)) {
      items.add(MediaItem(
        id: '$kPrefixAlbum${album.id}',
        title: album.name,
        artist: album.artist,
        artUri: _resolveArtUri(album.id, album.imageTag, kRootHome),
        playable: false,
        extras: _kGridExtras,
      ));
    }

    // ── Playlists ───────────────────────────────────────────────────────────
    for (final playlist in _playlists.take(4)) {
      items.add(MediaItem(
        id: '$kPrefixPlaylist${playlist.id}',
        title: playlist.name,
        displaySubtitle: '${playlist.trackCount} tracks',
        artUri: _resolveArtUri(playlist.id, playlist.imageTag, kRootHome),
        playable: false,
        extras: _kGridExtras,
      ));
    }

    return items;
  }

  // ---------------------------------------------------------------------------
  // Playlists
  // ---------------------------------------------------------------------------

  List<MediaItem> _buildPlaylistBrowse() {
    // Cap at 100 — Android Binder IPC buffer limit is ~1MB per transaction.
    return _playlists.take(100).map((playlist) {
      return MediaItem(
        id: '$kPrefixPlaylist${playlist.id}',
        title: playlist.name,
        displaySubtitle: '${playlist.trackCount} tracks',
        artUri: _resolveArtUri(playlist.id, playlist.imageTag, kRootPlaylists),
        playable: false,
        extras: _kGridExtras,
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Albums
  // ---------------------------------------------------------------------------

  List<MediaItem> _buildAlbumBrowse() {
    // Cap at 100 — Android Binder IPC buffer limit is ~1MB per transaction.
    // Each MediaItem with a full art URL can be 8-12KB; 200+ blows the buffer.
    return _albums.take(100).map((album) {
      return MediaItem(
        id: '$kPrefixAlbum${album.id}',
        title: album.name,
        artist: album.artist,
        artUri: _resolveArtUri(album.id, album.imageTag, kRootAlbums),
        playable: false,
        extras: _kGridExtras,
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Artists
  // ---------------------------------------------------------------------------

  List<MediaItem> _buildArtistBrowse() {
    return _artists.map((artist) {
      return MediaItem(
        id: '$kPrefixArtist${artist.id}',
        title: artist.name,
        artUri: artist.imageTag != null
            ? _resolveArtUri(artist.id, artist.imageTag, kRootArtists)
            : null,
        playable: false,
        extras: _kGridExtras,
      );
    }).toList();
  }

  /// Returns the albums that belong to a given artist, making them browsable
  /// so the user can drill further into individual tracks.
  List<MediaItem> _buildArtistAlbums(String artistMediaId) {
    final artistId = artistMediaId.substring(kPrefixArtist.length);
    
    // Find the artist object to get the actual name
    final artistObj = _artists.firstWhere(
      (a) => a.id == artistId,
      orElse: () => JellyfinArtist(id: artistId, name: ''),
    );
    final artistName = artistObj.name;
    if (artistName.isEmpty) return const [];

    final artistAlbums = _albums
        .where((a) => a.artist.toLowerCase() == artistName.toLowerCase())
        .toList();

    final items = <MediaItem>[];

    // Add "Play All Songs" playable shortcut at the top
    items.add(MediaItem(
      id: 'artist_play_all_$artistId',
      title: 'Play All Songs',
      displaySubtitle: artistName,
      playable: true,
      artUri: artistObj.imageTag != null
          ? _resolveArtUri(artistObj.id, artistObj.imageTag, artistMediaId)
          : null,
      extras: const {
        kContentStyleSupported: true,
        kContentStylePlayableHint: kContentStyleList,
      },
    ));

    items.addAll(artistAlbums.map((album) {
      return MediaItem(
        id: '$kPrefixAlbum${album.id}',
        title: album.name,
        artist: album.artist,
        artUri: _resolveArtUri(album.id, album.imageTag, artistMediaId),
        playable: false,
        extras: _kGridExtras,
      );
    }));

    return items;
  }

  // ---------------------------------------------------------------------------
  // Smart Mixes
  // ---------------------------------------------------------------------------
  List<MediaItem> _buildSmartMixes() {
    return [
      MediaItem(
        id: 'smart_mix_daily',
        title: 'Daily Mix',
        displaySubtitle: 'Curated just for you',
        artUri: Uri.parse('android.resource://$_kPackage/drawable/mix_daily'),
        playable: false,
        extras: _kGridExtras,
      ),
      MediaItem(
        id: 'smart_mix_heavy_rotation',
        title: 'Heavy Rotation',
        displaySubtitle: 'Your most-played tracks',
        artUri: Uri.parse('android.resource://$_kPackage/drawable/mix_heavy'),
        playable: false,
        extras: _kGridExtras,
      ),
      MediaItem(
        id: 'smart_mix_undiscovered',
        title: 'Undiscovered',
        displaySubtitle: "Music you haven't explored yet",
        artUri: Uri.parse('android.resource://$_kPackage/drawable/mix_undiscovered'),
        playable: false,
        extras: _kGridExtras,
      ),
    ];
  }
  // ---------------------------------------------------------------------------
  // Track lists (shared by playlists and albums)
  // ---------------------------------------------------------------------------

  List<MediaItem> _buildTrackList(String containerId) {
    final tracks = _tracksByContainer[containerId] ?? [];
    return tracks.map((track) {
      // Prefer track-level imageTag for most precise artwork;
      // fall back to album-level art if track has no own image.
      final artUri = track.imageTag != null && track.imageTag!.isNotEmpty
          ? _resolveArtUri(track.id, track.imageTag, containerId)
          : (track.albumId.isNotEmpty
              ? _resolveArtUri(track.albumId, null, containerId)
              : _resolveArtUri(track.id, null, containerId));
      return MediaItem(
        id: track.id,
        title: track.title,
        album: track.album,
        artist: track.artist,
        duration: track.duration,
        artUri: artUri,
        playable: true,
        extras: {
          kContentStyleSupported: true,
          kContentStylePlayableHint: kContentStyleList,
          'streamUrl': '$serverUrl/Audio/${track.id}/stream?static=true&api_key=$accessToken',
          'containerId': containerId,
        },
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Search (voice + text)
  // ---------------------------------------------------------------------------

  /// Returns search results as a flat list of playable [MediaItem]s.
  /// Tracks come first, then albums (shown as browsable containers).
  List<MediaItem> searchLocal(String query) {
    final q = query.toLowerCase();
    final results = <MediaItem>[];

    // Matching tracks from all loaded containers
    for (final tracks in _tracksByContainer.values) {
      for (final track in tracks) {
        if (track.title.toLowerCase().contains(q) ||
            track.artist.toLowerCase().contains(q) ||
            track.album.toLowerCase().contains(q)) {
          final artUri = track.imageTag != null && track.imageTag!.isNotEmpty
              ? _resolveArtUri(track.id, track.imageTag, 'search')
              : (track.albumId.isNotEmpty
                  ? _resolveArtUri(track.albumId, null, 'search')
                  : null);
          results.add(MediaItem(
            id: track.id,
            title: track.title,
            album: track.album,
            artist: track.artist,
            duration: track.duration,
            artUri: artUri,
            playable: true,
            extras: const {
              kContentStyleSupported: true,
              kContentStylePlayableHint: kContentStyleList,
            },
          ));
        }
      }
    }

    // Matching albums (browsable)
    for (final album in _albums) {
      if (album.name.toLowerCase().contains(q) ||
          album.artist.toLowerCase().contains(q)) {
        results.add(MediaItem(
          id: '$kPrefixAlbum${album.id}',
          title: album.name,
          artist: album.artist,
          artUri: _resolveArtUri(album.id, album.imageTag, 'search'),
          playable: false,
          extras: _kGridExtras,
        ));
      }
    }

    return results.take(25).toList();
  }

  /// Returns the container ID (playlist/album/smart mix) that contains [trackId].
  String? findContainerForTrack(String trackId) {
    for (final entry in _tracksByContainer.entries) {
      if (entry.value.any((t) => t.id == trackId)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Returns the list of tracks for a container.
  List<JellyfinTrack> getTracksForContainer(String containerId) {
    return _tracksByContainer[containerId] ?? [];
  }

  /// Finds a track by its ID across all cached containers.
  JellyfinTrack? findTrackById(String trackId) {
    for (final tracks in _tracksByContainer.values) {
      for (final track in tracks) {
        if (track.id == trackId) {
          return track;
        }
      }
    }
    return null;
  }
}
