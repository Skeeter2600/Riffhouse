import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// A published GitHub release of the app.
class AppRelease {
  /// Version without the leading "v" (e.g. `1.2.0`).
  final String version;
  final String tag;
  final String title;

  /// Release notes as written on GitHub (Markdown).
  final String notes;
  final String pageUrl;

  /// Download URL of the Android APK asset, if the release has one.
  final String? apkUrl;
  final int? apkSizeBytes;

  const AppRelease({
    required this.version,
    required this.tag,
    required this.title,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.apkSizeBytes,
  });
}

/// Outcome of asking Android to install a downloaded update.
enum InstallResult {
  /// The system installer was opened; the user confirms there.
  started,

  /// The user must first allow this app to install apps. The matching
  /// system settings page was opened.
  permissionRequired,
  failed,
}

/// Checks GitHub Releases for new versions and installs them on Android.
class UpdateService {
  static const repository = 'Skeeter2600/Riffhouse';
  static const _apiBase = 'https://api.github.com/repos/$repository/releases';
  static const _channel = MethodChannel('com.riffhouse/app_update');

  final http.Client _client;
  final Dio _dio;

  UpdateService({http.Client? client, Dio? dio})
      : _client = client ?? http.Client(),
        _dio = dio ?? Dio();

  /// Only Android can install an update from inside the app. Other platforms
  /// are pointed at the release page.
  bool get canSelfInstall => !kIsWeb && Platform.isAndroid;

  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// The newest published release (drafts and pre-releases are excluded by
  /// GitHub), or null if it cannot be fetched.
  Future<AppRelease?> fetchLatestRelease() => _fetchRelease('$_apiBase/latest');

  /// The release for a specific [version], used to show its notes after an
  /// update. Null if there is no such release.
  Future<AppRelease?> fetchReleaseForVersion(String version) =>
      _fetchRelease('$_apiBase/tags/v${normalizeVersion(version)}');

  Future<AppRelease?> _fetchRelease(String url) async {
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map<String, dynamic>) return null;
      return parseRelease(json);
    } catch (_) {
      return null;
    }
  }

  /// Builds an [AppRelease] from a GitHub release JSON object.
  static AppRelease? parseRelease(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String?;
    if (tag == null || tag.isEmpty) return null;

    String? apkUrl;
    int? apkSize;
    for (final asset in (json['assets'] as List? ?? const [])) {
      if (asset is! Map) continue;
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        apkSize = asset['size'] as int?;
        break;
      }
    }

    final name = json['name'] as String?;
    return AppRelease(
      version: normalizeVersion(tag),
      tag: tag,
      title: (name == null || name.isEmpty) ? tag : name,
      notes: (json['body'] as String? ?? '').replaceAll('\r\n', '\n').trim(),
      pageUrl: json['html_url'] as String? ??
          'https://github.com/$repository/releases/tag/$tag',
      apkUrl: apkUrl,
      apkSizeBytes: apkSize,
    );
  }

  /// Strips a leading "v" and any build (`+1`) or pre-release (`-beta`) suffix.
  static String normalizeVersion(String version) {
    var v = version.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    return v.split('+').first.split('-').first;
  }

  /// Compares two versions numerically, part by part. Returns a negative
  /// number if [a] is older than [b], zero if equal, positive if newer.
  static int compareVersions(String a, String b) {
    List<int> parts(String v) => normalizeVersion(v)
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    final length = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static bool isNewer(String candidate, String current) =>
      compareVersions(candidate, current) > 0;

  /// Downloads the APK of [release] into the app's cache and returns it.
  /// A complete download from an earlier attempt is reused.
  Future<File> downloadApk(
    AppRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final url = release.apkUrl;
    if (url == null) {
      throw StateError('Release ${release.tag} has no Android APK');
    }

    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/updates');
    await dir.create(recursive: true);
    final target = File('${dir.path}/Riffhouse-${release.version}.apk');

    // Remove APKs of other versions and any half-finished download.
    await for (final entity in dir.list()) {
      if (entity is File && entity.path != target.path) {
        try {
          await entity.delete();
        } catch (_) {
          // Ignore error
        }
      }
    }

    final expected = release.apkSizeBytes;
    if (await target.exists() &&
        expected != null &&
        await target.length() == expected) {
      onProgress?.call(1);
      return target;
    }

    final partial = File('${target.path}.part');
    await _dio.download(
      url,
      partial.path,
      onReceiveProgress: (received, total) {
        final size = total > 0 ? total : (expected ?? 0);
        if (size > 0) onProgress?.call((received / size).clamp(0.0, 1.0));
      },
    );
    if (expected != null && await partial.length() != expected) {
      await partial.delete();
      throw const FileSystemException('Update download was incomplete');
    }
    if (await target.exists()) await target.delete();
    return partial.rename(target.path);
  }

  /// Hands [apk] to the Android package installer. Android always asks the
  /// user to confirm; an app cannot install an update silently.
  Future<InstallResult> installApk(File apk) async {
    if (!canSelfInstall) return InstallResult.failed;
    try {
      final allowed =
          await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
      if (!allowed) {
        await _channel.invokeMethod<void>('openInstallPermissionSettings');
        return InstallResult.permissionRequired;
      }
      await _channel.invokeMethod<void>('installApk', {'path': apk.path});
      return InstallResult.started;
    } catch (_) {
      return InstallResult.failed;
    }
  }
}
