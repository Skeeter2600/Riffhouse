import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/jellyfin_models.dart';
import '../providers/library_provider.dart';
import '../providers/auth_provider.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';

void showAddToPlaylistBottomSheet(BuildContext context, WidgetRef ref, JellyfinTrack track) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Consumer(
      builder: (context, ref, _) {
        final playlistsAsync = ref.watch(playlistsProvider);

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Add to Playlist',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 18),
                ),
              ),
              const Divider(color: AppColors.glassBorder, height: 1),
              
              // Option to create a new playlist
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.surfaceVariant,
                  child: Icon(Icons.add, color: AppColors.primary),
                ),
                title: const Text('Create New Playlist', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreateAndAddDialog(context, ref, track);
                },
              ),
              const Divider(color: AppColors.glassBorder, height: 1),
              
              // List of existing playlists
              Expanded(
                child: playlistsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.textMuted))),
                  data: (playlists) {
                    if (playlists.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No other playlists found', style: TextStyle(color: AppColors.textMuted)),
                      );
                    }
                    return ListView.builder(
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        return ListTile(
                          leading: const Icon(Icons.queue_music_rounded, color: AppColors.primary),
                          title: Text(playlist.name, style: const TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text('${playlist.trackCount} tracks', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          onTap: () async {
                            Navigator.pop(ctx);
                            final playlistService = ref.read(playlistServiceProvider);
                            final success = await playlistService.addTrackToPlaylist(playlist.id, track.id);
                            if (success) {
                              ref.invalidate(playlistsProvider);
                              ref.invalidate(playlistTracksProvider(playlist.id));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Added "${track.name}" to "${playlist.name}"'),
                                  backgroundColor: AppColors.primary,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to add track to playlist'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

void _showCreateAndAddDialog(BuildContext context, WidgetRef ref, JellyfinTrack track) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('New Playlist', style: TextStyle(color: AppColors.textPrimary)),
      content: TextField(
        controller: controller,
        style: const TextStyle(color: AppColors.textPrimary),
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Playlist name',
          hintStyle: TextStyle(color: AppColors.textMuted),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              Navigator.pop(ctx);
              final playlistService = ref.read(playlistServiceProvider);
              final newId = await playlistService.createPlaylistOnServer(name, [track.id]);
              if (newId != null) {
                ref.invalidate(playlistsProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Created playlist "$name" and added "${track.name}"'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to create playlist'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            }
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
