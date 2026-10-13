part of '../library_provider.dart';

// ---------------------------------------------------------------------------
// Smart mix caching (regenerates daily at midnight local time)
// ---------------------------------------------------------------------------

class _CachedMix {
  final List<JellyfinTrack> tracks;
  final DateTime generatedAt;
  _CachedMix(this.tracks, this.generatedAt);
}

DateTime _nextMidnight(DateTime from) {
  return DateTime(from.year, from.month, from.day + 1);
}

bool _isMixCacheValid(DateTime generatedAt) {
  return DateTime.now().isBefore(_nextMidnight(generatedAt));
}

final Map<String, _CachedMix> _mixMemoryCache = {};

/// Generations currently running, so concurrent provider builds share one
/// result instead of each producing a different random mix.
final Map<String, Future<List<JellyfinTrack>>> _mixInFlight = {};

/// Bumped on every cache clear so a generation started before the clear does
/// not persist its now-outdated result.
int _mixCacheEpoch = 0;

const _smartMixStoragePrefix = 'smart_mix_persisted_cache_v2_';

Future<List<JellyfinTrack>?> _getPersistedMix(String mixType) async {
  // Check in-memory cache first
  final mem = _mixMemoryCache[mixType];
  if (mem != null && _isMixCacheValid(mem.generatedAt)) {
    return mem.tracks;
  }

  // Check persistent storage across app restarts
  try {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_smartMixStoragePrefix$mixType');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final generatedAtMs = data['generatedAt'] as int?;
      if (generatedAtMs != null) {
        final generatedAt = DateTime.fromMillisecondsSinceEpoch(generatedAtMs);
        if (_isMixCacheValid(generatedAt)) {
          final rawTracks = data['tracks'] as List? ?? [];
          final tracks = rawTracks
              .map((t) => JellyfinTrack.fromJson(t as Map<String, dynamic>))
              .toList();
          _mixMemoryCache[mixType] = _CachedMix(tracks, generatedAt);
          return tracks;
        }
      }
    }
  } catch (_) {
    // Ignore cache read error
  }
  return null;
}

Future<void> _persistMix(String mixType, List<JellyfinTrack> tracks) async {
  final now = DateTime.now();
  _mixMemoryCache[mixType] = _CachedMix(tracks, now);
  try {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'generatedAt': now.millisecondsSinceEpoch,
      'tracks': tracks.map((t) => t.toMap()).toList(),
    };
    await prefs.setString('$_smartMixStoragePrefix$mixType', jsonEncode(payload));
  } catch (_) {
    // Ignore cache write error
  }
}

/// Read access to the daily smart mix cache for code outside the provider
/// graph (the Android Auto browse tree), so it shows the same mix as the app.
Future<List<JellyfinTrack>?> getCachedSmartMix(String mixType) =>
    _getPersistedMix(mixType);

/// Stores [tracks] as today's mix for [mixType]. See [getCachedSmartMix].
Future<void> cacheSmartMix(String mixType, List<JellyfinTrack> tracks) =>
    _persistMix(mixType, tracks);

