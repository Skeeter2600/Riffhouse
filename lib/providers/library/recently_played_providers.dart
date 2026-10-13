part of '../library_provider.dart';

// ---------------------------------------------------------------------------
// Recently played (local cache — fast, works offline)
// ---------------------------------------------------------------------------

/// Model for a single recently-played item shown in the home screen section.
class RecentlyPlayedItem {
  final String id;
  final String title;
  final String subtitle;
  final String? imageTag;
  final RecentlyPlayedType type;
  final DateTime lastPlayedAt;
  /// For [RecentlyPlayedType.mix] items — the mixType string used to navigate
  /// to SmartMixDetailScreen (e.g. 'daily', 'genre_Rock').
  final String? mixType;
  final int? colorValue;
  final int? secondaryColorValue;

  const RecentlyPlayedItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.imageTag,
    required this.type,
    required this.lastPlayedAt,
    this.mixType,
    this.colorValue,
    this.secondaryColorValue,
  });
}

enum RecentlyPlayedType { track, album, artist, playlist, mix }

/// Mix types that must not appear in the Recently Played section
/// because they already have prominent dedicated cards on the home screen.
const kExcludedRecentlyPlayedMixTypes = {
  'daily',
  'daily_drive',
  'heavy',
  'undiscovered',
};

/// Returns true if the mix should be excluded from Recently Played.
bool isExcludedRecentlyPlayedMix({String? mixType, String? id, String? title}) {
  if (mixType != null && kExcludedRecentlyPlayedMixTypes.contains(mixType.toLowerCase())) {
    return true;
  }
  if (id != null && kExcludedRecentlyPlayedMixTypes.contains(id.toLowerCase())) {
    return true;
  }
  if (title != null) {
    final t = title.toLowerCase().trim();
    if (t == 'daily mix' || t == 'daily drive' || t == 'heavy rotation' || t == 'undiscovered') {
      return true;
    }
  }
  return false;
}

