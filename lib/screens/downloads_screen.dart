import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cachedAsync = ref.watch(cachedTracksProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Downloads'),
      ),
      body: cachedAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.textMuted))),
        data: (tracks) {
          final totalBytes =
              tracks.fold<int>(0, (sum, t) => sum + t.sizeBytes);
          return Column(
            children: [
              // Header
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.2),
                      AppColors.card,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.glassBorder, width: 0.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storage_rounded,
                        color: AppColors.primary, size: 28),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatBytes(totalBytes),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${tracks.length} tracks downloaded',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // List
              Expanded(
                child: tracks.isEmpty
                    ? _emptyState(context)
                    : ListView.separated(
                        itemCount: tracks.length,
                        separatorBuilder: (_, __) => const Divider(
                            color: AppColors.surfaceVariant, height: 1),
                        itemBuilder: (ctx, i) =>
                            _CachedTrackTile(track: tracks[i]),
                      ),
              ),

              // Clear All button
              if (tracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmClearAll(context, ref),
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    label: const Text('Clear All Downloads',
                        style: TextStyle(color: Colors.redAccent)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.download_outlined,
              color: AppColors.textMuted, size: 64),
          const SizedBox(height: 16),
          Text('No downloads yet',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Download tracks to listen offline',
              style: TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All Downloads',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This will delete all downloaded tracks from your device.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(cachedTracksProvider.notifier).clearAll();
            },
            child:
                const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cached track tile
// ---------------------------------------------------------------------------

class _CachedTrackTile extends ConsumerWidget {
  final CachedTrack track;
  const _CachedTrackTile({required this.track});

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.music_note_rounded,
            color: AppColors.primary, size: 24),
      ),
      title: Text(
        track.jellyfinId,
        style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _formatBytes(track.sizeBytes),
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
        onPressed: () => ref
            .read(cachedTracksProvider.notifier)
            .deleteTrack(track.jellyfinId),
      ),
    );
  }
}
