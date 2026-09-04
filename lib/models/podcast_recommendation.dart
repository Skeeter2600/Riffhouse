/// Curated popular podcast recommendations to help users quickly discover and subscribe.
class RecommendedPodcast {
  final String title;
  final String publisher;
  final String category;
  final String rssUrl;
  final String description;

  const RecommendedPodcast({
    required this.title,
    required this.publisher,
    required this.category,
    required this.rssUrl,
    required this.description,
  });
}

const List<RecommendedPodcast> popularPodcastRecommendations = [
  RecommendedPodcast(
    title: 'Up First',
    publisher: 'NPR',
    category: 'News',
    rssUrl: 'https://feeds.npr.org/510318/podcast.xml',
    description: 'The three biggest stories of the day in 15 minutes, with NPR News reporting.',
  ),
  RecommendedPodcast(
    title: 'Marketplace',
    publisher: 'Marketplace / APM',
    category: 'Business',
    rssUrl: 'https://feeds.publicradio.org/public_feeds/marketplace/rss/rss.xml',
    description: "Every weekday, host Kai Ryssdal makes sense of business and the economy.",
  ),
  RecommendedPodcast(
    title: 'The Daily',
    publisher: 'The New York Times',
    category: 'News',
    rssUrl: 'https://feeds.simplecast.com/54nAGcIl',
    description: 'Twenty minutes a day, five days a week, hosted by Michael Barbaro.',
  ),
  RecommendedPodcast(
    title: 'Freakonomics Radio',
    publisher: 'Stephen J. Dubner',
    category: 'Economics',
    rssUrl: 'https://feeds.simplecast.com/Y8lFbOT4',
    description: 'Discover the hidden side of everything, from sleep to global economics.',
  ),
  RecommendedPodcast(
    title: 'Planet Money',
    publisher: 'NPR',
    category: 'Economics',
    rssUrl: 'https://feeds.npr.org/510289/podcast.xml',
    description: 'The economy explained through highly entertaining, narrative storytelling.',
  ),
  RecommendedPodcast(
    title: 'This American Life',
    publisher: 'This American Life',
    category: 'Storytelling',
    rssUrl: 'https://www.thisamericanlife.org/podcast/rss.xml',
    description: 'Compelling, narrative-driven stories about everyday people, hosted by Ira Glass.',
  ),
  RecommendedPodcast(
    title: 'Science Vs',
    publisher: 'Gimlet',
    category: 'Science',
    rssUrl: 'https://feeds.megaphone.fm/sciencevs',
    description: 'Takes on fads, findings, and what everyone is talking about with science.',
  ),
  RecommendedPodcast(
    title: '99% Invisible',
    publisher: 'Roman Mars',
    category: 'Design',
    rssUrl: 'https://feeds.simplecast.com/BqbsxVfO',
    description: 'All the thought that goes into the things we do not think about — architecture and design.',
  ),
  RecommendedPodcast(
    title: 'TED Talks Daily',
    publisher: 'TED',
    category: 'Technology',
    rssUrl: 'https://feeds.feedburner.com/TEDTalks_audio',
    description: 'Every weekday, thought-provoking ideas on every subject.',
  ),
  RecommendedPodcast(
    title: 'Stuff You Should Know',
    publisher: 'iHeartPodcasts',
    category: 'Education',
    rssUrl: 'https://www.omnycontent.com/d/playlist/e73c998e-6e60-432f-8610-ae210140c5b1/a91018a4-ea4f-4130-bf55-ae270180c327/44710ecc-10bb-48d1-93c7-ae270180c33e/podcast.rss',
    description: 'Explains everything from how champagne works to chaos theory.',
  ),
];
