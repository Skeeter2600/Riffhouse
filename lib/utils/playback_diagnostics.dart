import 'log.dart';

/// Debug-build logging of what the player does around song changes and
/// crossfades. Nothing is logged or kept in release builds.
///
/// Lines hold track titles, positions and player states: never addresses or
/// sign-in details.
class PlaybackDiagnostics {
  PlaybackDiagnostics._();

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// A position as `m:ss.mmm`, or `?` when it is not known.
  static String time(Duration? d) {
    if (d == null) return '?';
    final sign = d.isNegative ? '-' : '';
    final ms = d.inMilliseconds.abs();
    return '$sign${ms ~/ 60000}:${_two((ms ~/ 1000) % 60)}.'
        '${(ms % 1000).toString().padLeft(3, '0')}';
  }

  static void log(String message) => logDebug('[Playback] $message');

  /// Logs something that should never happen, so it stands out.
  static void failed(String message) => log('CHECK FAILED: $message');
}
