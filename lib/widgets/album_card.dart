import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/jellyfin_models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../audio/queue_notifier.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// AlbumCard widget
// ---------------------------------------------------------------------------

class AlbumCard extends ConsumerWidget {
  final JellyfinAlbum album;
  const AlbumCard({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(jellyfinServiceProvider);
    final imageUrl = (service != null && album.imageTag != null)
        ? service.getImageUrl(album.id, album.imageTag!)
        : null;

    return GestureDetector(
      onTap: () => context.push('/album/${album.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) => _placeholder(),
                      errorWidget: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.name,
            style: Theme.of(context).textTheme.labelLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            album.artist,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Center(
        child: Icon(Icons.album, color: AppColors.textMuted, size: 40),
      ),
    );
  }
}
