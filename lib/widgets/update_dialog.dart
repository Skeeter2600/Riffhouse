import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/update_provider.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

/// Shows the dialog for [prompt]: either the pending update with its release
/// notes, or the notes of the version that was just installed.
Future<void> showUpdateDialog(BuildContext context, UpdatePrompt prompt) {
  return showDialog<void>(
    context: context,
    builder: (_) => prompt == UpdatePrompt.whatsNew
        ? const _WhatsNewDialog()
        : const _UpdateAvailableDialog(),
  );
}

class _UpdateAvailableDialog extends ConsumerWidget {
  const _UpdateAvailableDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateProvider);
    final release = state.release;
    if (release == null) return const SizedBox.shrink();

    final canInstall = ref.watch(updateServiceProvider).canSelfInstall &&
        release.downloadUrl != null;
    // Desktop replaces its own files and has to restart to do so.
    final restarts = UpdateTarget.current != UpdateTarget.android;
    final downloading = state.status == UpdateStatus.downloading;
    final ready = state.status == UpdateStatus.readyToInstall;

    return AlertDialog(
      title: Text(
        ready ? 'Update ready to install' : 'Update available',
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      content: _DialogBody(
        versionLine: state.currentVersion != null
            ? 'Version ${release.version} (you have ${state.currentVersion})'
            : 'Version ${release.version}',
        release: release,
        footer: [
          if (downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: state.progress > 0 ? state.progress : null,
              color: AppColors.primary,
              backgroundColor: AppColors.surfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              'Downloading… ${(state.progress * 100).round()}%',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 12),
            Text(
              state.message!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Later',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        if (canInstall)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: downloading
                ? null
                : () => ref.read(updateProvider.notifier).downloadAndInstall(),
            child: Text(
              ready
                  ? (restarts ? 'Install & restart' : 'Install')
                  : 'Download & install',
              style: const TextStyle(color: Colors.white),
            ),
          )
        else
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => launchUrl(
              Uri.parse(release.pageUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('View release',
                style: TextStyle(color: Colors.white)),
          ),
      ],
    );
  }
}

class _WhatsNewDialog extends ConsumerWidget {
  const _WhatsNewDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final release = ref.watch(updateProvider.select((s) => s.whatsNew));
    if (release == null) return const SizedBox.shrink();

    return AlertDialog(
      title: const Text("What's new",
          style: TextStyle(color: AppColors.textPrimary)),
      content: _DialogBody(
        versionLine: 'Updated to version ${release.version}',
        release: release,
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _DialogBody extends StatelessWidget {
  final String versionLine;
  final AppRelease release;
  final List<Widget> footer;

  const _DialogBody({
    required this.versionLine,
    required this.release,
    this.footer = const [],
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            versionLine,
            style: const TextStyle(
              color: AppColors.primaryLight,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: ReleaseNotesView(markdown: release.notes),
              ),
            ),
          ),
          ...footer,
        ],
      ),
    );
  }
}

/// Renders GitHub release notes. Handles the Markdown that release notes
/// normally use (headings, bullet lists, bold/italic/code markers and links)
/// and shows everything else as plain text.
class ReleaseNotesView extends StatelessWidget {
  final String markdown;

  const ReleaseNotesView({super.key, required this.markdown});

  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$');
  static final _link = RegExp(r'\[([^\]]+)\]\([^)]+\)');
  static final _emphasis = RegExp(r'(\*\*|__|\*|_|`)(.+?)\1');

  /// Strips inline Markdown markers, keeping the text they wrap.
  static String plainInline(String text) {
    var result = text.replaceAllMapped(_link, (m) => m[1]!);
    for (var i = 0; i < 3; i++) {
      result = result.replaceAllMapped(_emphasis, (m) => m[2]!);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (markdown.trim().isEmpty) {
      return const Text(
        'No release notes were provided for this version.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      );
    }

    const body = TextStyle(
        color: AppColors.textSecondary, fontSize: 13, height: 1.4);
    final children = <Widget>[];

    for (final rawLine in markdown.split('\n')) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }
      if (RegExp(r'^\s*([-*_])\1{2,}\s*$').hasMatch(line)) {
        children.add(const Divider(color: AppColors.glassBorder, height: 16));
        continue;
      }

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        final level = heading[1]!.length;
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            plainInline(heading[2]!),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: level == 1 ? 16 : (level == 2 ? 15 : 14),
            ),
          ),
        ));
        continue;
      }

      final bullet = _bullet.firstMatch(line);
      if (bullet != null) {
        final indent = (bullet[1]!.length ~/ 2) * 12.0;
        children.add(Padding(
          padding: EdgeInsets.only(left: indent, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: body),
              Expanded(child: Text(plainInline(bullet[3]!), style: body)),
            ],
          ),
        ));
        continue;
      }

      children.add(Text(plainInline(line.trim()), style: body));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
