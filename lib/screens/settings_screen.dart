import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../audio/audio_handler.dart';
import '../audio/queue_notifier.dart';

import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../providers/download_provider.dart';
import '../providers/update_provider.dart';
import '../services/backup_files.dart';
import '../services/backup_service.dart';
import '../services/play_reporter.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/update_dialog.dart';

/// Whether plays are reported to the server (Settings → Playback).
final reportPlaysProvider =
    FutureProvider<bool>((ref) => PlayReporter.isEnabled());

const _gb = 1024 * 1024 * 1024;

/// Choices offered for the download limit; zero means unlimited.
const _storageLimitChoices = [0, 1 * _gb, 2 * _gb, 5 * _gb, 10 * _gb, 20 * _gb, 50 * _gb];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final service = ref.watch(musicServiceProvider);
    final audioHandler = ref.watch(audioHandlerProvider);
    final updateState = ref.watch(updateProvider);
    final downloads = ref.watch(downloadProvider);
    final reportPlays = ref.watch(reportPlaysProvider).valueOrNull ?? true;
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/home/library');
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ---- Server ----
          const _SectionHeader(title: 'Server'),
          _SettingsTile(
            icon: Icons.storage_rounded,
            title: 'Server Type',
            subtitle: service?.type.label ?? 'Not connected',
          ),
          _SettingsTile(
            icon: Icons.dns_rounded,
            title: 'Server URL',
            subtitle: service?.serverUrl ?? 'Not connected',
          ),
          _SettingsTile(
            icon: Icons.person_rounded,
            title: 'Username',
            subtitle: user?.name ?? 'Unknown',
          ),
          _DangerTile(
            icon: Icons.logout_rounded,
            title: 'Disconnect',
            subtitle: 'Sign out from this server',
            onTap: () => _confirmLogout(context, ref),
          ),

          const SizedBox(height: 8),

          // ---- Playback ----
          const _SectionHeader(title: 'Playback'),
          _ToggleTile(
            icon: Icons.music_note_rounded,
            title: 'Gapless Playback',
            subtitle: 'Pre-load the next track so songs follow on without a pause',
            value: audioHandler.gaplessEnabled,
            onChanged: audioHandler.setGaplessEnabled,
          ),
          _ToggleTile(
            icon: Icons.blur_on_rounded,
            title: 'Crossfade',
            subtitle: 'Fade each song out while the next one fades in',
            value: audioHandler.crossfadeEnabled,
            onChanged: audioHandler.setCrossfadeEnabled,
          ),
          _CrossfadeLengthTile(handler: audioHandler),
          _ToggleTile(
            icon: Icons.cloud_sync_rounded,
            title: 'Report Plays to Server',
            subtitle:
                'Keep play counts and last-played dates on your server up to date',
            value: reportPlays,
            onChanged: (enabled) async {
              await PlayReporter.setEnabled(enabled);
              ref.invalidate(reportPlaysProvider);
            },
          ),

          const SizedBox(height: 8),

          // ---- Downloads ----
          const _SectionHeader(title: 'Downloads'),
          _SettingsTile(
            icon: Icons.storage_rounded,
            title: 'Downloads',
            subtitle: 'Manage offline tracks',
            onTap: () => context.push('/home/downloads'),
          ),
          if (isMobile)
            _ToggleTile(
              icon: Icons.wifi_rounded,
              title: 'Download on Wi-Fi Only',
              subtitle: 'Never use mobile data for downloads',
              value: downloads.wifiOnly,
              onChanged: ref.read(downloadProvider.notifier).setWifiOnly,
            ),
          _SettingsTile(
            icon: Icons.sd_storage_rounded,
            title: 'Download Limit',
            subtitle: downloads.storageLimitBytes == 0
                ? 'No limit'
                : 'Stop downloading at ${formatBytes(downloads.storageLimitBytes)}',
            onTap: () => _chooseStorageLimit(context, ref),
          ),
          _SettingsTile(
            icon: Icons.cleaning_services_rounded,
            title: 'Prune Temporary Cache',
            subtitle: 'Remove songs not in downloaded playlists',
            onTap: () async {
              final count = await ref.read(downloadProvider.notifier).pruneUnpinnedTracks();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(count > 0
                        ? 'Cleaned up $count temporary tracks'
                        : 'Cache clean. Only downloaded playlists retained.'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              }
            },
          ),
          _DangerTile(
            icon: Icons.delete_outline,
            title: 'Clear All Cache',
            subtitle: 'Remove all downloaded files from device',
            onTap: () => _confirmClearCache(context, ref),
          ),

          const SizedBox(height: 8),

          // ---- Backup ----
          const _SectionHeader(title: 'Backup'),
          _SettingsTile(
            icon: Icons.save_alt_rounded,
            title: 'Back Up Listening Data',
            subtitle:
                'Save play history, stats, mixes and podcast subscriptions to a file',
            onTap: () => _backUp(context, ref),
          ),
          _SettingsTile(
            icon: Icons.restore_rounded,
            title: 'Restore from Backup',
            subtitle: 'Bring listening data back from a backup file',
            onTap: () => _restore(context, ref),
          ),

          const SizedBox(height: 8),

          // ---- Updates ----
          const _SectionHeader(title: 'Updates'),
          _ToggleTile(
            icon: Icons.system_update_rounded,
            title: 'Automatic Updates',
            subtitle: 'Check on launch and download new releases',
            value: updateState.autoUpdateEnabled,
            onChanged: ref.read(updateProvider.notifier).setAutoUpdateEnabled,
          ),
          _SettingsTile(
            icon: Icons.refresh_rounded,
            title: 'Check for Updates',
            subtitle: _updateStatusText(updateState),
            onTap: () => _checkForUpdates(context, ref),
          ),

          const SizedBox(height: 8),

          // ---- About ----
          const _SectionHeader(title: 'About'),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            title: 'Version',
            subtitle: updateState.currentVersion ?? '…',
          ),
          _SettingsTile(
            icon: Icons.code_rounded,
            title: 'GitHub',
            subtitle: 'Riffhouse',
            onTap: () =>
                _openLink(context, 'https://github.com/Skeeter2600/Riffhouse'),
          ),
          _SettingsTile(
            icon: Icons.coffee_rounded,
            title: 'Support Riffhouse',
            subtitle: 'Buy me a coffee',
            onTap: () =>
                _openLink(context, 'https://buymeacoffee.com/skeeter26'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    ),
    );
  }

  Future<void> _openLink(BuildContext context, String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Reported below
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  void _chooseStorageLimit(BuildContext context, WidgetRef ref) {
    final current = ref.read(downloadProvider).storageLimitBytes;
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Download Limit',
            style: TextStyle(color: AppColors.textPrimary)),
        children: [
          for (final bytes in _storageLimitChoices)
            ListTile(
              leading: Icon(
                bytes == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: bytes == current
                    ? AppColors.primary
                    : AppColors.textMuted,
              ),
              title: Text(
                bytes == 0 ? 'No limit' : formatBytes(bytes),
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(downloadProvider.notifier).setStorageLimitBytes(bytes);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _backUp(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final prefs = await SharedPreferences.getInstance();
      final json =
          await BackupService(ref.read(databaseProvider)).exportJson(prefs);
      final bytes = Uint8List.fromList(utf8.encode(json));
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final savedAs =
          await BackupFiles.save('riffhouse-backup-$date.json', bytes);
      if (savedAs == null) return; // Cancelled

      messenger.showSnackBar(SnackBar(
        content: Text('Backup saved: $savedAs'),
        backgroundColor: AppColors.primary,
      ));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not save the backup')));
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await BackupFiles.pick();
      if (bytes == null) return; // Cancelled

      final prefs = await SharedPreferences.getInstance();
      final summary = await BackupService(ref.read(databaseProvider))
          .restoreJson(utf8.decode(bytes), prefs);

      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backup restored',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Text(
            'Restored play history for ${summary.playbackRecords} tracks and '
            '${summary.settings} saved settings.\n\n'
            'Close and reopen Riffhouse so every screen picks them up.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } on BackupFormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not read that backup file')));
    }
  }

  String _updateStatusText(UpdateState state) {
    switch (state.status) {
      case UpdateStatus.checking:
        return 'Checking…';
      case UpdateStatus.upToDate:
        return 'You have the latest version';
      case UpdateStatus.available:
        return 'Version ${state.release?.version} is available';
      case UpdateStatus.downloading:
        return 'Downloading version ${state.release?.version}… '
            '${(state.progress * 100).round()}%';
      case UpdateStatus.readyToInstall:
        return 'Version ${state.release?.version} is ready to install';
      case UpdateStatus.error:
        return state.message ?? 'Could not check for updates';
      case UpdateStatus.idle:
        return 'Look for a new release on GitHub';
    }
  }

  /// Runs a manual check, or reopens the prompt for an update already found.
  Future<void> _checkForUpdates(BuildContext context, WidgetRef ref) async {
    bool hasUpdate() {
      final status = ref.read(updateProvider).status;
      return status == UpdateStatus.available ||
          status == UpdateStatus.downloading ||
          status == UpdateStatus.readyToInstall;
    }

    if (!hasUpdate()) {
      // A newer release raises the prompt through the app shell.
      await ref.read(updateProvider.notifier).checkForUpdates(userInitiated: true);
      return;
    }
    if (context.mounted) await showUpdateDialog(context, UpdatePrompt.update);
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            child: const Text('Disconnect',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmClearCache(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Cache',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'All offline tracks will be deleted from your device.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(downloadProvider.notifier).clearAllDownloads();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All cached tracks deleted'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              }
            },
            child:
                const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings section widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 12)),
      onTap: onTap,
      trailing: onTap != null
          ? const Icon(Icons.chevron_right, color: AppColors.textMuted)
          : null,
    );
  }
}

