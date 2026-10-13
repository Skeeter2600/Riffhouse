import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/update_service.dart';

enum UpdateStatus {
  idle,
  checking,
  upToDate,

  /// A newer release exists but has not been downloaded.
  available,
  downloading,

  /// The update is downloaded and waiting for the user to confirm install.
  readyToInstall,
  error,
}

/// What the app should bring to the user's attention.
enum UpdatePrompt {
  /// A newer version is available / ready to install.
  update,

  /// The app was just updated; show the notes of the running version.
  whatsNew,
}

class UpdateState {
  final UpdateStatus status;
  final bool autoUpdateEnabled;
  final String? currentVersion;

  /// The newer release, once one has been found.
  final AppRelease? release;
  final double progress;
  final String? message;

  /// Notes for the version that was just installed.
  final AppRelease? whatsNew;

  /// Set (with a new [promptSeq]) each time a dialog should be shown.
  final UpdatePrompt? prompt;
  final int promptSeq;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.autoUpdateEnabled = true,
    this.currentVersion,
    this.release,
    this.progress = 0,
    this.message,
    this.whatsNew,
    this.prompt,
    this.promptSeq = 0,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    bool? autoUpdateEnabled,
    String? currentVersion,
    AppRelease? release,
    double? progress,
    String? message,
    bool clearMessage = false,
    AppRelease? whatsNew,
    UpdatePrompt? prompt,
    int? promptSeq,
  }) {
    return UpdateState(
      status: status ?? this.status,
      autoUpdateEnabled: autoUpdateEnabled ?? this.autoUpdateEnabled,
      currentVersion: currentVersion ?? this.currentVersion,
      release: release ?? this.release,
      progress: progress ?? this.progress,
      message: clearMessage ? null : (message ?? this.message),
      whatsNew: whatsNew ?? this.whatsNew,
      prompt: prompt ?? this.prompt,
      promptSeq: promptSeq ?? this.promptSeq,
    );
  }
}

/// Drives update checks, downloads and installs.
///
/// With automatic updates on (the default) the app checks GitHub on launch,
/// downloads a newer release in the background and then prompts with its
/// release notes. With it off nothing happens until the user taps
/// "Check for updates" in settings.
class UpdateNotifier extends StateNotifier<UpdateState> {
  static const _autoUpdateKey = 'auto_update_enabled';
  static const _lastSeenVersionKey = 'update_last_seen_version';

  final UpdateService _service;
  File? _downloadedUpdate;
  bool _busy = false;

  UpdateNotifier(this._service) : super(const UpdateState()) {
    _init();
  }

  Future<void> _init() async {
    var autoEnabled = true;
    String? lastSeen;
    String? current;
    try {
      final prefs = await SharedPreferences.getInstance();
      autoEnabled = prefs.getBool(_autoUpdateKey) ?? true;
      lastSeen = prefs.getString(_lastSeenVersionKey);
      current = await _service.currentVersion();
      await prefs.setString(_lastSeenVersionKey, current);
    } catch (_) {
      // Fall through with defaults
    }
    if (!mounted) return;
    state = state.copyWith(
      autoUpdateEnabled: autoEnabled,
      currentVersion: current,
    );

    // First launch after an update: show what changed in this version.
    if (current != null &&
        lastSeen != null &&
        UpdateService.isNewer(current, lastSeen)) {
      final release = await _service.fetchReleaseForVersion(current);
      if (!mounted) return;
      if (release != null && release.notes.isNotEmpty) {
        state = state.copyWith(
          whatsNew: release,
          prompt: UpdatePrompt.whatsNew,
          promptSeq: state.promptSeq + 1,
        );
      }
    }

    if (autoEnabled) await checkForUpdates();
  }

