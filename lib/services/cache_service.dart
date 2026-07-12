import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import '../database/app_database.dart';

/// Manages downloading, storing, and querying locally cached audio files using Drift.
class CacheService {
  final AppDatabase db;
  final Map<String, String> _cacheRegistry = {};

  CacheService(this.db);

  /// Initializes the in-memory cache registry by loading records from the database.
  Future<void> init() async {
    final tracks = await db.getAllCachedTracks();
    _cacheRegistry.clear();
    for (final t in tracks) {
      if (File(t.localPath).existsSync()) {
        _cacheRegistry[t.jellyfinId] = t.localPath;
      } else {
        await db.deleteCachedTrack(t.jellyfinId);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Directory helpers
  // ---------------------------------------------------------------------------

  /// Returns (and creates if necessary) the audio cache directory.
  Future<Directory> _getAudioCacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${docs.path}/audio_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  // ---------------------------------------------------------------------------
  // Cache queries
  // ---------------------------------------------------------------------------

  /// Synchronously returns the local file path for [jellyfinId] if cached on disk,
  /// or `null` if the track is not cached.
  String? getCachedPathSync(String jellyfinId) {
    final path = _cacheRegistry[jellyfinId];
    if (path == null) return null;

    final file = File(path);
    if (!file.existsSync()) {
      // Record is stale — clean up.
      _cacheRegistry.remove(jellyfinId);
      db.deleteCachedTrack(jellyfinId);
      return null;
    }

    return path;
  }

  /// Synchronously returns `true` if [jellyfinId] has a valid cached file on disk.
  bool isTrackCachedSync(String jellyfinId) {
    return getCachedPathSync(jellyfinId) != null;
  }

  /// Returns the local file path for [jellyfinId] if it exists on disk,
  /// or `null` if the track is not cached (async wrapper).
  Future<String?> getCachedPath(String jellyfinId) async {
    return getCachedPathSync(jellyfinId);
  }

  /// Returns `true` if [jellyfinId] has a valid cached file on disk (async wrapper).
  Future<bool> isTrackCached(String jellyfinId) async {
    return isTrackCachedSync(jellyfinId);
  }

  // ---------------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------------

  /// Downloads the audio file at [streamUrl] and stores it under the cache dir.
  ///
  /// Progress is reported via [onProgress] as a value between 0.0 and 1.0.
  /// A [CachedTrack] record is saved in Drift after a successful download.
  Future<void> downloadTrack(
    String jellyfinId,
    String streamUrl, {
    Function(double)? onProgress,
  }) async {
    final cacheDir = await _getAudioCacheDir();
    final filePath = '${cacheDir.path}/$jellyfinId.audio';
    final file = File(filePath);

    // Remove any previous partial download.
    if (await file.exists()) {
      await file.delete();
    }

    final dio = Dio();

    await dio.download(
      streamUrl,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );

    final sizeBytes = await file.length();

    await db.upsertCachedTrack(CachedTracksCompanion(
      jellyfinId: Value(jellyfinId),
      localPath: Value(filePath),
      sizeBytes: Value(sizeBytes),
      cachedAt: Value(DateTime.now()),
    ));

    _cacheRegistry[jellyfinId] = filePath;
  }

  // ---------------------------------------------------------------------------
  // Deletion
  // ---------------------------------------------------------------------------

  /// Deletes the cached file and its database record for [jellyfinId].
  Future<void> deleteCachedTrack(String jellyfinId) async {
    final path = _cacheRegistry.remove(jellyfinId);
    final targetPath = path ?? (await db.getCachedTrack(jellyfinId))?.localPath;

    if (targetPath != null) {
      final file = File(targetPath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    await db.deleteCachedTrack(jellyfinId);
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Returns all cached tracks stored in database.
  Future<List<CachedTrack>> getAllCachedTracks() async {
    return db.getAllCachedTracks();
  }

  /// Returns the total disk usage of all cached tracks in bytes.
  Future<int> getCacheSizeBytes() async {
    return db.getTotalCacheSizeBytes();
  }
}
