import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/jellyfin_models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';

class PlaylistAddTracksScreen extends ConsumerStatefulWidget {
  final String playlistId;
  const PlaylistAddTracksScreen({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistAddTracksScreen> createState() =>
      _PlaylistAddTracksScreenState();
}

class _PlaylistAddTracksScreenState
    extends ConsumerState<PlaylistAddTracksScreen> {
  final _controller = TextEditingController();
  String _query = '';
  // Track IDs added this session so button updates immediately
  final Set<String> _justAdded = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allTracksAsync = ref.watch(tracksProvider);
    final playlistTracksAsync =
        ref.watch(playlistTracksProvider(widget.playlistId));
    final service = ref.watch(jellyfinServiceProvider);

    final isLoading = allTracksAsync.isLoading;
    final allTracks = allTracksAsync.valueOrNull ?? [];
    final playlistTracks = playlistTracksAsync.valueOrNull ?? [];
    final playlistTrackIds =
        {...playlistTracks.map((t) => t.id), ..._justAdded};

    final q = _query.toLowerCase().trim();
    final filtered = q.isEmpty
        ? <JellyfinTrack>[]
        : allTracks
            .where((t) =>
                t.name.toLowerCase().contains(q) ||
                t.artists.any((a) => a.toLowerCase().contains(q)) ||
                t.albumName.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: const BackButton(color: AppColors.textPrimary),
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Search tracks to add...',
            hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: AppColors.textMuted),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: q.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading) ...[                  
                    const SizedBox(
                      width: 36, height: 36,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppColors.primary),
                    ),
                    const SizedBox(height: 16),
                    const Text('Loading your library...',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 15)),
                  ] else ...[                  
                    const Icon(Icons.search_rounded,
                        color: AppColors.textMuted, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Search ${allTracks.length} tracks to add',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 15),
                    ),
                  ],
                ],
              ),
            )
          : isLoading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 16),
                      Text('Loading library...',
                          style: TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                )
          : filtered.isEmpty
              ? const Center(
                  child: Text('No tracks found',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 15)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final track = filtered[index];
                    final isAdded = playlistTrackIds.contains(track.id);
                    final imageUrl =
                        (service != null && track.imageTag != null)
                            ? service.getImageUrl(track.id, track.imageTag!)
                            : null;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: imageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _placeholder(),
                                  placeholder: (_, __) => _placeholder(),
                                )
                              : _placeholder(),
                        ),
                      ),
                      title: Text(
                        track.name,
                        style: TextStyle(
                          color: isAdded
                              ? AppColors.textMuted
                              : AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        track.artists.join(', '),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isAdded
                          ? const Icon(Icons.check_circle_rounded,
                              color: Colors.green, size: 24)
                          : IconButton(
                              icon: const Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: AppColors.primary,
                                  size: 28),
                              onPressed: () async {
                                final playlistService =
                                    ref.read(playlistServiceProvider);
                                final success =
                                    await playlistService.addTrackToPlaylist(
                                  widget.playlistId,
                                  track.id,
                                );
                                if (success) {
                                  setState(() => _justAdded.add(track.id));
                                  ref.invalidate(playlistTracksProvider(
                                      widget.playlistId));
                                  ref.invalidate(playlistsProvider);
                                } else if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to add track'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              },
                            ),
                    );
                  },
                ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.music_note,
            color: AppColors.textMuted, size: 20),
      );
}
