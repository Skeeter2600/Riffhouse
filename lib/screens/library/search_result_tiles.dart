part of '../library_screen.dart';

// ---------------------------------------------------------------------------
// Search Result Tiles for Library Search
// ---------------------------------------------------------------------------

class _PlaylistResultTile extends ConsumerWidget {
  final JellyfinPlaylist playlist;
  const _PlaylistResultTile({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(musicServiceProvider);
    final imageUrl = (service != null && playlist.imageTag != null)
        ? service.getImageUrl(playlist.id, playlist.imageTag!)
        : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: LocalCoverOr(
            itemId: playlist.id,
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const ArtPlaceholder(icon: Icons.queue_music_rounded),
                  )
                : const ArtPlaceholder(icon: Icons.queue_music_rounded),
          ),
        ),
      ),
      title: Text(
        playlist.name,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${playlist.trackCount} tracks',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: () => context.push('/playlist/${playlist.id}'),
    );
  }
}

class _AlbumResultTile extends ConsumerWidget {
  final JellyfinAlbum album;
  const _AlbumResultTile({required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(musicServiceProvider);
    final imageUrl = (service != null && album.imageTag != null)
        ? service.getImageUrl(album.id, album.imageTag!)
        : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const ArtPlaceholder(icon: Icons.album_rounded),
                )
              : const ArtPlaceholder(icon: Icons.album_rounded),
        ),
      ),
      title: Text(
        album.name,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        album.artist,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: () => context.push('/album/${album.id}'),
    );
  }
}

class _ArtistResultTile extends ConsumerWidget {
  final JellyfinArtist artist;
  const _ArtistResultTile({required this.artist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(musicServiceProvider);
    final imageUrl = (service != null && artist.imageTag != null)
        ? service.getImageUrl(artist.id, artist.imageTag!)
        : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.surfaceVariant,
        backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
        child: imageUrl == null
            ? const Icon(Icons.person_rounded, color: AppColors.textMuted, size: 24)
            : null,
      ),
      title: Text(
        artist.name,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: () => context.push('/artist/${artist.id}'),
    );
  }
}

// ---------------------------------------------------------------------------
// Genre Search Result Tile — opens a SmartMixDetailScreen for the genre
// ---------------------------------------------------------------------------

class _GenreSearchResultTile extends ConsumerWidget {
  final String genre;
  const _GenreSearchResultTile({required this.genre});

  static const _palette = [
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
    [Color(0xFF10B981), Color(0xFF047857)],
    [Color(0xFFF97316), Color(0xFFC2410C)],
    [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
    [Color(0xFFEC4899), Color(0xFFBE185D)],
    [Color(0xFF14B8A6), Color(0xFF0F766E)],
    [Color(0xFFEAB308), Color(0xFFA16207)],
    [Color(0xFF6366F1), Color(0xFF4338CA)],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = _palette[genre.hashCode.abs() % _palette.length];
    final mixType = 'genre_${Uri.encodeComponent(genre)}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 24),
      ),
      title: Text(
        '$genre Mix',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: const Text(
        'Genre Mix · Tap to play',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: () => context.push('/smart-mix/$mixType'),
    );
  }
}
