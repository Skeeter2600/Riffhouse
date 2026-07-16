import 'jellyfin_models.dart';

class PodcastEpisode {
  final String guid;
  final String title;
  final String description;
  final String streamUrl;
  final DateTime pubDate;
  final String imageUrl;
  final Duration duration;
  final String podcastFeedId;
  final String podcastTitle;
  final String podcastPublisher;

  const PodcastEpisode({
    required this.guid,
    required this.title,
    required this.description,
    required this.streamUrl,
    required this.pubDate,
    required this.imageUrl,
    required this.duration,
    required this.podcastFeedId,
    required this.podcastTitle,
    required this.podcastPublisher,
  });

  /// Convert to JellyfinTrack so it plays in the existing audio player.
  JellyfinTrack toJellyfinTrack() {
    return JellyfinTrack(
      id: 'podcast_$guid',
      name: title,
      artists: [podcastPublisher],
      albumArtist: podcastPublisher,
      albumId: 'podcast_$podcastFeedId',
      albumName: podcastTitle,
      genres: const ['News', 'Podcast'],
      durationMs: duration.inMilliseconds,
      serverId: '',
      imageTag: imageUrl, // Store remote image URL as the image tag
      dateCreated: pubDate,
      remoteStreamUrl: streamUrl,
    );
  }
}
