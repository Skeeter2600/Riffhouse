import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/log.dart';

/// The platforms that can install a release from inside the app, each with
/// its own release asset.
enum UpdateTarget {
  android,
  windows,
  linux,

  /// Everything else is pointed at the release page.
  none;

  static UpdateTarget get current {
    if (kIsWeb) return none;
    if (Platform.isAndroid) return android;
    if (Platform.isWindows) return windows;
    if (Platform.isLinux) return linux;
    return none;
  }

  /// Whether [assetName] (lower case) is this platform's release asset.
  bool matchesAsset(String assetName) {
    switch (this) {
      case android:
        return assetName.endsWith('.apk');
      case windows:
        return assetName.contains('windows') && assetName.endsWith('.zip');
      case linux:
        return assetName.contains('linux') && assetName.endsWith('.tar.gz');
      case none:
        return false;
    }
  }
}

/// A published GitHub release of the app.
class AppRelease {
  /// Version without the leading "v" (e.g. `1.2.0`).
  final String version;
  final String tag;
  final String title;

  /// Release notes as written on GitHub (Markdown).
  final String notes;
  final String pageUrl;

  /// Download URL of this platform's asset (APK, zip or tarball), if the
  /// release has one.
  final String? downloadUrl;
  final String? downloadName;
  final int? downloadSizeBytes;

  /// SHA-256 of the asset as published by GitHub (lower-case hex), if known.
  final String? downloadSha256;

  const AppRelease({
    required this.version,
    required this.tag,
    required this.title,
    required this.notes,
    required this.pageUrl,
    this.downloadUrl,
    this.downloadName,
    this.downloadSizeBytes,
    this.downloadSha256,
  });
}

/// Outcome of asking Android to install a downloaded update.
enum InstallResult {
  /// The system installer was opened; the user confirms there.
  started,

  /// The user must first allow this app to install apps. The matching
  /// system settings page was opened.
  permissionRequired,

  /// Desktop: a helper is waiting for the app to quit so it can replace the
  /// installed files and start the new version.
  restartRequired,
  failed,
}

/// Checks GitHub Releases for new versions and installs them on Android,
/// Windows and Linux.
class UpdateService {
  static const repository = 'Skeeter2600/Riffhouse';
  static const _apiBase = 'https://api.github.com/repos/$repository/releases';
  static const _channel = MethodChannel('com.riffhouse/app_update');

  final http.Client _client;
  final Dio _dio;

  UpdateService({http.Client? client, Dio? dio})
      : _client = client ?? http.Client(),
        _dio = dio ?? Dio();

  /// Whether this install can update itself. Android hands the APK to the
  /// system installer; Windows and Linux replace their own files, which only
  /// works when the app's folder is writable (not e.g. under Program Files).
  /// Everything else is pointed at the release page.
  late final bool canSelfInstall = _detectCanSelfInstall();

  bool _detectCanSelfInstall() {
    switch (UpdateTarget.current) {
      case UpdateTarget.android:
        return true;
      case UpdateTarget.windows:
      case UpdateTarget.linux:
        final env = Platform.environment;
        // Sandboxed or read-only package formats update through their store.
        if (env.containsKey('FLATPAK_ID') ||
            env.containsKey('SNAP') ||
            env.containsKey('APPIMAGE')) {
          return false;
        }
        try {
          final probe = File(p.join(
              File(Platform.resolvedExecutable).parent.path, '.update-probe'));
          probe.writeAsStringSync('');
          probe.deleteSync();
          return true;
        } catch (_) {
          return false;
        }
      case UpdateTarget.none:
        return false;
    }
  }

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

