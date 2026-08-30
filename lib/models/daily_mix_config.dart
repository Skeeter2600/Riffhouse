import 'dart:convert';
import 'package:uuid/uuid.dart';

enum DailyMixSlotType { music, podcast }

enum PodcastSelectionType { specific, anySubscribed, news, nonNews }

enum EpisodeSelectionMode { latest, latestUnheard }

enum MusicSourceType {
  frequentlyPlayed,
  recentlyPlayed,
  undiscovered,
  smartMix,
  genre,
  playlist,
  artist,
}

class DailyMixSlotConfig {
  final String id;
  final DailyMixSlotType slotType;

  // Podcast options
  final PodcastSelectionType podcastSelectionType;
  final List<String> podcastFeedIds;
  final EpisodeSelectionMode episodeSelection;
  final int podcastCount;

  // Music options
  final MusicSourceType musicSourceType;
  final List<String> selectedGenres;
  final List<String> selectedPlaylistIds;
  final List<String> selectedArtistIds;
  final bool isCountRange;
  final int fixedCount;
  final int minCount;
  final int maxCount;

  DailyMixSlotConfig({
    String? id,
    required this.slotType,
    this.podcastSelectionType = PodcastSelectionType.specific,
    this.podcastFeedIds = const [],
    this.episodeSelection = EpisodeSelectionMode.latest,
    this.podcastCount = 1,
    this.musicSourceType = MusicSourceType.frequentlyPlayed,
    this.selectedGenres = const [],
    this.selectedPlaylistIds = const [],
    this.selectedArtistIds = const [],
    this.isCountRange = false,
    this.fixedCount = 5,
    this.minCount = 5,
    this.maxCount = 10,
  }) : id = id ?? const Uuid().v4();

