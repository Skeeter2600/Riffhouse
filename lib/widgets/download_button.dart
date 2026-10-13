import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/jellyfin_models.dart';
import '../providers/download_provider.dart';
import '../theme/app_theme.dart';

const _downloadedColor = Color(0xFF10B981);

/// Downloads an album for offline listening, shows progress while it runs
/// (tap to cancel) and removes the download again once it is complete.
class AlbumDownloadButton extends ConsumerWidget {
  final String albumId;
  final String albumName;
  final List<JellyfinTrack> tracks;

  const AlbumDownloadButton({
    super.key,
    required this.albumId,
    required this.albumName,
    required this.tracks,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadProvider);
    final notifier = ref.read(downloadProvider.notifier);
    final progress = downloads.batchProgress[albumId];
    final downloaded = downloads.downloadedAlbumIds.contains(albumId);

    if (progress != null) {
      return IconButton(
        tooltip: 'Cancel download '
            '(${progress.current}/${progress.total})',
        onPressed: () => notifier.cancelBatch(albumId),
        icon: SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress.total > 0
                    ? progress.current / progress.total
                    : null,
                strokeWidth: 2.5,
                color: AppColors.primary,
                backgroundColor: AppColors.surfaceVariant,
              ),
              const Icon(Icons.close_rounded,
                  size: 14, color: AppColors.textSecondary),
            ],
          ),
        ),
      );
    }

    if (downloaded) {
      return IconButton(
        tooltip: 'Remove download',
        icon: const Icon(Icons.download_done_rounded, color: _downloadedColor),
        onPressed: () async {
          await notifier.removeAlbumDownloads(albumId, tracks);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Removed "$albumName" from downloads')),
            );
          }
        },
      );
    }

    return IconButton(
      tooltip: 'Download album',
      icon: const Icon(Icons.download_rounded, color: AppColors.primary),
      onPressed: () async {
        await notifier.downloadAlbum(albumId, tracks);
        final message = ref.read(downloadProvider).message;
        if (message != null && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
  }
}

/// "Download" / "Remove download" entry for a track's context menu.
class TrackDownloadTile extends ConsumerWidget {
  final JellyfinTrack track;

  /// Called before the action runs, to close the menu.
  final VoidCallback onSelected;

  const TrackDownloadTile({
    super.key,
    required this.track,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadProvider);
    final pinned = downloads.pinnedTrackIds.contains(track.id);
    final busy = downloads.activeDownloadingIds.contains(track.id) ||
        downloads.queuedIds.contains(track.id);
    final messenger = ScaffoldMessenger.of(context);

    return ListTile(
      leading: Icon(
        pinned ? Icons.delete_outline_rounded : Icons.download_outlined,
        color: pinned ? Colors.redAccent : AppColors.primary,
      ),
      title: Text(
        pinned
            ? (busy ? 'Cancel Download' : 'Remove Download')
            : 'Download',
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      onTap: () async {
        onSelected();
        final notifier = ref.read(downloadProvider.notifier);
        if (pinned) {
          await notifier.removeDownloadedTrack(track.id);
          messenger.showSnackBar(
            SnackBar(content: Text('Removed "${track.name}" from downloads')),
          );
          return;
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text('Downloading "${track.name}"...'),
            backgroundColor: AppColors.primary,
          ),
        );
        final ok = await notifier.downloadSingleTrack(track);
        final message = ref.read(downloadProvider).message;
        if (!ok && message != null) {
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
  }
}