Future<void> clearSmartMixCache([String? mixType]) async {
  _mixCacheEpoch++;
  if (mixType != null) {
    _mixMemoryCache.remove(mixType);
    _mixInFlight.remove(mixType);
  } else {
    _mixMemoryCache.clear();
    _mixInFlight.clear();
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    if (mixType != null) {
      await prefs.remove('$_smartMixStoragePrefix$mixType');
    } else {
      final keys = prefs.getKeys().where((k) => k.startsWith(_smartMixStoragePrefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    }
  } catch (_) {
    // Ignore cache clear error
  }
}

class DailyMixConfigNotifier extends StateNotifier<AsyncValue<DailyMixConfig>> {
  final PlaylistService _playlistService;

  DailyMixConfigNotifier(this._playlistService) : super(const AsyncLoading()) {
    loadConfig();
  }

  Future<void> loadConfig() async {
    state = const AsyncLoading();
    try {
      final config = await _playlistService.getDailyMixConfig();
      state = AsyncData(config);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> saveConfig(DailyMixConfig config) async {
    await _playlistService.saveDailyMixConfig(config);
    // Clear before publishing the new config so nothing re-reads the old mix.
    await clearSmartMixCache('daily_drive');
    state = AsyncData(config);
  }

  Future<void> resetConfig() async {
    await _playlistService.resetDailyMixConfig();
    final defaultConfig = DailyMixConfig.defaultConfig();
    await clearSmartMixCache('daily_drive');
    state = AsyncData(defaultConfig);
  }
}

final dailyMixConfigProvider =
    StateNotifierProvider<DailyMixConfigNotifier, AsyncValue<DailyMixConfig>>((ref) {
  final playlistService = ref.watch(playlistServiceProvider);
  return DailyMixConfigNotifier(playlistService);
});

final topGenresProvider = FutureProvider<List<String>>((ref) async {
  final playlistService = ref.watch(playlistServiceProvider);
  return playlistService.getTopListenedGenres();
});

final recentGenresProvider = FutureProvider<List<String>>((ref) async {
  final playlistService = ref.watch(playlistServiceProvider);
  return playlistService.getRecentlyListenedGenres();
});

/// Provider that resolves the tracks for a given smart mix type
/// ('daily', 'heavy', 'undiscovered', 'daily_drive').
/// Results are persisted to disk and valid until midnight of each day.
final smartMixTracksProvider =
    FutureProvider.autoDispose.family<List<JellyfinTrack>, String>((ref, mixType) async {
  // Resolve dependencies up front; the provider may be disposed while awaiting.
  final tracksFuture = ref.watch(tracksProvider.future)..ignore();
  final playlistService = ref.read(playlistServiceProvider);
  final podcastService = ref.read(podcastServiceProvider);

  // Return persisted/cached result if still valid (before midnight).
  final cached = await _getPersistedMix(mixType);
  if (cached != null && cached.isNotEmpty) {
    return cached;
  }

  final running = _mixInFlight[mixType];
  if (running != null) return running;

  final generation = _generateSmartMix(
    mixType: mixType,
    tracksFuture: tracksFuture,
    playlistService: playlistService,
    podcastService: podcastService,
  );
  _mixInFlight[mixType] = generation;
  try {
    return await generation;
  } finally {
    if (identical(_mixInFlight[mixType], generation)) {
      _mixInFlight.remove(mixType);
    }
  }
});

Future<List<JellyfinTrack>> _generateSmartMix({
  required String mixType,
  required Future<List<JellyfinTrack>> tracksFuture,
  required PlaylistService playlistService,
  required PodcastService podcastService,
}) async {
  final epoch = _mixCacheEpoch;
  final tracks = await tracksFuture;
  var complete = true;

  List<JellyfinTrack> result;
  if (mixType.startsWith('genre_')) {
    final genre = Uri.decodeComponent(mixType.substring('genre_'.length));
    result = await playlistService.getSmartMix(
      genreFilter: [genre],
      libraryTracks: tracks,
    );
  } else if (mixType == 'daily') {
    result = await playlistService.getSmartMix(libraryTracks: tracks);
  } else if (mixType == 'daily_drive') {
    // The config is read from storage here rather than watched, so a config
    // provider emission cannot trigger a second, different generation.
    result = await playlistService.getDailyDrive(
      libraryTracks: tracks,
      podcastService: podcastService,
      onIncomplete: () => complete = false,
    );
  } else if (mixType == 'heavy') {
    result = await playlistService.getHeavyRotation(libraryTracks: tracks);
  } else if (mixType == 'undiscovered') {
    result = await playlistService.getUndiscovered(libraryTracks: tracks);
  } else {
    result = [];
  }

  // Persist result until next midnight, unless a source failed to load (retry
  // on the next open) or the cache was cleared while generating.
  if (complete && result.isNotEmpty && epoch == _mixCacheEpoch) {
    await _persistMix(mixType, result);
  }
  return result;
}