  /// Builds an [AppRelease] from a GitHub release JSON object, picking the
  /// asset for [target] (the running platform by default).
  static AppRelease? parseRelease(
    Map<String, dynamic> json, {
    UpdateTarget? target,
  }) {
    final tag = json['tag_name'] as String?;
    if (tag == null || tag.isEmpty) return null;
    target ??= UpdateTarget.current;

    String? downloadUrl;
    String? downloadName;
    int? downloadSize;
    String? downloadSha256;
    for (final asset in (json['assets'] as List? ?? const [])) {
      if (asset is! Map) continue;
      final assetName = asset['name'] as String? ?? '';
      if (target.matchesAsset(assetName.toLowerCase())) {
        downloadUrl = asset['browser_download_url'] as String?;
        downloadName = assetName;
        downloadSize = asset['size'] as int?;
        final digest = asset['digest'] as String?;
        if (digest != null && digest.startsWith('sha256:')) {
          downloadSha256 = digest.substring('sha256:'.length).toLowerCase();
        }
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
      downloadUrl: downloadUrl,
      downloadName: downloadName,
      downloadSizeBytes: downloadSize,
      downloadSha256: downloadSha256,
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

  /// Downloads this platform's asset of [release] into the app's cache and
  /// returns it. A complete download from an earlier attempt is reused.
  Future<File> downloadUpdate(
    AppRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final url = release.downloadUrl;
    final name = release.downloadName;
    if (url == null || name == null) {
      throw StateError(
          'Release ${release.tag} has no download for this platform');
    }

    final tempDir = await getTemporaryDirectory();
    final dir = Directory(p.join(tempDir.path, 'riffhouse-updates'));
    await dir.create(recursive: true);
    // Keep the asset's extension (.apk, .zip, .tar.gz) after the version.
    final extension =
        name.contains('.') ? name.substring(name.indexOf('.')) : '';
    final target =
        File(p.join(dir.path, 'Riffhouse-${release.version}$extension'));

    // Remove other versions, half-finished downloads and old staging folders.
    await for (final entity in dir.list()) {
      if (entity.path != target.path) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // Ignore error
        }
      }
    }

    final expected = release.downloadSizeBytes;
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
    final sha256Expected = release.downloadSha256;
    if (sha256Expected != null) {
      final actual = (await sha256.bind(partial.openRead()).first).toString();
      if (actual != sha256Expected) {
        await partial.delete();
        throw const FileSystemException('Update download failed verification');
      }
    }
    if (await target.exists()) await target.delete();
    return partial.rename(target.path);
  }

  /// Starts installing the downloaded [update].
  ///
  /// Android opens the system installer, which always asks the user to
  /// confirm. On Windows and Linux the new files are unpacked and a helper
  /// script is left waiting; the caller must then quit the app
  /// ([InstallResult.restartRequired]) so the helper can swap the files and
  /// start the new version.
  Future<InstallResult> installUpdate(File update) async {
    if (!canSelfInstall) return InstallResult.failed;
    try {
      if (UpdateTarget.current == UpdateTarget.android) {
        return await _installApk(update);
      }
      await _stageDesktopUpdate(update);
      return InstallResult.restartRequired;
    } catch (e) {
      logDebug('[UpdateService.installUpdate] $e');
      return InstallResult.failed;
    }
  }

  Future<InstallResult> _installApk(File apk) async {
    final allowed =
        await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    if (!allowed) {
      await _channel.invokeMethod<void>('openInstallPermissionSettings');
      return InstallResult.permissionRequired;
    }
    await _channel.invokeMethod<void>('installApk', {'path': apk.path});
    return InstallResult.started;
  }

  /// Unpacks [archive] next to itself and launches a detached helper that
  /// copies the files over the install folder once this process has exited.
  Future<void> _stageDesktopUpdate(File archive) async {
    final executable = File(Platform.resolvedExecutable);
    final installDir = executable.parent.path;
    final executableName = p.basename(executable.path);

    final staging = Directory(p.join(archive.parent.path, 'staging'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    // Windows ships bsdtar, which also reads zip files. Use its full path so
    // a different tar earlier on PATH is not picked up.
    final tar = Platform.isWindows
        ? p.join(Platform.environment['SystemRoot'] ?? r'C:\Windows',
            'System32', 'tar.exe')
        : 'tar';
    final extract =
        await Process.run(tar, ['-xf', archive.path, '-C', staging.path]);
    if (extract.exitCode != 0) {
      throw ProcessException(
          tar, const [], '${extract.stderr}', extract.exitCode);
    }
    // Guard against a release that would leave the app unable to start.
    if (!await File(p.join(staging.path, executableName)).exists()) {
      throw FileSystemException('Update does not contain $executableName');
    }

    if (Platform.isWindows) {
      final script = File(p.join(archive.parent.path, 'apply-update.cmd'));
      await script.writeAsString(windowsUpdateScript);
      await Process.start(
        'cmd.exe',
        ['/c', script.path],
        environment: {
          'RIFF_SRC': staging.path,
          'RIFF_DST': installDir,
          'RIFF_EXE': executableName,
        },
        mode: ProcessStartMode.detached,
      );
    } else {
      final script = File(p.join(archive.parent.path, 'apply-update.sh'));
      await script.writeAsString(linuxUpdateScript(
        pid: pid,
        stagingDir: staging.path,
        installDir: installDir,
        executableName: executableName,
      ));
      await Process.start('/bin/sh', [script.path],
          mode: ProcessStartMode.detached);
    }
  }

  /// Batch script that waits for the app to exit, copies the staged files
  /// over the install folder and starts the app again.
  ///
  /// The folders arrive in environment variables (RIFF_SRC, RIFF_DST,
  /// RIFF_EXE) rather than in the script text, so names with spaces, percent
  /// signs or non-ASCII characters need no escaping. The helper runs without
  /// a console, where tools like `tasklist` print nothing, so "has the app
  /// exited" is tested by opening the running .exe for writing: Windows
  /// refuses that until the process is gone.
  static const windowsUpdateScript = '@echo off\r\n'
      'set /a tries=0\r\n'
      ':wait\r\n'
      '2>NUL (>>"%RIFF_DST%\\%RIFF_EXE%" call ) && goto apply\r\n'
      'set /a tries+=1\r\n'
      // Still running after a minute: leave the install untouched.
      'if %tries% GEQ 60 goto done\r\n'
      'ping -n 2 127.0.0.1 >NUL\r\n'
      'goto wait\r\n'
      ':apply\r\n'
      'robocopy "%RIFF_SRC%" "%RIFF_DST%" /E /R:10 /W:1 /NFL /NDL /NJH /NJS /NP >NUL\r\n'
      'start "" "%RIFF_DST%\\%RIFF_EXE%"\r\n'
      ':done\r\n'
      'rmdir /S /Q "%RIFF_SRC%"\r\n';

  /// Shell script that waits for process [pid] to exit, copies [stagingDir]
  /// over [installDir] and starts the app again.
  static String linuxUpdateScript({
    required int pid,
    required String stagingDir,
    required String installDir,
    required String executableName,
  }) {
    String quote(String path) => "'${path.replaceAll("'", r"'\''")}'";
    final src = quote(stagingDir);
    final dst = quote(installDir);
    final exe = quote(p.posix.join(installDir, executableName));
    return [
      '#!/bin/sh',
      'tries=0',
      'while kill -0 $pid 2>/dev/null; do',
      // Still running after a minute: leave the install untouched.
      '  tries=\$((tries + 1))',
      '  if [ "\$tries" -ge 300 ]; then rm -rf $src; exit 1; fi',
      '  sleep 0.2',
      'done',
      'cp -af $src/. $dst/',
      'rm -rf $src',
      'nohup $exe >/dev/null 2>&1 &',
      '',
    ].join('\n');
  }
}