  DailyMixSlotConfig copyWith({
    String? id,
    DailyMixSlotType? slotType,
    PodcastSelectionType? podcastSelectionType,
    List<String>? podcastFeedIds,
    EpisodeSelectionMode? episodeSelection,
    int? podcastCount,
    MusicSourceType? musicSourceType,
    List<String>? selectedGenres,
    List<String>? selectedPlaylistIds,
    List<String>? selectedArtistIds,
    bool? isCountRange,
    int? fixedCount,
    int? minCount,
    int? maxCount,
  }) {
    return DailyMixSlotConfig(
      id: id ?? this.id,
      slotType: slotType ?? this.slotType,
      podcastSelectionType: podcastSelectionType ?? this.podcastSelectionType,
      podcastFeedIds: podcastFeedIds ?? this.podcastFeedIds,
      episodeSelection: episodeSelection ?? this.episodeSelection,
      podcastCount: podcastCount ?? this.podcastCount,
      musicSourceType: musicSourceType ?? this.musicSourceType,
      selectedGenres: selectedGenres ?? this.selectedGenres,
      selectedPlaylistIds: selectedPlaylistIds ?? this.selectedPlaylistIds,
      selectedArtistIds: selectedArtistIds ?? this.selectedArtistIds,
      isCountRange: isCountRange ?? this.isCountRange,
      fixedCount: fixedCount ?? this.fixedCount,
      minCount: minCount ?? this.minCount,
      maxCount: maxCount ?? this.maxCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'slotType': slotType.name,
        'podcastSelectionType': podcastSelectionType.name,
        'podcastFeedIds': podcastFeedIds,
        'episodeSelection': episodeSelection.name,
        'podcastCount': podcastCount,
        'musicSourceType': musicSourceType.name,
        'selectedGenres': selectedGenres,
        'selectedPlaylistIds': selectedPlaylistIds,
        'selectedArtistIds': selectedArtistIds,
        'isCountRange': isCountRange,
        'fixedCount': fixedCount,
        'minCount': minCount,
        'maxCount': maxCount,
      };

  factory DailyMixSlotConfig.fromJson(Map<String, dynamic> json) {
    return DailyMixSlotConfig(
      id: json['id'] as String?,
      slotType: DailyMixSlotType.values.firstWhere(
        (e) => e.name == json['slotType'],
        orElse: () => DailyMixSlotType.music,
      ),
      podcastSelectionType: PodcastSelectionType.values.firstWhere(
        (e) => e.name == json['podcastSelectionType'],
        orElse: () => PodcastSelectionType.specific,
      ),
      podcastFeedIds: List<String>.from(json['podcastFeedIds'] as List? ?? []),
      episodeSelection: EpisodeSelectionMode.values.firstWhere(
        (e) => e.name == json['episodeSelection'],
        orElse: () => EpisodeSelectionMode.latest,
      ),
      podcastCount: json['podcastCount'] as int? ?? 1,
      musicSourceType: MusicSourceType.values.firstWhere(
        (e) => e.name == json['musicSourceType'],
        orElse: () => MusicSourceType.frequentlyPlayed,
      ),
      selectedGenres: List<String>.from(json['selectedGenres'] as List? ?? []),
      selectedPlaylistIds:
          List<String>.from(json['selectedPlaylistIds'] as List? ?? []),
      selectedArtistIds:
          List<String>.from(json['selectedArtistIds'] as List? ?? []),
      isCountRange: json['isCountRange'] as bool? ?? false,
      fixedCount: json['fixedCount'] as int? ?? 5,
      minCount: json['minCount'] as int? ?? 5,
      maxCount: json['maxCount'] as int? ?? 10,
    );
  }

  String getDisplayTitle({
    Map<String, String>? feedTitleMap,
    Map<String, String>? playlistTitleMap,
  }) {
    if (slotType == DailyMixSlotType.podcast) {
      if (podcastSelectionType == PodcastSelectionType.specific) {
        if (podcastFeedIds.isEmpty) return 'Podcast (Select Feeds)';
        if (podcastFeedIds.length == 1) {
          final feedId = podcastFeedIds.first;
          final title = feedTitleMap?[feedId] ?? _formatKnownFeedId(feedId);
          return 'Podcast: $title';
        }
        return '1 of ${podcastFeedIds.length} Podcasts';
      } else if (podcastSelectionType == PodcastSelectionType.news) {
        return 'News Podcast';
      } else if (podcastSelectionType == PodcastSelectionType.nonNews) {
        return 'Non-News Podcast';
      } else {
        return 'Subscribed Podcast';
      }
    } else {
      switch (musicSourceType) {
        case MusicSourceType.frequentlyPlayed:
          return 'Frequently Played';
        case MusicSourceType.recentlyPlayed:
          return 'Recently Played';
        case MusicSourceType.undiscovered:
          return 'New Discoveries';
        case MusicSourceType.smartMix:
          return 'Smart Mix (Curated)';
        case MusicSourceType.genre:
          if (selectedGenres.isEmpty) return 'Genre (Select)';
          if (selectedGenres.length == 1) return 'Genre: ${selectedGenres.first}';
          return '${selectedGenres.length} Genres';
        case MusicSourceType.playlist:
          if (selectedPlaylistIds.isEmpty) return 'Playlist (Select)';
          if (selectedPlaylistIds.length == 1) {
            final pid = selectedPlaylistIds.first;
            final title = playlistTitleMap?[pid] ?? 'Playlist';
            return 'Playlist: $title';
          }
          return '${selectedPlaylistIds.length} Playlists';
        case MusicSourceType.artist:
          return 'Artist Tracks';
      }
    }
  }

  static String _formatKnownFeedId(String id) {
    const known = {
      'up_first': 'Up First',
      'marketplace': 'Marketplace',
      'the_daily': 'The Daily',
      'npr_news_now': 'NPR News Now',
      'wsj_tech_news': 'WSJ Tech News',
      'bbc_minute': 'BBC Minute',
    };
    if (known.containsKey(id)) return known[id]!;
    return id
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  String getDisplaySubtitle() {
    if (slotType == DailyMixSlotType.podcast) {
      final epStr = podcastCount == 1 ? '1 episode' : '$podcastCount episodes';
      final modeStr = episodeSelection == EpisodeSelectionMode.latestUnheard
          ? 'unheard'
          : 'latest';
      return '$epStr • $modeStr';
    } else {
      final countStr = isCountRange
          ? '$minCount–$maxCount songs'
          : '$fixedCount ${fixedCount == 1 ? 'song' : 'songs'}';
      if (musicSourceType == MusicSourceType.genre && selectedGenres.isNotEmpty) {
        return '$countStr • ${selectedGenres.join(', ')}';
      }
      return countStr;
    }
  }
}

class DailyMixConfig {
  final List<DailyMixSlotConfig> slots;

  const DailyMixConfig({required this.slots});

  DailyMixConfig copyWith({List<DailyMixSlotConfig>? slots}) {
    return DailyMixConfig(slots: slots ?? this.slots);
  }

  Map<String, dynamic> toJson() => {
        'slots': slots.map((s) => s.toJson()).toList(),
      };

  factory DailyMixConfig.fromJson(Map<String, dynamic> json) {
    final rawSlots = json['slots'] as List? ?? [];
    return DailyMixConfig(
      slots: rawSlots
          .map((s) => DailyMixSlotConfig.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Default configuration mirroring the built-in Daily Drive / Mix structure
  factory DailyMixConfig.defaultConfig() {
    return DailyMixConfig(
      slots: [
        // 1. Up First (latest episode)
        DailyMixSlotConfig(
          slotType: DailyMixSlotType.podcast,
          podcastSelectionType: PodcastSelectionType.specific,
          podcastFeedIds: ['up_first'],
          episodeSelection: EpisodeSelectionMode.latest,
          podcastCount: 1,
        ),
        // 2. 5 Frequently Played songs
        DailyMixSlotConfig(
          slotType: DailyMixSlotType.music,
          musicSourceType: MusicSourceType.frequentlyPlayed,
          fixedCount: 5,
        ),
        // 3. Marketplace (latest episode)
        DailyMixSlotConfig(
          slotType: DailyMixSlotType.podcast,
          podcastSelectionType: PodcastSelectionType.specific,
          podcastFeedIds: ['marketplace'],
          episodeSelection: EpisodeSelectionMode.latest,
          podcastCount: 1,
        ),
        // 4. 5 Recently Listened songs
        DailyMixSlotConfig(
          slotType: DailyMixSlotType.music,
          musicSourceType: MusicSourceType.recentlyPlayed,
          fixedCount: 5,
        ),
        // 5. 1 unheard non-news podcast episode
        DailyMixSlotConfig(
          slotType: DailyMixSlotType.podcast,
          podcastSelectionType: PodcastSelectionType.nonNews,
          episodeSelection: EpisodeSelectionMode.latestUnheard,
          podcastCount: 1,
        ),
        // 6. 5 new discoveries
        DailyMixSlotConfig(
          slotType: DailyMixSlotType.music,
          musicSourceType: MusicSourceType.undiscovered,
          fixedCount: 5,
        ),
        // 7. 1 unheard podcast of different genre
        DailyMixSlotConfig(
          slotType: DailyMixSlotType.podcast,
          podcastSelectionType: PodcastSelectionType.nonNews,
          episodeSelection: EpisodeSelectionMode.latestUnheard,
          podcastCount: 1,
        ),
        // 8. 20 undiscovered songs
        DailyMixSlotConfig(
          slotType: DailyMixSlotType.music,
          musicSourceType: MusicSourceType.undiscovered,
          fixedCount: 20,
        ),
      ],
    );
  }
}