/// Shows and changes how long two songs overlap.
class _CrossfadeLengthTile extends StatefulWidget {
  final JellyfinAudioHandler handler;
  const _CrossfadeLengthTile({required this.handler});

  @override
  State<_CrossfadeLengthTile> createState() => _CrossfadeLengthTileState();
}

class _CrossfadeLengthTileState extends State<_CrossfadeLengthTile> {
  Future<void> _choose() async {
    var seconds = widget.handler.crossfadeSeconds;
    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Crossfade Length',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$seconds ${seconds == 1 ? 'second' : 'seconds'}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Slider(
                value: seconds.toDouble(),
                min: JellyfinAudioHandler.minCrossfadeSeconds.toDouble(),
                max: JellyfinAudioHandler.maxCrossfadeSeconds.toDouble(),
                divisions: JellyfinAudioHandler.maxCrossfadeSeconds -
                    JellyfinAudioHandler.minCrossfadeSeconds,
                label: '$seconds s',
                onChanged: (v) => setDialogState(() => seconds = v.round()),
              ),
              const Text(
                'Over this long, the song that is ending fades to silence '
                'while the next one fades up to full volume.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, seconds),
              child: const Text('Set', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await widget.handler.setCrossfadeSeconds(chosen);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.handler.crossfadeSeconds;
    return _SettingsTile(
      icon: Icons.timelapse_rounded,
      title: 'Crossfade Length',
      subtitle: '$seconds ${seconds == 1 ? 'second' : 'seconds'}',
      onTap: _choose,
    );
  }
}

class _ToggleTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_ToggleTile> createState() => _ToggleTileState();
}

class _ToggleTileState extends State<_ToggleTile> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(covariant _ToggleTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow values that load or change after the tile was first built.
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(widget.icon, color: AppColors.primary, size: 20),
      ),
      title: Text(widget.title,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      subtitle: Text(widget.subtitle,
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 12)),
      trailing: Switch(
        value: _value,
        onChanged: (v) {
          setState(() => _value = v);
          widget.onChanged(v);
        },
        activeThumbColor: AppColors.primary,
      ),
    );
  }
}

class _DangerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DangerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.redAccent, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(
              color: Colors.redAccent, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 12)),
      onTap: onTap,
    );
  }
}
