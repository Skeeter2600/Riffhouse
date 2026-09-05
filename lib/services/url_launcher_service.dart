import 'package:flutter/services.dart';

/// Launches URLs using a direct Android ACTION_VIEW intent via MethodChannel.
///
/// Falls back to copying the URL to clipboard if the native channel is not yet
/// registered (e.g. app not fully rebuilt after MainActivity.kt change).
class UrlLauncherService {
  static const _channel = MethodChannel('com.riffhouse/url_launcher');

  /// Attempts to open [url] in the device browser via native Intent.
  /// Returns `(launched: true)` on success, `(launched: false, url: url)` on
  /// MissingPluginException so the caller can prompt the user to copy it.
  static Future<({bool launched, String url})> launch(String url) async {
    try {
      final result = await _channel.invokeMethod<bool>('launch', {'url': url});
      return (launched: result ?? false, url: url);
    } on MissingPluginException {
      // Native channel not registered yet — full rebuild required.
      await Clipboard.setData(ClipboardData(text: url));
      return (launched: false, url: url);
    }
  }
}
