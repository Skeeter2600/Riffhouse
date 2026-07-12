import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// ─── Table Definitions ────────────────────────────────────────────────────────

/// Tracks that have been downloaded for offline use
class CachedTracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get jellyfinId => text().unique()();
  TextColumn get localPath => text()();
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get cachedAt => dateTime()();
}

/// Playback history and statistics per track
class PlaybackRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get jellyfinId => text().unique()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get skipCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayedAt => dateTime()();
}

/// Locally cached playlists synced from/to Jellyfin
class LocalPlaylists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get jellyfinId => text().unique()();
  TextColumn get name => text()();
  TextColumn get trackIdsJson => text()(); // JSON-encoded List<String>
  DateTimeColumn get lastSyncedAt => dateTime()();
}

/// Saved server connection config
class ServerConfigs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverUrl => text()();
  TextColumn get userId => text()();
  TextColumn get username => text()();
  TextColumn get accessToken => text()();
}

// ─── Database ─────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [CachedTracks, PlaybackRecords, LocalPlaylists, ServerConfigs])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  // ── CachedTracks ────────────────────────────────────────────────────────────

  Future<CachedTrack?> getCachedTrack(String jellyfinId) =>
      (select(cachedTracks)..where((t) => t.jellyfinId.equals(jellyfinId)))
          .getSingleOrNull();

  Future<List<CachedTrack>> getAllCachedTracks() => select(cachedTracks).get();

  Future<void> upsertCachedTrack(CachedTracksCompanion entry) =>
      into(cachedTracks).insertOnConflictUpdate(entry);

  Future<int> deleteCachedTrack(String jellyfinId) =>
      (delete(cachedTracks)..where((t) => t.jellyfinId.equals(jellyfinId)))
          .go();

  Future<int> getTotalCacheSizeBytes() async {
    final rows = await select(cachedTracks).get();
    return rows.fold<int>(0, (sum, row) => sum + row.sizeBytes);
  }

  // ── PlaybackRecords ──────────────────────────────────────────────────────────

  Future<PlaybackRecord?> getPlaybackRecord(String jellyfinId) =>
      (select(playbackRecords)..where((t) => t.jellyfinId.equals(jellyfinId)))
          .getSingleOrNull();

  Future<List<PlaybackRecord>> getAllPlaybackRecords() =>
      select(playbackRecords).get();

  Future<void> upsertPlaybackRecord(PlaybackRecordsCompanion entry) =>
      into(playbackRecords).insertOnConflictUpdate(entry);

  Future<void> incrementPlayCount(String jellyfinId) async {
    final existing = await getPlaybackRecord(jellyfinId);
    if (existing != null) {
      await (update(playbackRecords)
            ..where((t) => t.jellyfinId.equals(jellyfinId)))
          .write(PlaybackRecordsCompanion(
        playCount: Value(existing.playCount + 1),
        lastPlayedAt: Value(DateTime.now()),
      ));
    } else {
      await into(playbackRecords).insert(PlaybackRecordsCompanion(
        jellyfinId: Value(jellyfinId),
        playCount: const Value(1),
        skipCount: const Value(0),
        lastPlayedAt: Value(DateTime.now()),
      ));
    }
  }

  Future<void> incrementSkipCount(String jellyfinId) async {
    final existing = await getPlaybackRecord(jellyfinId);
    if (existing != null) {
      await (update(playbackRecords)
            ..where((t) => t.jellyfinId.equals(jellyfinId)))
          .write(PlaybackRecordsCompanion(
        skipCount: Value(existing.skipCount + 1),
      ));
    } else {
      await into(playbackRecords).insert(PlaybackRecordsCompanion(
        jellyfinId: Value(jellyfinId),
        playCount: const Value(0),
        skipCount: const Value(1),
        lastPlayedAt: Value(DateTime.now()),
      ));
    }
  }

  /// Returns up to [limit] playback records sorted by most-recently-played.
  Future<List<PlaybackRecord>> getRecentPlaybackRecords({int limit = 30}) =>
      (select(playbackRecords)
            ..orderBy([(t) => OrderingTerm.desc(t.lastPlayedAt)])
            ..limit(limit))
          .get();

  // ── LocalPlaylists ───────────────────────────────────────────────────────────

  Future<List<LocalPlaylist>> getAllLocalPlaylists() =>
      select(localPlaylists).get();

  Future<LocalPlaylist?> getLocalPlaylist(String jellyfinId) =>
      (select(localPlaylists)..where((t) => t.jellyfinId.equals(jellyfinId)))
          .getSingleOrNull();

  Future<void> upsertLocalPlaylist(LocalPlaylistsCompanion entry) =>
      into(localPlaylists).insertOnConflictUpdate(entry);

  Future<int> deleteLocalPlaylist(String jellyfinId) =>
      (delete(localPlaylists)..where((t) => t.jellyfinId.equals(jellyfinId)))
          .go();

  // ── ServerConfig ─────────────────────────────────────────────────────────────

  Future<ServerConfig?> getServerConfig() =>
      select(serverConfigs).getSingleOrNull();

  Future<void> saveServerConfig(ServerConfigsCompanion config) async {
    await delete(serverConfigs).go();
    await into(serverConfigs).insert(config);
  }

  Future<void> clearServerConfig() => delete(serverConfigs).go();
}

// ─── Connection helper ────────────────────────────────────────────────────────

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'riffhouse.db'));
    return NativeDatabase(
      file,
      setup: (database) {
        database.execute('PRAGMA journal_mode=WAL;');
        database.execute('PRAGMA busy_timeout=5000;');
      },
    );
  });
}
