import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:audio_service/audio_service.dart';

import '../audio/queue_notifier.dart';
import '../models/jellyfin_models.dart';
import '../providers/auth_provider.dart';
import '../providers/download_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_playlist_sheet.dart';
import 'package:image_picker/image_picker.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final String playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final tracksAsync = ref.watch(playlistTracksProvider(playlistId));
    final service = ref.watch(jellyfinServiceProvider);

    return playlistsAsync.when(
      loading: () => const Scaffold(
          body:
              Center(child: CircularProgressIndicator(color: AppColors.primary))),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('$e'))),
      data: (playlists) {
        final playlist = playlists.firstWhere(
          (p) => p.id == playlistId,
          orElse: () => JellyfinPlaylist(
              id: playlistId, name: 'Playlist', trackCount: 0),
        );
        final imageUrl = (service != null && playlist.imageTag != null)
            ? service.getImageUrl(playlist.id, playlist.imageTag!)
            : null;

        return PopScope(
          canPop: context.canPop(),
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            context.go('/home/library');
          },
          child: Scaffold(
          backgroundColor: AppColors.background,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.push('/playlist/$playlistId/add'),
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text('Add Songs', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          body: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.card,
            onRefresh: () async {
              ref.invalidate(playlistsProvider);
              ref.invalidate(playlistTracksProvider(playlistId));
              await ref.read(playlistTracksProvider(playlistId).future);
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 280,
                  pinned: true,
                  backgroundColor: AppColors.background,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.more_horiz_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => _showEditBottomSheet(context, ref, playlist, tracksAsync.valueOrNull ?? []),
                      tooltip: 'Playlist Options',
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                Container(color: AppColors.card),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary.withValues(alpha: 0.6),
                                  AppColors.background,
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child: const Icon(Icons.queue_music_rounded,
                                size: 80, color: AppColors.primary),
                          ),
                    stretchModes: const [StretchMode.zoomBackground],
                  ),
                ),

                // Info
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(playlist.name,
                            style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${playlist.trackCount} tracks',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Builder(
                              builder: (context) {
                                final isDownloaded = ref.watch(downloadProvider)
                                    .downloadedPlaylistIds
                                    .contains(playlistId);
                                if (!isDownloaded) return const SizedBox.shrink();
                                return const Row(
                                  children: [
                                    SizedBox(width: 8),
                                    Icon(Icons.download_done_rounded,
                                        color: Color(0xFF10B981), size: 16),
                                    SizedBox(width: 4),
                                    Text(
                                      'Downloaded',
                                      style: TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: tracksAsync.when(
                                loading: () => const SizedBox(),
                                error: (_, __) => const SizedBox(),
                                data: (tracks) => Row(
                                  children: [
                                    Expanded(
                                      child: _btn(
                                        icon: Icons.play_arrow_rounded,
                                        label: 'Play All',
                                        primary: true,
                                        onTap: () {
                                          ref
                                              .read(recentSelectionsProvider.notifier)
                                              .addSelection(playlistId, 'playlist');
                                          ref
                                              .read(queueNotifierProvider.notifier)
                                              .playQueue(
                                                tracks,
                                                0,
                                                fromType: 'playlist',
                                                fromId: playlistId,
                                                fromTitle: playlist.name,
                                              );
                                          ref
                                              .read(queueNotifierProvider.notifier)
                                              .setShuffleMode(AudioServiceShuffleMode.none);
                                          context.push('/player');
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _btn(
                                        icon: Icons.shuffle_rounded,
                                        label: 'Shuffle',
                                        primary: false,
                                        onTap: () {
                                          ref
                                              .read(recentSelectionsProvider.notifier)
                                              .addSelection(playlistId, 'playlist');
                                          final s = [...tracks]..shuffle();
                                          ref
                                              .read(queueNotifierProvider.notifier)
                                              .playQueue(
                                                s,
                                                0,
                                                fromType: 'playlist',
                                                fromId: playlistId,
                                                fromTitle: playlist.name,
                                              );
                                          ref
                                              .read(queueNotifierProvider.notifier)
                                              .setShuffleMode(AudioServiceShuffleMode.all);
                                          context.push('/player');
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Tracks
                tracksAsync.when(
                  loading: () => const SliverToBoxAdapter(
                    child: Center(
                        child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                      child: Center(child: Text('$e'))),
                  data: (tracks) => SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final t = tracks[i];
                        return _TrackItem(
                          track: t,
                          queue: tracks,
                          index: i,
                          playlistId: playlistId,
                          playlistName: playlist.name,
                        );
                      },
                      childCount: tracks.length,
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        ),
        );
      },
    );
  }

  void _confirmRemoveDownloads(
      BuildContext context, WidgetRef ref, String playlistId, String playlistName, List<JellyfinTrack> tracks) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Downloads',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Remove downloaded tracks for "$playlistName" from device?',
          style: const TextStyle(color: AppColors.textSecondary),
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
              ref
                  .read(downloadProvider.notifier)
                  .removePlaylistDownloads(playlistId, tracks);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditBottomSheet(
      BuildContext context, WidgetRef ref, JellyfinPlaylist playlist, List<JellyfinTrack> tracks) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (sheetContext, sheetRef, _) {
            final downloadState = sheetRef.watch(downloadProvider);
            final isDownloaded = downloadState.downloadedPlaylistIds.contains(playlist.id);
            final batchProgress = downloadState.batchProgress[playlist.id];
            final isBatchDownloading = batchProgress != null;

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Download Toggle
                  SwitchListTile(
                    secondary: Icon(
                      isDownloaded
                          ? Icons.download_done_rounded
                          : Icons.download_rounded,
                      color: isDownloaded ? const Color(0xFF10B981) : AppColors.primary,
                    ),
                    title: const Text('Download for Offline',
                        style: TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text(
                      isBatchDownloading
                          ? 'Downloading ${batchProgress.current}/${batchProgress.total}...'
                          : isDownloaded
                              ? 'Downloaded & saved to device'
                              : 'Keep songs downloaded on device',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    value: isDownloaded || isBatchDownloading,
                    activeThumbColor: const Color(0xFF10B981),
                    onChanged: isBatchDownloading
                        ? null
                        : (bool enable) async {
                            Navigator.pop(ctx);
                            if (enable) {
                              await ref
                                  .read(downloadProvider.notifier)
                                  .downloadPlaylist(playlist.id, tracks);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Downloading "${playlist.name}"...'),
                                    backgroundColor: AppColors.primary,
                                  ),
                                );
                              }
                            } else {
                              _confirmRemoveDownloads(context, ref, playlist.id, playlist.name, tracks);
                            }
                          },
                  ),

                  // Smart Add
                  ListTile(
                    leading: const Icon(Icons.auto_awesome_rounded, color: AppColors.primaryLight),
                    title: const Text('Smart Add Recommendations',
                        style: TextStyle(color: AppColors.textPrimary)),
                    subtitle: const Text('Swipe to add recommended songs tailored to this playlist',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      context.push('/playlist/${playlist.id}/smart-add');
                    },
                  ),

                  // Sync Option
                  ListTile(
                    leading: const Icon(Icons.sync_rounded, color: AppColors.secondary),
                    title: const Text('Sync with Server',
                        style: TextStyle(color: AppColors.textPrimary)),
                    subtitle: const Text('Refresh playlist tracks from Jellyfin',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      ref.invalidate(playlistsProvider);
                      ref.invalidate(playlistTracksProvider(playlist.id));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Syncing playlist with server...'),
                          duration: Duration(seconds: 1),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    },
                  ),

                  // Change Cover Art
                  ListTile(
                    leading: const Icon(Icons.image_outlined, color: AppColors.primary),
                    title: const Text('Change Cover Art',
                        style: TextStyle(color: AppColors.textPrimary)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final picker = ImagePicker();
                      final image = await picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        final bytes = await image.readAsBytes();
                        final mimeType = image.mimeType ?? 'image/jpeg';
                        final playlistService = ref.read(playlistServiceProvider);

                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Uploading cover art...'), duration: Duration(seconds: 2)),
                        );

                        final success = await playlistService.uploadPlaylistImage(playlist.id, bytes, mimeType);
                        if (!context.mounted) return;
                        if (success) {
                          ref.invalidate(playlistsProvider);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cover art updated successfully!'), backgroundColor: AppColors.primary),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to upload cover art'), backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    },
                  ),

                  // Delete Playlist
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    title: const Text('Delete Playlist',
                        style: TextStyle(color: AppColors.textPrimary)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          backgroundColor: AppColors.card,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: const Text('Delete Playlist', style: TextStyle(color: AppColors.textPrimary)),
                          content: Text('Are you sure you want to delete "${playlist.name}"? This action cannot be undone.', style: const TextStyle(color: AppColors.textSecondary)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogCtx, false),
                              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(dialogCtx, true),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                              child: const Text('Delete', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        final playlistService = ref.read(playlistServiceProvider);
                        final success = await playlistService.deletePlaylist(playlist.id);
                        if (!context.mounted) return;
                        if (success) {
                          ref.invalidate(playlistsProvider);
                          context.pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Deleted playlist "${playlist.name}"'), backgroundColor: AppColors.primary),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to delete playlist'), backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _btn({
    required IconData icon,
    required String label,
    required bool primary,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: primary
              ? const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark])
              : null,
          color: primary ? null : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: primary
              ? null
              : Border.all(color: AppColors.glassBorder, width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Track item
// ---------------------------------------------------------------------------

class _TrackItem extends ConsumerWidget {
  final JellyfinTrack track;
  final List<JellyfinTrack> queue;
  final int index;
  final String playlistId;
  final String playlistName;

  const _TrackItem({
    required this.track,
    required this.queue,
    required this.index,
    required this.playlistId,
    required this.playlistName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(jellyfinServiceProvider);
    final imageUrl = (service != null && track.imageTag != null)
        ? service.getImageUrl(track.id, track.imageTag!)
        : null;

    final cachedTracks = ref.watch(cachedTracksProvider).valueOrNull ?? [];
    final isCached = cachedTracks.any((c) => c.jellyfinId == track.id);
    final downloadState = ref.watch(downloadProvider);
    final isDownloading = downloadState.activeDownloadingIds.contains(track.id);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _ph(),
                )
              : _ph(),
        ),
      ),
      title: Text(track.name,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          if (isDownloading) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.primary),
            ),
            const SizedBox(width: 5),
          ] else if (isCached) ...[
            const Icon(Icons.download_done_rounded, color: Color(0xFF10B981), size: 14),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: Text(
              track.artists.join(', '),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert_rounded,
            color: AppColors.textMuted, size: 20),
        onPressed: () => _showContextMenu(context, ref, isCached),
      ),
      onTap: () {
        ref.read(recentSelectionsProvider.notifier).addSelection(playlistId, 'playlist');
        ref.read(queueNotifierProvider.notifier).playQueue(
              queue,
              index,
              fromType: 'playlist',
              fromId: playlistId,
              fromTitle: playlistName,
            );
        context.push('/player');
      },
      onLongPress: () => _showContextMenu(context, ref, isCached),
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref, bool isCached) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(
                isCached ? Icons.delete_outline_rounded : Icons.download_rounded,
                color: isCached ? Colors.redAccent : AppColors.primary,
              ),
              title: Text(
                isCached ? 'Remove from Downloads' : 'Download Track',
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                if (isCached) {
                  ref.read(downloadProvider.notifier).removeDownloadedTrack(track.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Removed "${track.name}" from downloads')),
                  );
                } else {
                  ref.read(downloadProvider.notifier).downloadSingleTrack(track);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Downloading "${track.name}"...'),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                }
              },
            ),
            if (track.albumId.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.album_outlined, color: AppColors.primary),
                title: const Text('Go to Album',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/album/${track.albumId}');
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded, color: AppColors.primary),
              title: const Text('Go to Artist',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                final artists = ref.read(artistsProvider).valueOrNull ?? [];
                final firstArtist = track.artists.firstOrNull ?? track.albumArtist;
                JellyfinArtist? artistObj;
                for (final a in artists) {
                  if (a.name.toLowerCase() == firstArtist.toLowerCase()) {
                    artistObj = a;
                    break;
                  }
                }
                if (artistObj != null) {
                  context.push('/artist/${artistObj.id}');
                } else {
                  context.go('/home/library');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add, color: AppColors.primary),
              title: const Text('Add to Other Playlist',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                showAddToPlaylistBottomSheet(context, ref, track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
              title: const Text('Remove from Playlist',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () async {
                Navigator.pop(ctx);
                final playlistService = ref.read(playlistServiceProvider);
                final success = await playlistService.removeTrackFromPlaylist(playlistId, track.id);
                if (!context.mounted) return;
                if (success) {
                  ref.invalidate(playlistTracksProvider(playlistId));
                  ref.invalidate(playlistsProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Removed "${track.name}" from playlist'),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to remove track from playlist'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _ph() => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.music_note, color: AppColors.textMuted),
      );
}

class _PlaylistSearchAndAddSection extends ConsumerStatefulWidget {
  final String playlistId;
  const _PlaylistSearchAndAddSection({required this.playlistId});

  @override
  ConsumerState<_PlaylistSearchAndAddSection> createState() =>
      _PlaylistSearchAndAddSectionState();
}

class _PlaylistSearchAndAddSectionState
    extends ConsumerState<_PlaylistSearchAndAddSection> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allTracksAsync = ref.watch(tracksProvider);
    final playlistTracksAsync = ref.watch(playlistTracksProvider(widget.playlistId));
    final service = ref.watch(jellyfinServiceProvider);

    final allTracks = allTracksAsync.valueOrNull ?? [];
    final playlistTracks = playlistTracksAsync.valueOrNull ?? [];
    final playlistTrackIds = playlistTracks.map((t) => t.id).toSet();

    final q = _query.toLowerCase().trim();
    final filtered = q.isEmpty
        ? <JellyfinTrack>[]
        : allTracks
            .where((t) =>
                t.name.toLowerCase().contains(q) ||
                t.artists.any((a) => a.toLowerCase().contains(q)) ||
                t.albumName.toLowerCase().contains(q))
            .take(5)
            .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: AppColors.glassBorder, height: 32),
          Text(
            'Add to this playlist',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 12),
          // Search box
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder, width: 0.5),
            ),
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search for tracks...',
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textMuted, size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 16),
          // Results
          if (filtered.isNotEmpty)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final track = filtered[index];
                final isAdded = playlistTrackIds.contains(track.id);
                final imageUrl = (service != null && track.imageTag != null)
                    ? service.getImageUrl(track.id, track.imageTag!)
                    : null;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _ph(),
                              placeholder: (_, __) => _ph(),
                            )
                          : _ph(),
                    ),
                  ),
                  title: Text(
                    track.name,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    track.artists.join(', '),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      isAdded ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                      color: isAdded ? Colors.green : AppColors.textSecondary,
                    ),
                    onPressed: isAdded
                        ? null
                        : () async {
                            final playlistService = ref.read(playlistServiceProvider);
                            final success = await playlistService.addTrackToPlaylist(
                              widget.playlistId,
                              track.id,
                            );
                            if (success) {
                              ref.invalidate(playlistsProvider);
                              ref.invalidate(playlistTracksProvider(widget.playlistId));
                            }
                          },
                  ),
                );
              },
            )
          else if (_query.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No tracks found',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ph() => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.music_note, color: AppColors.textMuted, size: 20),
      );
}
