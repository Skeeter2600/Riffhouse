import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'log.dart';

const _databaseName = 'riffhouse.db';
const _audioCacheFolder = 'audio_cache';

/// The file whose presence means the application folder is in use.
const _settingsFile = 'shared_preferences.json';

/// On Windows and Linux the "documents" directory is the user's own
/// Documents folder, which is no place for a database and a music cache.
/// Those platforms keep their data in the per-user application folder.
/// Mobile and macOS documents directories are already private to the app.
bool get _usesAppSupportFolder =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux);

/// The folder holding the database and downloaded audio.
///
/// If an install still has its data in the legacy Documents location (the
/// move in [migrateLegacyDesktopData] did not happen or failed) that location
/// keeps being used, so listening history is never left behind.
Future<Directory> appDataDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  if (!_usesAppSupportFolder) return documents;

  final support = await getApplicationSupportDirectory();
  final hasNew = await File(p.join(support.path, _databaseName)).exists();
  final hasLegacy = await File(p.join(documents.path, _databaseName)).exists();
  return (!hasNew && hasLegacy) ? documents : support;
}

/// The folder downloaded audio is stored in.
Future<Directory> audioCacheDirectory() async {
  final dir = Directory(p.join((await appDataDirectory()).path, _audioCacheFolder));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Where the application folder was before the app was renamed from its
/// project placeholder (`com.example` / `mobile_music_player`) to Riffhouse.
@visibleForTesting
Directory legacySupportDirectory(Directory current, {required bool windows}) {
  return windows
      // %APPDATA%\<CompanyName>\<ProductName>
      ? Directory(p.join(current.parent.parent.path, 'com.example',
          'mobile_music_player'))
      // ~/.local/share/<application id>
      : Directory(
          p.join(current.parent.path, 'com.example.mobile_music_player'));
}

/// Brings desktop data from where earlier versions kept it to where it lives
/// now. Call once at startup, before settings are read or the database is
/// opened.
///
/// Two moves have happened: the application folder was renamed, and the
/// database and audio cache left the user's Documents folder.
Future<void> migrateLegacyDesktopData() async {
  if (!_usesAppSupportFolder) return;
  try {
    final support = await getApplicationSupportDirectory();
    await copyLegacySupportData(
      legacySupportDirectory(support, windows: Platform.isWindows),
      support,
    );
    await moveLegacyData(await getApplicationDocumentsDirectory(), support);
  } catch (e) {
    logDebug('[migrateLegacyDesktopData] $e');
  }
}

/// Copies everything in the old application folder [from] into [to], unless
/// [to] already holds settings. Returns whether anything was copied.
///
/// The old folder is left as it is: a copy that fails half-way can simply be
/// repeated on the next start, and nothing is ever lost.
@visibleForTesting
Future<bool> copyLegacySupportData(Directory from, Directory to) async {
  if (!await from.exists()) return false;
  if (await File(p.join(to.path, _settingsFile)).exists()) return false;

  await to.create(recursive: true);
  File? settings;
  await for (final entity in from.list(recursive: true)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: from.path);
    // The settings file goes last: it is what marks the copy as complete.
    if (relative == _settingsFile) {
      settings = entity;
      continue;
    }
    final target = File(p.join(to.path, relative));
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
  if (settings != null) {
    await settings.copy(p.join(to.path, _settingsFile));
  }
  return true;
}

/// Moves the database (and the audio cache, when it can be renamed in place)
/// from [from] to [to]. Returns whether anything was moved.
///
/// The database is copied and checked before the originals are deleted, so a
/// failure at any point leaves a complete copy in one of the two places.
@visibleForTesting
Future<bool> moveLegacyData(Directory from, Directory to) async {
  final oldDb = File(p.join(from.path, _databaseName));
  final newDb = File(p.join(to.path, _databaseName));
  if (!await oldDb.exists() || await newDb.exists()) return false;

  await to.create(recursive: true);

  // SQLite keeps recent writes in the -wal file; it has to travel with the
  // database. Copy the side files first so the main file appearing at the
  // new location (which is what [appDataDirectory] looks for) means the set
  // is complete.
  const sideFiles = ['-wal', '-shm'];
  final copied = <File>[];
  try {
    for (final suffix in sideFiles) {
      final side = File('${oldDb.path}$suffix');
      if (await side.exists()) {
        copied.add(await side.copy('${newDb.path}$suffix'));
      }
    }
    final staged = await oldDb.copy('${newDb.path}.migrating');
    if (await staged.length() != await oldDb.length()) {
      throw const FileSystemException('Database copy is incomplete');
    }
    await staged.rename(newDb.path);
  } catch (_) {
    for (final file in copied) {
      try {
        await file.delete();
      } catch (_) {
        // Ignore error
      }
    }
    final staged = File('${newDb.path}.migrating');
    if (await staged.exists()) await staged.delete();
    rethrow;
  }

  // The audio cache can be large, so it is only moved when that is a cheap
  // rename. Otherwise it stays put; the stored file paths remain valid.
  final oldAudio = Directory(p.join(from.path, _audioCacheFolder));
  if (await oldAudio.exists()) {
    try {
      await oldAudio.rename(p.join(to.path, _audioCacheFolder));
    } catch (e) {
      logDebug('[moveLegacyData] Audio cache left in place: $e');
    }
  }

  for (final suffix in ['', ...sideFiles]) {
    try {
      final file = File('${oldDb.path}$suffix');
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A leftover copy is harmless; the new location is now preferred.
    }
  }
  return true;
}
