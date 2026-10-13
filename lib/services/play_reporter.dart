import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';
import 'jellyfin_service.dart';

/// Tells the server about plays, so its play counts and "last played" dates
/// match what was listened to in Riffhouse.
///
/// Every play is written to a pending list before it is sent and only removed
/// once the server has accepted it, so plays made offline (or while the server
/// is down) are delivered later with their original time.
class PlayReporter {
  static const enabledKey = 'report_plays_to_server';
  static const _pendingKey = 'pending_play_reports_v1';

  /// Oldest reports are dropped beyond this, so the list cannot grow forever
  /// on an install that never reaches its server again.
  static const _maxPending = 5000;

  static bool _flushing = false;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, enabled);
  }

  static List<Map<String, dynamic>> _read(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_pendingKey);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Number of plays waiting to be sent.
  static Future<int> pendingCount() async =>
      _read(await SharedPreferences.getInstance()).length;

  /// Queues a play of [itemId] by the signed-in user and tries to send
  /// everything outstanding.
  static Future<void> report(
    MusicService service,
    String itemId,
    DateTime playedAt,
  ) async {
    // The placeholder service used while signed out has no user.
    if (service.userId.isEmpty || service.accessToken.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(enabledKey) ?? true)) return;

      final pending = _read(prefs)
        ..add({
          'u': service.userId,
          'id': itemId,
          't': playedAt.toUtc().millisecondsSinceEpoch,
        });
      if (pending.length > _maxPending) {
        pending.removeRange(0, pending.length - _maxPending);
      }
      await prefs.setString(_pendingKey, jsonEncode(pending));
    } catch (e) {
      logDebug('[PlayReporter.report] $e');
      return;
    }
    await flush(service);
  }

  /// Sends the signed-in user's pending plays, oldest first, stopping at the
  /// first one the server cannot be reached for.
  static Future<void> flush(MusicService service) async {
    if (_flushing || service.userId.isEmpty || service.accessToken.isEmpty) {
      return;
    }
    _flushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(enabledKey) ?? true)) return;

      while (true) {
        final pending = _read(prefs);
        final index = pending.indexWhere((e) => e['u'] == service.userId);
        if (index < 0) return;
        final entry = pending[index];
        final result = await service.markPlayed(
          entry['id'] as String,
          DateTime.fromMillisecondsSinceEpoch(entry['t'] as int, isUtc: true),
        );
        if (result == ReportResult.unreachable) return;

        // Sent, or refused for good (e.g. the track was deleted): either way
        // it is done. Re-read the list, since a play may have been queued
        // while the request was in flight.
        final latest = _read(prefs)
          ..removeWhere((e) =>
              e['u'] == entry['u'] &&
              e['id'] == entry['id'] &&
              e['t'] == entry['t']);
        await prefs.setString(_pendingKey, jsonEncode(latest));
      }
    } catch (e) {
      logDebug('[PlayReporter.flush] $e');
    } finally {
      _flushing = false;
    }
  }
}
