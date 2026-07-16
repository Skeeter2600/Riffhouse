import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../audio/queue_notifier.dart';
import '../models/jellyfin_models.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';

class SmartMixDetailScreen extends ConsumerWidget {
  final String mixType;

  const SmartMixDetailScreen({super.key, required this.mixType});

  String _getTitle() {
    if (mixType == 'daily') return 'Daily Mix';
    if (mixType == 'heavy') return 'Heavy Rotation';
    if (mixType == 'undiscovered') return 'Undiscovered';
    return 'Smart Mix';
  }

  String _getSubtitle() {
    if (mixType == 'daily') return 'Curated weekly playlist based on your activity';
    if (mixType == 'heavy') return 'Your most played tracks on repeat';
    if (mixType == 'undiscovered') return 'Tracks from your library you haven\'t heard yet';
    return 'Your personalized smart mix';
  }

  List<Color> _getColors() {
    if (mixType == 'daily') return [const Color(0xFF7C3AED), const Color(0xFF4F46E5)];
    if (mixType == 'heavy') return [const Color(0xFFEC4899), const Color(0xFFBE185D)];
    if (mixType == 'undiscovered') return [const Color(0xFF06B6D4), const Color(0xFF0369A1)];
    return [AppColors.primary, AppColors.primaryDark];
  }

  IconData _getIcon() {
    if (mixType == 'daily') return Icons.auto_awesome;
    if (mixType == 'heavy') return Icons.replay_rounded;
    if (mixType == 'undiscovered') return Icons.explore_rounded;
    return Icons.music_note_rounded;
  }

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(smartMixTracksProvider(mixType));
    final service = ref.watch(jellyfinServiceProvider);
    final title = _getTitle();
    final subtitle = _getSubtitle();
    final colors = _getColors();
    final icon = _getIcon();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Parallax Header
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: AppColors.background,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: 80,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
              ),
              stretchModes: const [StretchMode.zoomBackground],
            ),
          ),

          // Info Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  
                  // Controls
                  tracksAsync.when(
                    loading: () => const SizedBox(),
                    error: (_, __) => const SizedBox(),
                    data: (tracks) {
                      if (tracks.isEmpty) return const SizedBox();
                      return Row(
                        children: [
                          Expanded(
                            child: _btn(
                              icon: Icons.play_arrow_rounded,
                              label: 'Play All',
                              primary: true,
                              onTap: () {
                                ref.read(queueNotifierProvider.notifier).playQueue(
                                  tracks,
                                  0,
                                  fromType: 'smart_mix',
                                  fromId: mixType,
                                  fromTitle: title,
                                );
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
                                final s = [...tracks]..shuffle();
                                ref.read(queueNotifierProvider.notifier).playQueue(
                                  s,
                                  0,
                                  fromType: 'smart_mix',
                                  fromId: mixType,
                                  fromTitle: title,
                                );
                                context.push('/player');
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Track List
          tracksAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
            ),
            error: (err, _) => SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Error loading tracks: $err'),
                ),
              ),
            ),
            data: (tracks) {
              if (tracks.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No tracks in this mix yet.',
                          style: TextStyle(color: AppColors.textMuted)),
                    ),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final t = tracks[i];
                    final imageUrl = (service != null && t.imageTag != null)
                        ? service.getImageUrl(t.id, t.imageTag!)
                        : null;

                    return InkWell(
                      onTap: () {
                        ref.read(queueNotifierProvider.notifier).playQueue(tracks, i);
                        context.push('/player');
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Row(
                          children: [
                            // Cover art
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: imageUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: imageUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(color: AppColors.surfaceVariant),
                                        errorWidget: (_, __, ___) => Container(color: AppColors.surfaceVariant),
                                      )
                                    : Container(
                                        color: AppColors.surfaceVariant,
                                        child: const Icon(Icons.music_note, color: AppColors.textMuted, size: 20),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.name,
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    t.artist,
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatDuration(t.durationMs),
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: tracks.length,
                ),
              );
            },
          ),
          
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
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
              ? const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark])
              : null,
          color: primary ? null : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: primary ? null : Border.all(color: AppColors.glassBorder, width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
