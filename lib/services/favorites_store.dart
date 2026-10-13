import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/jellyfin_models.dart';
import '../utils/log.dart';
import 'music_service.dart';

/// The tracks the signed-in user has liked.
///
/// The server is where likes live (Jellyfin and Emby "favorites", Subsonic
/// "stars"), so they show up in other apps too. A copy is kept on the device
/// so the heart is right immediately and while offline. It sits outside the
/// widget tree because the background audio handler, which draws the heart
/// in Android Auto and the notification, needs it as well.
class FavoritesStore {
  FavoritesStore._();

  static const _idsKey = 'favorite_track_ids';
  static const _ownerKey = 'favorite_track_owner';

  static final Set<String> _ids = {};
  static String? _owner;

  /// Changes whenever a like is added, removed or re-read from the server.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static String _ownerOf(MusicService service) => '${service.type.id}|'
      '${MusicService.normalizeUrl(service.serverUrl)}|${service.userId}';

  static bool isFavorite(String trackId) => _ids.contains(trackId);

  /// Id and name of the playlist made up of the liked tracks. It is built on
  /// the device from the likes; it does not exist on the server.
  static const likedSongsId = 'liked_songs';
  static const likedSongsTitle = 'Liked Songs';

  static int get count => _ids.length;

  /// The liked tracks among [library], in library order.
  static List<JellyfinTrack> likedTracks(Iterable<JellyfinTrack> library) =>
      library.where((track) => _ids.contains(track.id)).toList();

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_idsKey, _ids.toList());
      if (_owner != null) await prefs.setString(_ownerKey, _owner!);
    } catch (_) {
      // Ignore error
    }
  }

  /// Loads the saved likes of [service]'s account. Likes saved for another
  /// account are not used.
  static Future<void> load(MusicService? service) async {
    _ids.clear();
    _owner = (service == null || !service.isSignedIn) ? null : _ownerOf(service);
    if (_owner != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(_ownerKey) == _owner) {
          _ids.addAll(prefs.getStringList(_idsKey) ?? const []);
        }
      } catch (_) {
        // Start empty
      }
    }
    revision.value++;
  }

  /// Replaces the local copy with what the server has. Does nothing if the
  /// server cannot be reached.
  static Future<void> sync(MusicService service) async {
    if (!service.isSignedIn) return;
    final owner = _ownerOf(service);
    if (_owner != owner) await load(service);

    final remote = await service.getFavoriteTrackIds();
    if (remote == null || _owner != owner) return;
    _ids
      ..clear()
      ..addAll(remote);
    await _persist();
    revision.value++;
    logDebug('[FavoritesStore] ${_ids.length} liked tracks');
  }

  /// Likes or unlikes [trackId]. The change shows at once and is undone if
  /// the server does not accept it. Returns whether it was saved.
  static Future<bool> setFavorite(
    MusicService service,
    String trackId,
    bool favorite,
  ) async {
    if (!service.isSignedIn) return false;
    final owner = _ownerOf(service);
    if (_owner != owner) await load(service);
    if (_ids.contains(trackId) == favorite) return true;

    void apply(bool value) {
      value ? _ids.add(trackId) : _ids.remove(trackId);
      revision.value++;
    }

    apply(favorite);
    final saved = await service.setFavorite(trackId, favorite);
    if (_owner != owner) return saved;
    if (!saved) {
      apply(!favorite);
      return false;
    }
    await _persist();
    return true;
  }

  static Future<bool> toggle(MusicService service, String trackId) =>
      setFavorite(service, trackId, !isFavorite(trackId));
}