/// Helper to get fallback gradient colors for mix types
List<Color> getMixPalette(String mixType) {
  if (mixType.startsWith('genre_')) {
    final genre = Uri.decodeComponent(mixType.replaceFirst('genre_', ''));
    const palettes = [
      [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
      [Color(0xFF10B981), Color(0xFF047857)],
      [Color(0xFFF97316), Color(0xFFC2410C)],
      [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
      [Color(0xFFEC4899), Color(0xFFBE185D)],
      [Color(0xFF14B8A6), Color(0xFF0F766E)],
      [Color(0xFFEAB308), Color(0xFFA16207)],
      [Color(0xFF6366F1), Color(0xFF4338CA)],
    ];
    return palettes[genre.hashCode.abs() % palettes.length];
  }
  if (mixType == 'daily') return const [Color(0xFF7C3AED), Color(0xFF4F46E5)];
  if (mixType == 'heavy') return const [Color(0xFFEC4899), Color(0xFFBE185D)];
  if (mixType == 'undiscovered') return const [Color(0xFF06B6D4), Color(0xFF0369A1)];
  if (mixType == 'daily_drive') return const [Color(0xFFF59E0B), Color(0xFFD97706)];
  return const [Color(0xFF8B5CF6), Color(0xFF7C3AED)];
}

/// Model for a recorded selection in history
class RecentSelection {
  final String id;
  final String type; // 'album', 'artist', 'playlist', 'mix'
  final DateTime timestamp;
  /// Stored title for 'mix' entries (no server lookup needed).
  final String? title;
  /// The mixType used to navigate to SmartMixDetailScreen for 'mix' entries.
  final String? mixType;
  final int? colorValue;
  final int? secondaryColorValue;

  RecentSelection({
    required this.id,
    required this.type,
    required this.timestamp,
    this.title,
    this.mixType,
    this.colorValue,
    this.secondaryColorValue,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'timestamp': timestamp.millisecondsSinceEpoch,
        if (title != null) 'title': title,
        if (mixType != null) 'mixType': mixType,
        if (colorValue != null) 'colorValue': colorValue,
        if (secondaryColorValue != null) 'secondaryColorValue': secondaryColorValue,
      };

  factory RecentSelection.fromJson(Map<String, dynamic> json) => RecentSelection(
        id: json['id'] as String,
        type: json['type'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        title: json['title'] as String?,
        mixType: json['mixType'] as String?,
        colorValue: json['colorValue'] as int?,
        secondaryColorValue: json['secondaryColorValue'] as int?,
      );
}

class RecentSelectionsNotifier extends StateNotifier<List<RecentSelection>> {
  RecentSelectionsNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('recent_selections');
      if (jsonStr != null) {
        final List<dynamic> list = jsonDecode(jsonStr);
        final loaded = list
            .map((item) => RecentSelection.fromJson(item))
            .where((item) => !(item.type == 'mix' &&
                isExcludedRecentlyPlayedMix(
                  mixType: item.mixType,
                  id: item.id,
                  title: item.title,
                )))
            .toList();
        state = loaded;
      }
    } catch (_) {}
  }

  Future<void> addSelection(
    String id,
    String type, {
    String? title,
    String? mixType,
    int? colorValue,
    int? secondaryColorValue,
  }) async {
    // Smart mixes of daily mix, daily drive, heavy rotation, and undiscovered
    // should not appear in the recently played section.
    if (type == 'mix' &&
        isExcludedRecentlyPlayedMix(
          mixType: mixType,
          id: id,
          title: title,
        )) {
      return;
    }

    // Remove if already exists (to move it to top)
    final filtered = state.where((item) => !(item.id == id && item.type == type)).toList();

    final newItem = RecentSelection(
      id: id,
      type: type,
      timestamp: DateTime.now(),
      title: title,
      mixType: mixType,
      colorValue: colorValue,
      secondaryColorValue: secondaryColorValue,
    );

    final newState = [newItem, ...filtered].take(20).toList();
    state = newState;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(newState.map((item) => item.toJson()).toList());
      await prefs.setString('recent_selections', jsonStr);
    } catch (_) {}
  }
}

final recentSelectionsProvider = StateNotifierProvider<RecentSelectionsNotifier, List<RecentSelection>>((ref) {
  return RecentSelectionsNotifier();
});

/// Resolves actual models for recently played items by watching [recentSelectionsProvider]
/// and joining against active providers.
final recentlyPlayedProvider = FutureProvider<List<RecentlyPlayedItem>>((ref) async {
  final selections = ref.watch(recentSelectionsProvider);
  if (selections.isEmpty) return [];

  final albums = ref.watch(albumsProvider).valueOrNull ?? [];
  final artists = ref.watch(artistsProvider).valueOrNull ?? [];
  final playlists = ref.watch(playlistsProvider).valueOrNull ?? [];

  final List<RecentlyPlayedItem> items = [];

  for (final sel in selections) {
    try {
      if (sel.type == 'album') {
        final album = albums.firstWhere((a) => a.id == sel.id);
        items.add(RecentlyPlayedItem(
          id: album.id,
          title: album.name,
          subtitle: album.artist,
          imageTag: album.imageTag,
          type: RecentlyPlayedType.album,
          lastPlayedAt: sel.timestamp,
        ));
      } else if (sel.type == 'artist') {
        final artist = artists.firstWhere((a) => a.id == sel.id);
        items.add(RecentlyPlayedItem(
          id: artist.id,
          title: artist.name,
          subtitle: 'Artist',
          imageTag: artist.imageTag,
          type: RecentlyPlayedType.artist,
          lastPlayedAt: sel.timestamp,
        ));
      } else if (sel.type == 'playlist') {
        final playlist = playlists.firstWhere((p) => p.id == sel.id);
        items.add(RecentlyPlayedItem(
          id: playlist.id,
          title: playlist.name,
          subtitle: '${playlist.trackCount} tracks',
          imageTag: playlist.imageTag,
          type: RecentlyPlayedType.playlist,
          lastPlayedAt: sel.timestamp,
        ));
      } else if (sel.type == 'mix' && sel.mixType != null && sel.title != null) {
        if (isExcludedRecentlyPlayedMix(
          mixType: sel.mixType,
          id: sel.id,
          title: sel.title,
        )) {
          continue;
        }
        // Mix items store title & mixType directly — no server lookup needed.
        final palette = sel.colorValue != null
            ? null
            : getMixPalette(sel.mixType!);
        items.add(RecentlyPlayedItem(
          id: sel.mixType!,
          title: sel.title!,
          subtitle: 'Mix',
          imageTag: null,
          type: RecentlyPlayedType.mix,
          lastPlayedAt: sel.timestamp,
          mixType: sel.mixType,
          colorValue: sel.colorValue ?? palette?[0].toARGB32(),
          secondaryColorValue: sel.secondaryColorValue ?? palette?[1].toARGB32(),
        ));
      }
    } catch (_) {
      // Item not found in current library — skip it.
    }
  }

  return items;
});

/// Old server-based providers kept for Android Auto use only.
final recentAlbumsProvider = FutureProvider<List<JellyfinAlbum>>((ref) async {
  final service = ref.watch(musicServiceProvider);
  if (service == null) return [];
  return service.getRecentAlbums();
});

final recentArtistsProvider = FutureProvider<List<JellyfinArtist>>((ref) async {
  final service = ref.watch(musicServiceProvider);
  if (service == null) return [];
  return service.getRecentArtists();
});

final recentPlaylistsProvider = FutureProvider<List<JellyfinPlaylist>>((ref) async {
  final service = ref.watch(musicServiceProvider);
  if (service == null) return [];
  return service.getRecentPlaylists();
});
