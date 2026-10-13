import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';

/// What a restore brought back, for the confirmation message.
class RestoreSummary {
  final int playbackRecords;
  final int playlists;
  final int settings;

  const RestoreSummary({
    required this.playbackRecords,
    required this.playlists,
    required this.settings,
  });
}

class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);

  @override
  String toString() => message;
}

/// Saves and restores everything that exists only on this device: play
/// counts and history, listening statistics, mix settings, podcast
/// subscriptions and playback preferences.
///
/// The sign-in, the library index and downloaded audio are left out. They
/// come back from the server, and the access token does not belong in a file
/// the user may store anywhere.
class BackupService {
  static const _appId = 'riffhouse';
  static const formatVersion = 1;

  /// Settings that describe this install rather than the user's listening.
  /// The download marks are among them: the audio files are not part of a
  /// backup, so restoring "this playlist is downloaded" without them would
  /// be wrong.
  static const _excludedKeys = {
    'jellyfin_device_id',
    'update_last_seen_version',
    'downloaded_playlist_ids_v1',
    'downloaded_album_ids_v1',
    'pinned_track_ids_v1',
  };

  /// Generated mixes are large and rebuilt on demand.
  static const _excludedPrefixes = ['smart_mix_persisted_cache_'];

  final AppDatabase db;

  BackupService(this.db);

  static bool _included(String key) =>
      !_excludedKeys.contains(key) &&
      !_excludedPrefixes.any(key.startsWith);

  /// Builds the backup document.
  Future<Map<String, dynamic>> export(SharedPreferences prefs) async {
    final records = await db.getAllPlaybackRecords();
    final playlists = await db.getAllLocalPlaylists();

    final settings = <String, dynamic>{};
    for (final key in prefs.getKeys().where(_included)) {
      final value = prefs.get(key);
      if (value is bool) {
        settings[key] = {'t': 'bool', 'v': value};
      } else if (value is int) {
        settings[key] = {'t': 'int', 'v': value};
      } else if (value is double) {
        settings[key] = {'t': 'double', 'v': value};
      } else if (value is String) {
        settings[key] = {'t': 'string', 'v': value};
      } else if (value is List) {
        settings[key] = {'t': 'stringList', 'v': value.cast<String>()};
      }
    }

    return {
      'app': _appId,
      'format': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'playbackRecords': [
        for (final r in records)
          {
            'id': r.jellyfinId,
            'plays': r.playCount,
            'skips': r.skipCount,
            'lastPlayed': r.lastPlayedAt.millisecondsSinceEpoch,
          },
      ],
      'localPlaylists': [
        for (final p in playlists)
          {
            'id': p.jellyfinId,
            'name': p.name,
            'trackIds': p.trackIdsJson,
            'lastSynced': p.lastSyncedAt.millisecondsSinceEpoch,
          },
      ],
      'settings': settings,
    };
  }

  Future<String> exportJson(SharedPreferences prefs) async =>
      jsonEncode(await export(prefs));

  /// Restores a backup made by [export].
  ///
  /// Play history is merged rather than replaced: for each track the higher
  /// play and skip counts and the later "last played" win, so restoring into
  /// an install that already has some history never loses any, and restoring
  /// the same file twice changes nothing. Settings in the backup overwrite
  /// the current ones.
  Future<RestoreSummary> restoreJson(
    String source,
    SharedPreferences prefs,
  ) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw const BackupFormatException('This is not a Riffhouse backup file.');
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != _appId) {
      throw const BackupFormatException('This is not a Riffhouse backup file.');
    }
    final format = decoded['format'];
    if (format is! int || format > formatVersion) {
      throw const BackupFormatException(
          'This backup was made by a newer version of Riffhouse. '
          'Update the app and try again.');
    }

    final records = (decoded['playbackRecords'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final existing = {
      for (final r in await db.getAllPlaybackRecords()) r.jellyfinId: r,
    };

    await db.transaction(() async {
      for (final entry in records) {
        final id = entry['id'] as String?;
        if (id == null || id.isEmpty) continue;
        var plays = (entry['plays'] as int?) ?? 0;
        var skips = (entry['skips'] as int?) ?? 0;
        var lastPlayed = DateTime.fromMillisecondsSinceEpoch(
            (entry['lastPlayed'] as int?) ?? 0);

        final current = existing[id];
        if (current != null) {
          if (current.playCount > plays) plays = current.playCount;
          if (current.skipCount > skips) skips = current.skipCount;
          if (current.lastPlayedAt.isAfter(lastPlayed)) {
            lastPlayed = current.lastPlayedAt;
          }
        }
        await db.upsertPlaybackRecord(PlaybackRecordsCompanion(
          jellyfinId: Value(id),
          playCount: Value(plays),
          skipCount: Value(skips),
          lastPlayedAt: Value(lastPlayed),
        ));
      }
    });

    final playlists = (decoded['localPlaylists'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    var restoredPlaylists = 0;
    for (final entry in playlists) {
      final id = entry['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await db.upsertLocalPlaylist(LocalPlaylistsCompanion(
        jellyfinId: Value(id),
        name: Value((entry['name'] as String?) ?? ''),
        trackIdsJson: Value((entry['trackIds'] as String?) ?? '[]'),
        lastSyncedAt: Value(DateTime.fromMillisecondsSinceEpoch(
            (entry['lastSynced'] as int?) ?? 0)),
      ));
      restoredPlaylists++;
    }

    final settings = decoded['settings'] as Map<String, dynamic>? ?? const {};
    var restoredSettings = 0;
    for (final MapEntry(:key, :value) in settings.entries) {
      if (!_included(key) || value is! Map) continue;
      final v = value['v'];
      switch (value['t']) {
        case 'bool' when v is bool:
          await prefs.setBool(key, v);
        case 'int' when v is int:
          await prefs.setInt(key, v);
        case 'double' when v is num:
          await prefs.setDouble(key, v.toDouble());
        case 'string' when v is String:
          await prefs.setString(key, v);
        case 'stringList' when v is List:
          await prefs.setStringList(key, v.cast<String>());
        default:
          continue;
      }
      restoredSettings++;
    }

    return RestoreSummary(
      playbackRecords: records.length,
      playlists: restoredPlaylists,
      settings: restoredSettings,
    );
  }
}
