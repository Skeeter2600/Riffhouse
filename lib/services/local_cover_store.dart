import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../utils/app_paths.dart';
import '../utils/log.dart';
import 'music_service.dart';

/// Keeps custom covers on this device for servers that cannot store them
/// (the Subsonic API has no call for setting a playlist's cover).
///
/// A cover belongs to one item on one account, so the same playlist id on
/// another server never picks it up. Covers saved here are not on the server
/// and do not appear on other devices.
class LocalCoverStore {
  LocalCoverStore._();

  static const _folder = 'local_covers';

  static Directory? _directory;

  /// Cover file per item key, filled by [init].
  static final Map<String, File> _covers = {};

  /// Changes whenever a cover is saved or removed, so widgets can redraw.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Loads the saved covers. Call once at startup; [directory] is for tests.
  static Future<void> init({Directory? directory}) async {
    try {
      final dir = directory ??
          Directory(p.join((await appDataDirectory()).path, _folder));
      await dir.create(recursive: true);
      _directory = dir;
      _covers.clear();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        // File names are "<item key>_<saved at>.img".
        final name = p.basenameWithoutExtension(entity.path);
        final split = name.lastIndexOf('_');
        if (split <= 0) continue;
        final key = name.substring(0, split);
        final existing = _covers[key];
        // Keep the newest if an older one was left behind.
        if (existing == null || entity.path.compareTo(existing.path) > 0) {
          _covers[key] = entity;
        }
      }
    } catch (e) {
      logDebug('[LocalCoverStore.init] $e');
    }
  }

  static String _key(MusicService service, String itemId) => sha1
      .convert(utf8.encode('${service.type.id}|'
          '${MusicService.normalizeUrl(service.serverUrl)}|'
          '${service.userId}|$itemId'))
      .toString();

  /// The custom cover saved for [itemId], if there is one.
  static File? coverFor(MusicService? service, String itemId) =>
      service == null ? null : _covers[_key(service, itemId)];

  /// Saves [bytes] as the cover of [itemId]. Returns whether it worked.
  static Future<bool> save(
    MusicService service,
    String itemId,
    List<int> bytes,
  ) async {
    final dir = _directory;
    if (dir == null || bytes.isEmpty) return false;
    try {
      final key = _key(service, itemId);
      // A new file name each time: Flutter caches images by path, so
      // overwriting in place would keep showing the old picture.
      final file = File(p.join(
          dir.path, '${key}_${DateTime.now().millisecondsSinceEpoch}.img'));
      await file.writeAsBytes(bytes, flush: true);

      final previous = _covers[key];
      _covers[key] = file;
      if (previous != null) await _delete(previous);
      revision.value++;
      return true;
    } catch (e) {
      logDebug('[LocalCoverStore.save] $e');
      return false;
    }
  }

  /// Forgets the custom cover of [itemId], e.g. when its playlist is deleted.
  static Future<void> remove(MusicService service, String itemId) async {
    final file = _covers.remove(_key(service, itemId));
    if (file == null) return;
    await _delete(file);
    revision.value++;
  }

  static Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A leftover file is harmless.
    }
  }
}
