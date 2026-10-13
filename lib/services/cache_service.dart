import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import '../database/app_database.dart';
import '../utils/app_paths.dart';

/// Manages downloading, storing, and querying locally cached audio files using Drift.
class CacheService {
  final AppDatabase db;
  final Map<String, String> _cacheRegistry = {};
  final Dio _dio;

  /// Downloads in progress, so the same track is never fetched twice at once
  /// (the player pre-loading the next song while the user downloads it).
  final Map<String, Future<void>> _inFlight = {};

  /// Half-finished downloads older than this are thrown away at startup.
  static const _staleDownloadAge = Duration(days: 7);

  /// Override for tests; normally the app's audio cache folder.
  final Directory? _audioDirectory;

  CacheService(this.db, {Dio? dio, Directory? audioDirectory})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              // For a streamed download this is the longest allowed silence
              // between two pieces of data, so a stalled transfer fails (and
              // can be resumed) instead of occupying a download slot forever.
              receiveTimeout: const Duration(seconds: 30),
            )),
        _audioDirectory = audioDirectory;

  /// Initializes the in-memory cache registry by loading records from the database.
  Future<void> init() async {
    final cacheDir = await _getAudioCacheDir();
    final tracks = await db.getAllCachedTracks();
    _cacheRegistry.clear();
    for (final t in tracks) {
      if (File(t.localPath).existsSync()) {
        _cacheRegistry[t.jellyfinId] = t.localPath;
        continue;
      }
      // The data folder may have moved since the path was stored (desktop
      // installs migrate out of Documents). Look for the file by name.
      final moved = File(p.join(cacheDir.path, p.basename(t.localPath)));
      if (moved.existsSync()) {
        await db.upsertCachedTrack(CachedTracksCompanion(
          jellyfinId: Value(t.jellyfinId),
          localPath: Value(moved.path),
          sizeBytes: Value(t.sizeBytes),
          cachedAt: Value(t.cachedAt),
        ));
        _cacheRegistry[t.jellyfinId] = moved.path;
      } else {
        await db.deleteCachedTrack(t.jellyfinId);
      }
    }

    try {
      final cutoff = DateTime.now().subtract(_staleDownloadAge);
      await for (final entity in cacheDir.list()) {
        if (entity is File &&
            entity.path.endsWith(_partialSuffix) &&
            (await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Ignore error
    }
  }

  // ---------------------------------------------------------------------------
  // Directory helpers
  // ---------------------------------------------------------------------------

  static const _partialSuffix = '.part';

  /// Returns (and creates if necessary) the audio cache directory.
  Future<Directory> _getAudioCacheDir() async =>
      _audioDirectory ?? await audioCacheDirectory();

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
  ///
  /// An interrupted or cancelled download leaves its partial file behind and
  /// the next attempt continues from where it stopped.
  Future<void> downloadTrack(
    String jellyfinId,
    String streamUrl, {
    Function(double)? onProgress,
    CancelToken? cancelToken,
  }) {
    final running = _inFlight[jellyfinId];
    if (running != null) return running;

    final download = _download(
      jellyfinId,
      streamUrl,
      onProgress: onProgress,
      cancelToken: cancelToken,
    ).whenComplete(() {
      // A block body on purpose: returning the removed future here would
      // make this download wait on itself.
      _inFlight.remove(jellyfinId);
    });
    _inFlight[jellyfinId] = download;
    return download;
  }

  Future<void> _download(
    String jellyfinId,
    String streamUrl, {
    Function(double)? onProgress,
    CancelToken? cancelToken,
    bool allowResume = true,
  }) async {
    final cacheDir = await _getAudioCacheDir();
    final filePath = '${cacheDir.path}/$jellyfinId.audio';
    final partial = File('$filePath$_partialSuffix');

    var offset = 0;
    if (await partial.exists()) {
      if (allowResume) {
        offset = await partial.length();
      } else {
        await partial.delete();
      }
    }

    final response = await _dio.get<ResponseBody>(
      streamUrl,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: offset > 0 ? {'Range': 'bytes=$offset-'} : null,
        // 416: the server will not continue from our offset. Handled below.
        validateStatus: (status) =>
            status != null && (status < 300 || status == 416),
      ),
    );

    if (response.statusCode == 416) {
      // The partial file does not match what the server has; start over.
      return _download(
        jellyfinId,
        streamUrl,
        onProgress: onProgress,
        cancelToken: cancelToken,
        allowResume: false,
      );
    }

    // 206 means the server is sending only the missing part. Anything else
    // is the whole file, so whatever we had is replaced.
    final resumed = response.statusCode == 206 && offset > 0;
    if (!resumed) offset = 0;

    final contentLength =
        int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '') ??
            -1;
    final total = contentLength > 0 ? offset + contentLength : -1;

    var received = offset;
    final sink =
        partial.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    // Listen by hand rather than with `await for`: a cancelled transfer may
    // simply stop delivering data, and the wait has to end when the token
    // fires, not when the next chunk arrives.
    final finished = Completer<void>();
    final subscription = response.data!.stream.listen(
      (chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) onProgress(received / total);
      },
      onError: (Object e, StackTrace st) {
        if (!finished.isCompleted) finished.completeError(e, st);
      },
      onDone: () {
        if (!finished.isCompleted) finished.complete();
      },
      cancelOnError: true,
    );
    unawaited(cancelToken?.whenCancel.then((reason) {
      if (!finished.isCompleted) finished.completeError(reason);
    }));
    try {
      await finished.future;
    } finally {
      // Not awaited: cancelling a connection that has already died may
      // never report back.
      unawaited(subscription.cancel());
      await sink.flush();
      await sink.close();
    }

    if (total > 0 && received != total) {
      throw const FileSystemException('Download ended early');
    }

    final file = File(filePath);
    if (await file.exists()) await file.delete();
    await partial.rename(filePath);

    await db.upsertCachedTrack(CachedTracksCompanion(
      jellyfinId: Value(jellyfinId),
      localPath: Value(filePath),
      sizeBytes: Value(received),
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

    // A half-finished download of the same track goes too.
    try {
      final cacheDir = await _getAudioCacheDir();
      final partial = File('${cacheDir.path}/$jellyfinId.audio$_partialSuffix');
      if (await partial.exists()) await partial.delete();
    } catch (_) {
      // Ignore error
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