  Future<void> setAutoUpdateEnabled(bool enabled) async {
    state = state.copyWith(autoUpdateEnabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoUpdateKey, enabled);
    } catch (_) {
      // Ignore error
    }
    if (enabled) await checkForUpdates();
  }

  /// Looks for a newer release. When automatic updates are on it is also
  /// downloaded straight away. [userInitiated] checks always end in a prompt
  /// or a visible "up to date" / error status.
  Future<void> checkForUpdates({bool userInitiated = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      state = state.copyWith(status: UpdateStatus.checking, clearMessage: true);

      final current = state.currentVersion ?? await _service.currentVersion();
      final latest = await _service.fetchLatestRelease();
      if (!mounted) return;

      if (latest == null) {
        state = state.copyWith(
          status: userInitiated ? UpdateStatus.error : UpdateStatus.idle,
          currentVersion: current,
          message: userInitiated ? 'Could not reach GitHub to check for updates' : null,
        );
        return;
      }
      if (!UpdateService.isNewer(latest.version, current)) {
        state = state.copyWith(
          status: UpdateStatus.upToDate,
          currentVersion: current,
        );
        return;
      }

      state = state.copyWith(
        status: UpdateStatus.available,
        currentVersion: current,
        release: latest,
      );

      final canDownload =
          _service.canSelfInstall && latest.downloadUrl != null;
      if (canDownload && state.autoUpdateEnabled) {
        await _download(latest);
        if (!mounted) return;
      }
      _raisePrompt(UpdatePrompt.update);
    } catch (_) {
      // E.g. the installed version could not be read. Never leave the status
      // stuck on "checking".
      if (!mounted) return;
      state = state.copyWith(
        status: userInitiated ? UpdateStatus.error : UpdateStatus.idle,
        message: userInitiated ? 'Could not check for updates' : null,
      );
    } finally {
      _busy = false;
    }
  }

  /// Downloads the pending release (if needed) and opens the installer.
  Future<void> downloadAndInstall() async {
    final release = state.release;
    if (release == null || _busy) return;
    _busy = true;
    try {
      if (state.status != UpdateStatus.readyToInstall ||
          _downloadedUpdate == null) {
        await _download(release);
        if (!mounted || state.status != UpdateStatus.readyToInstall) return;
      }
      final result = await _service.installUpdate(_downloadedUpdate!);
      if (!mounted) return;
      switch (result) {
        case InstallResult.started:
          state = state.copyWith(clearMessage: true);
        case InstallResult.restartRequired:
          state = state.copyWith(message: 'Restarting to finish the update…');
          // Give the message a moment on screen; the helper script is
          // waiting for this process to end before it swaps the files.
          await Future<void>.delayed(const Duration(milliseconds: 600));
          exit(0);
        case InstallResult.permissionRequired:
          state = state.copyWith(
            message: 'Allow Riffhouse to install apps, then tap Install again',
          );
        case InstallResult.failed:
          state = state.copyWith(message: 'Could not start the installer');
      }
    } catch (_) {
      if (mounted) state = state.copyWith(message: 'Could not start the installer');
    } finally {
      _busy = false;
    }
  }

  Future<void> _download(AppRelease release) async {
    state = state.copyWith(
      status: UpdateStatus.downloading,
      progress: 0,
      clearMessage: true,
    );
    try {
      _downloadedUpdate = await _service.downloadUpdate(
        release,
        onProgress: (p) {
          // Throttle rebuilds to whole-percent steps.
          if (mounted && (p - state.progress >= 0.01 || p >= 1)) {
            state = state.copyWith(progress: p);
          }
        },
      );
      if (!mounted) return;
      state = state.copyWith(status: UpdateStatus.readyToInstall, progress: 1);
    } catch (_) {
      if (!mounted) return;
      _downloadedUpdate = null;
      state = state.copyWith(
        status: UpdateStatus.available,
        message: 'Download failed. Check your connection and try again',
      );
    }
  }

  void _raisePrompt(UpdatePrompt prompt) {
    state = state.copyWith(prompt: prompt, promptSeq: state.promptSeq + 1);
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

final updateProvider =
    StateNotifierProvider<UpdateNotifier, UpdateState>((ref) {
  return UpdateNotifier(ref.watch(updateServiceProvider));
});
