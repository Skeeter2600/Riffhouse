import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/daily_mix_config.dart';
import '../providers/library_provider.dart';
import '../providers/podcast_provider.dart';
import '../theme/app_theme.dart';

class DailyMixConfigScreen extends ConsumerStatefulWidget {
  const DailyMixConfigScreen({super.key});

  @override
  ConsumerState<DailyMixConfigScreen> createState() => _DailyMixConfigScreenState();
}

class _DailyMixConfigScreenState extends ConsumerState<DailyMixConfigScreen> {
  DailyMixConfig? _workingConfig;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final configAsync = ref.read(dailyMixConfigProvider);
      final initial = configAsync.valueOrNull ?? DailyMixConfig.defaultConfig();
      setState(() {
        _workingConfig = DailyMixConfig(slots: List.from(initial.slots));
      });
    });
  }

  void _markChanged() {
    setState(() {
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final feeds = ref.watch(subscribedFeedsProvider).valueOrNull ?? [];
    final playlists = ref.watch(playlistsProvider).valueOrNull ?? [];

    final feedTitleMap = {for (final f in feeds) f.id: f.title};
    final playlistTitleMap = {for (final p in playlists) p.id: p.name};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Customize Daily Drive'),
        leading: BackButton(
          color: AppColors.textPrimary,
          onPressed: () {
            if (_hasChanges) {
              _confirmDiscard();
            } else {
              context.pop();
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore_rounded, color: AppColors.textSecondary),
            tooltip: 'Reset to Defaults',
            onPressed: _confirmReset,
          ),
          IconButton(
            icon: const Icon(Icons.check_rounded, color: AppColors.primaryLight, size: 28),
            tooltip: 'Save Mix',
            onPressed: _saveAndApply,
          ),
        ],
      ),
      body: _workingConfig == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                // Info banner
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 0.5),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.tune_rounded, color: AppColors.primaryLight, size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Drag to reorder slots. Tap any slot to customize podcasts, genres, or song counts.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

                // Reorderable list
                Expanded(
                  child: _workingConfig!.slots.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.playlist_remove_rounded, color: AppColors.textMuted, size: 54),
                              const SizedBox(height: 12),
                              const Text('No slots in mix', style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _addNewSlot,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Slot'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(130, 42),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: _workingConfig!.slots.length,
                          // ignore: deprecated_member_use
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex--;
                              final slots = List<DailyMixSlotConfig>.from(_workingConfig!.slots);
                              final item = slots.removeAt(oldIndex);
                              slots.insert(newIndex, item);
                              _workingConfig = _workingConfig!.copyWith(slots: slots);
                              _markChanged();
                            });
                          },
                          itemBuilder: (context, index) {
                            final slot = _workingConfig!.slots[index];
                            return _SlotTile(
                              key: ValueKey(slot.id),
                              index: index + 1,
                              itemIndex: index,
                              slot: slot,
                              feedTitleMap: feedTitleMap,
                              playlistTitleMap: playlistTitleMap,
                              onEdit: () => _editSlot(index, slot),
                              onDelete: () {
                                setState(() {
                                  final slots = List<DailyMixSlotConfig>.from(_workingConfig!.slots);
                                  slots.removeAt(index);
                                  _workingConfig = _workingConfig!.copyWith(slots: slots);
                                  _markChanged();
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewSlot,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Slot', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.glassBorder, width: 0.5)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    if (_hasChanges) {
                      _confirmDiscard();
                    } else {
                      context.pop();
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.glassBorder),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveAndApply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save Mix', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addNewSlot() {
    final newSlot = DailyMixSlotConfig(
      slotType: DailyMixSlotType.music,
      musicSourceType: MusicSourceType.frequentlyPlayed,
      fixedCount: 5,
    );
    _showSlotEditor(
      slot: newSlot,
      title: 'Add New Slot',
      onSave: (savedSlot) {
        setState(() {
          final slots = List<DailyMixSlotConfig>.from(_workingConfig!.slots)..add(savedSlot);
          _workingConfig = _workingConfig!.copyWith(slots: slots);
          _markChanged();
        });
      },
    );
  }

  void _editSlot(int index, DailyMixSlotConfig slot) {
    _showSlotEditor(
      slot: slot,
      title: 'Edit Slot #${index + 1}',
      onSave: (savedSlot) {
        setState(() {
          final slots = List<DailyMixSlotConfig>.from(_workingConfig!.slots);
          slots[index] = savedSlot;
          _workingConfig = _workingConfig!.copyWith(slots: slots);
          _markChanged();
        });
      },
    );
  }

  void _showSlotEditor({
    required DailyMixSlotConfig slot,
    required String title,
    required ValueChanged<DailyMixSlotConfig> onSave,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SlotEditorSheet(
        initialSlot: slot,
        title: title,
        onSave: (res) {
          Navigator.pop(ctx);
          onSave(res);
        },
      ),
    );
  }

  Future<void> _saveAndApply() async {
    if (_workingConfig == null) return;
    await ref.read(dailyMixConfigProvider.notifier).saveConfig(_workingConfig!);
    ref.invalidate(smartMixTracksProvider('daily_drive'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Daily Drive customized successfully!'),
          backgroundColor: AppColors.primary,
        ),
      );
      context.pop();
    }
  }

  Future<void> _confirmReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset to Defaults?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This will restore the original daily drive mix (Up First, Frequently Played, Marketplace, Recent, and Discoveries).',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(80, 38),
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final defaultCfg = DailyMixConfig.defaultConfig();
      setState(() {
        _workingConfig = DailyMixConfig(slots: List.from(defaultCfg.slots));
        _markChanged();
      });
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Discard changes?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('You have unsaved changes to your daily drive configuration.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Editing', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(80, 38),
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (discard == true && mounted) {
      context.pop();
    }
  }
}

// ---------------------------------------------------------------------------
// Slot Item Tile
// ---------------------------------------------------------------------------

class _SlotTile extends StatelessWidget {
  final int index;
  final int itemIndex;
  final DailyMixSlotConfig slot;
  final Map<String, String> feedTitleMap;
  final Map<String, String> playlistTitleMap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SlotTile({
    super.key,
    required this.index,
    required this.itemIndex,
    required this.slot,
    required this.feedTitleMap,
    required this.playlistTitleMap,
    required this.onEdit,
    required this.onDelete,
  });

  Color get _slotColor {
    if (slot.slotType == DailyMixSlotType.podcast) {
      return const Color(0xFFF59E0B);
    }
    switch (slot.musicSourceType) {
      case MusicSourceType.frequentlyPlayed:
        return const Color(0xFFEC4899);
      case MusicSourceType.recentlyPlayed:
        return const Color(0xFF7C3AED);
      case MusicSourceType.undiscovered:
        return const Color(0xFF06B6D4);
      case MusicSourceType.smartMix:
        return AppColors.primary;
      case MusicSourceType.genre:
        return const Color(0xFF10B981);
      case MusicSourceType.playlist:
        return const Color(0xFF3B82F6);
      case MusicSourceType.artist:
        return const Color(0xFF8B5CF6);
    }
  }

  IconData get _slotIcon {
    if (slot.slotType == DailyMixSlotType.podcast) {
      return Icons.podcasts_rounded;
    }
    switch (slot.musicSourceType) {
      case MusicSourceType.frequentlyPlayed:
        return Icons.local_fire_department_rounded;
      case MusicSourceType.recentlyPlayed:
        return Icons.history_rounded;
      case MusicSourceType.undiscovered:
        return Icons.explore_rounded;
      case MusicSourceType.smartMix:
        return Icons.auto_awesome;
      case MusicSourceType.genre:
        return Icons.category_rounded;
      case MusicSourceType.playlist:
        return Icons.queue_music_rounded;
      case MusicSourceType.artist:
        return Icons.person_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder, width: 0.5),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$index',
                  style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _slotColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_slotIcon, color: _slotColor, size: 22),
                ),
              ],
            ),
            title: Text(
              slot.getDisplayTitle(
                feedTitleMap: feedTitleMap,
                playlistTitleMap: playlistTitleMap,
              ),
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              slot.getDisplaySubtitle(),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.textMuted, size: 20),
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                  onPressed: onDelete,
                ),
                ReorderableDragStartListener(
                  index: itemIndex,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Icon(Icons.drag_handle_rounded, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
            onTap: onEdit,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slot Editor Bottom Sheet
// ---------------------------------------------------------------------------

class _SlotEditorSheet extends ConsumerStatefulWidget {
  final DailyMixSlotConfig initialSlot;
  final String title;
  final ValueChanged<DailyMixSlotConfig> onSave;

  const _SlotEditorSheet({
    required this.initialSlot,
    required this.title,
    required this.onSave,
  });

  @override
  ConsumerState<_SlotEditorSheet> createState() => _SlotEditorSheetState();
}

class _SlotEditorSheetState extends ConsumerState<_SlotEditorSheet> {
  late DailyMixSlotType _slotType;

  // Podcast
  late PodcastSelectionType _podcastSelectionType;
  late List<String> _podcastFeedIds;
  late EpisodeSelectionMode _episodeSelection;
  late int _podcastCount;

  // Music
  late MusicSourceType _musicSourceType;
  late List<String> _selectedGenres;
  late List<String> _selectedPlaylistIds;
  late bool _isCountRange;
  late int _fixedCount;
  late int _minCount;
  late int _maxCount;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSlot;
    _slotType = s.slotType;

    _podcastSelectionType = s.podcastSelectionType;
    _podcastFeedIds = List.from(s.podcastFeedIds);
    _episodeSelection = s.episodeSelection;
    _podcastCount = s.podcastCount;

    _musicSourceType = s.musicSourceType;
    _selectedGenres = List.from(s.selectedGenres);
    _selectedPlaylistIds = List.from(s.selectedPlaylistIds);
    _isCountRange = s.isCountRange;
    _fixedCount = s.fixedCount;
    _minCount = s.minCount;
    _maxCount = s.maxCount;
  }

  @override
  Widget build(BuildContext context) {
    final feedsAsync = ref.watch(subscribedFeedsProvider);
    final playlistsAsync = ref.watch(playlistsProvider);
    final topGenresAsync = ref.watch(topGenresProvider);
    final allTracksAsync = ref.watch(tracksProvider);

    // Extract unique genres from library
    final allTracks = allTracksAsync.valueOrNull ?? [];
    final allGenresSet = <String>{};
    for (final t in allTracks) {
      allGenresSet.addAll(t.genres);
    }
    final allGenres = allGenresSet.toList()..sort((a, b) => a.compareTo(b));
    final topGenres = topGenresAsync.valueOrNull ?? [];

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final updated = widget.initialSlot.copyWith(
                        slotType: _slotType,
                        podcastSelectionType: _podcastSelectionType,
                        podcastFeedIds: _podcastFeedIds,
                        episodeSelection: _episodeSelection,
                        podcastCount: _podcastCount,
                        musicSourceType: _musicSourceType,
                        selectedGenres: _selectedGenres,
                        selectedPlaylistIds: _selectedPlaylistIds,
                        isCountRange: _isCountRange,
                        fixedCount: _fixedCount,
                        minCount: _minCount,
                        maxCount: _maxCount,
                      );
                      widget.onSave(updated);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(60, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.glassBorder, height: 1),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Slot Type Toggle
                  const Text('Slot Content Type', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<DailyMixSlotType>(
                    segments: const [
                      ButtonSegment(
                        value: DailyMixSlotType.music,
                        label: Text('Music Songs'),
                        icon: Icon(Icons.music_note_rounded),
                      ),
                      ButtonSegment(
                        value: DailyMixSlotType.podcast,
                        label: Text('Podcast Episode'),
                        icon: Icon(Icons.podcasts_rounded),
                      ),
                    ],
                    selected: {_slotType},
                    onSelectionChanged: (set) => setState(() => _slotType = set.first),
                  ),
                  const SizedBox(height: 24),

                  if (_slotType == DailyMixSlotType.podcast) ...[
                    // --- PODCAST CONFIG ---
                    const Text('Podcast Feed Selection', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Specific Feed(s)'),
                          selected: _podcastSelectionType == PodcastSelectionType.specific,
                          onSelected: (_) => setState(() => _podcastSelectionType = PodcastSelectionType.specific),
                        ),
                        ChoiceChip(
                          label: const Text('Any Subscribed Feed'),
                          selected: _podcastSelectionType == PodcastSelectionType.anySubscribed,
                          onSelected: (_) => setState(() => _podcastSelectionType = PodcastSelectionType.anySubscribed),
                        ),
                        ChoiceChip(
                          label: const Text('News Feed'),
                          selected: _podcastSelectionType == PodcastSelectionType.news,
                          onSelected: (_) => setState(() => _podcastSelectionType = PodcastSelectionType.news),
                        ),
                        ChoiceChip(
                          label: const Text('Non-News Feed'),
                          selected: _podcastSelectionType == PodcastSelectionType.nonNews,
                          onSelected: (_) => setState(() => _podcastSelectionType = PodcastSelectionType.nonNews),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_podcastSelectionType == PodcastSelectionType.specific) ...[
                      const Text('Select Podcast Feeds (Can select multiple):', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 8),
                      feedsAsync.when(
                        loading: () => const LinearProgressIndicator(color: AppColors.primary),
                        error: (e, _) => Text('Error loading feeds: $e', style: const TextStyle(color: Colors.redAccent)),
                        data: (feeds) {
                          if (feeds.isEmpty) {
                            return const Text('No subscribed podcasts found.', style: TextStyle(color: AppColors.textMuted));
                          }
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: feeds.map((feed) {
                              final isSelected = _podcastFeedIds.contains(feed.id);
                              return FilterChip(
                                label: Text(feed.title),
                                selected: isSelected,
                                onSelected: (sel) {
                                  setState(() {
                                    if (sel) {
                                      _podcastFeedIds.add(feed.id);
                                    } else {
                                      _podcastFeedIds.remove(feed.id);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    const Text('Episode Preference', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<EpisodeSelectionMode>(
                      segments: const [
                        ButtonSegment(
                          value: EpisodeSelectionMode.latest,
                          label: Text('Latest Episode'),
                        ),
                        ButtonSegment(
                          value: EpisodeSelectionMode.latestUnheard,
                          label: Text('Latest Unheard'),
                        ),
                      ],
                      selected: {_episodeSelection},
                      onSelectionChanged: (set) => setState(() => _episodeSelection = set.first),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Episode Count', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: AppColors.primary),
                              onPressed: _podcastCount > 1 ? () => setState(() => _podcastCount--) : null,
                            ),
                            Text('$_podcastCount', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                              onPressed: _podcastCount < 5 ? () => setState(() => _podcastCount++) : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else ...[
                    // --- MUSIC CONFIG ---
                    const Text('Music Category', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Frequently Played'),
                          selected: _musicSourceType == MusicSourceType.frequentlyPlayed,
                          onSelected: (_) => setState(() => _musicSourceType = MusicSourceType.frequentlyPlayed),
                        ),
                        ChoiceChip(
                          label: const Text('Recently Listened'),
                          selected: _musicSourceType == MusicSourceType.recentlyPlayed,
                          onSelected: (_) => setState(() => _musicSourceType = MusicSourceType.recentlyPlayed),
                        ),
                        ChoiceChip(
                          label: const Text('New Discoveries'),
                          selected: _musicSourceType == MusicSourceType.undiscovered,
                          onSelected: (_) => setState(() => _musicSourceType = MusicSourceType.undiscovered),
                        ),
                        ChoiceChip(
                          label: const Text('Smart Mix (25/25/50)'),
                          selected: _musicSourceType == MusicSourceType.smartMix,
                          onSelected: (_) => setState(() => _musicSourceType = MusicSourceType.smartMix),
                        ),
                        ChoiceChip(
                          label: const Text('Specific Genres'),
                          selected: _musicSourceType == MusicSourceType.genre,
                          onSelected: (_) => setState(() => _musicSourceType = MusicSourceType.genre),
                        ),
                        ChoiceChip(
                          label: const Text('From Playlist(s)'),
                          selected: _musicSourceType == MusicSourceType.playlist,
                          onSelected: (_) => setState(() => _musicSourceType = MusicSourceType.playlist),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Specific Genre selector
                    if (_musicSourceType == MusicSourceType.genre) ...[
                      const Text('Select Genres (Can select multiple):', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (topGenres.isNotEmpty) ...[
                        const Text('Top Listened Genres:', style: TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: topGenres.map((g) {
                            final isSel = _selectedGenres.contains(g);
                            return FilterChip(
                              label: Text(g),
                              selected: isSel,
                              avatar: const Icon(Icons.star, size: 14, color: Colors.amber),
                              onSelected: (sel) {
                                setState(() {
                                  if (sel) {
                                    _selectedGenres.add(g);
                                  } else {
                                    _selectedGenres.remove(g);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text('All Library Genres:', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 6),
                      allGenres.isEmpty
                          ? const Text('No genres found in library.', style: TextStyle(color: AppColors.textMuted))
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: allGenres.map((g) {
                                final isSel = _selectedGenres.contains(g);
                                return FilterChip(
                                  label: Text(g),
                                  selected: isSel,
                                  onSelected: (sel) {
                                    setState(() {
                                      if (sel) {
                                        _selectedGenres.add(g);
                                      } else {
                                        _selectedGenres.remove(g);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                      const SizedBox(height: 20),
                    ],

                    // Specific Playlist selector
                    if (_musicSourceType == MusicSourceType.playlist) ...[
                      const Text('Select Playlists:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      playlistsAsync.when(
                        loading: () => const LinearProgressIndicator(color: AppColors.primary),
                        error: (e, _) => Text('Error loading playlists: $e', style: const TextStyle(color: Colors.redAccent)),
                        data: (playlists) {
                          if (playlists.isEmpty) {
                            return const Text('No playlists found.', style: TextStyle(color: AppColors.textMuted));
                          }
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: playlists.map((p) {
                              final isSel = _selectedPlaylistIds.contains(p.id);
                              return FilterChip(
                                label: Text(p.name),
                                selected: isSel,
                                onSelected: (sel) {
                                  setState(() {
                                    if (sel) {
                                      _selectedPlaylistIds.add(p.id);
                                    } else {
                                      _selectedPlaylistIds.remove(p.id);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Song Count Settings (Fixed vs Range)
                    const Text('Number of Songs', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Fixed Count'),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Random Range'),
                        ),
                      ],
                      selected: {_isCountRange},
                      onSelectionChanged: (set) => setState(() => _isCountRange = set.first),
                    ),
                    const SizedBox(height: 12),

                    if (!_isCountRange) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Count: $_fixedCount songs', style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: AppColors.primary),
                                onPressed: _fixedCount > 1 ? () => setState(() => _fixedCount--) : null,
                              ),
                              Text('$_fixedCount', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                                onPressed: _fixedCount < 50 ? () => setState(() => _fixedCount++) : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ] else ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Between $_minCount and $_maxCount songs',
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                          RangeSlider(
                            values: RangeValues(_minCount.toDouble(), _maxCount.toDouble()),
                            min: 1,
                            max: 30,
                            divisions: 29,
                            activeColor: AppColors.primary,
                            labels: RangeLabels('$_minCount', '$_maxCount'),
                            onChanged: (vals) {
                              setState(() {
                                _minCount = vals.start.round();
                                _maxCount = vals.end.round();
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
