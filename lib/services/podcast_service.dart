import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_feed.dart';

class PodcastService {
  static const String _listenedPrefsKey = 'listened_podcast_episodes';
  static const String _subscribedFeedsPrefsKey = 'subscribed_podcast_feeds';

  static final List<PodcastFeed> _defaultFeeds = [
    const PodcastFeed(
      id: 'up_first',
      title: 'Up First',
      publisher: 'NPR',
      rssUrl: 'https://feeds.npr.org/510318/podcast.xml',
      imageUrl: 'https://media.npr.org/images/podcasts/primary/510318.png',
      description: 'The three biggest stories of the day, with reporting and analysis from NPR News.',
      category: 'News',
    ),
    const PodcastFeed(
      id: 'bbc_global_news',
      title: 'Global News Podcast',
      publisher: 'BBC World Service',
      rssUrl: 'https://podcasts.files.bbci.co.uk/p02nq0gn.rss',
      imageUrl: 'https://ichef.bbci.co.uk/images/ic/1200x675/p03wq0gz.jpg',
      description: "The day's top stories from BBC News, with reports from around the world.",
      category: 'News',
    ),
    const PodcastFeed(
      id: 'marketplace',
      title: 'Marketplace',
      publisher: 'Marketplace / APM',
      rssUrl: 'https://feeds.publicradio.org/public_feeds/marketplace/rss/rss.xml',
      imageUrl: 'https://img.apmcdn.org/2cdc31dad47bb9956cb2728a8329beaab1035ea0/square/b9d891-20220203-marketplace-logo-2000.jpg',
      description: "Every weekday, host Kai Ryssdal helps you make sense of the day's business and economic news.",
      category: 'Business',
    ),
    const PodcastFeed(
      id: 'pop_culture_happy_hour',
      title: 'Pop Culture Happy Hour',
      publisher: 'NPR',
      rssUrl: 'https://feeds.npr.org/510282/podcast.xml',
      imageUrl: 'https://media.npr.org/images/podcasts/primary/510282.png',
      description: 'A fun, fast-paced guide to the movies, television, music, and books you need to know about.',
      category: 'Pop Culture',
    ),
    const PodcastFeed(
      id: 'this_american_life',
      title: 'This American Life',
      publisher: 'This American Life',
      rssUrl: 'https://www.thisamericanlife.org/podcast/rss.xml',
      imageUrl: 'https://thisamericanlife.org/sites/all/themes/thislife/img/tal-logo-3000x3000.png',
      description: 'Compelling, narrative-driven journalistic stories about everyday people, hosted by Ira Glass.',
      category: 'Storytelling',
    ),
    const PodcastFeed(
      id: 'science_vs',
      title: 'Science Vs',
      publisher: 'Gimlet',
      rssUrl: 'https://feeds.megaphone.fm/sciencevs',
      imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts112/v4/bf/fb/1b/bffb1b22-8616-d3ee-ff5c-ea8a264a938c/mza_10375993850890697950.jpg/600x600bb.jpg',
      description: 'There are a lot of strong opinions, but then there’s science. Science Vs takes on fads, findings, and what everyone’s talking about.',
      category: 'Science',
    ),
    const PodcastFeed(
      id: '99_invisible',
      title: '99% Invisible',
      publisher: 'Roman Mars',
      rssUrl: 'https://feeds.simplecast.com/BqbsxVfO',
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/e/e0/99%25_Invisible_logo.jpg',
      description: 'A show about all the thought that goes into the things we don’t think about — design and architecture.',
      category: 'Design',
    ),
    const PodcastFeed(
      id: 'freakonomics',
      title: 'Freakonomics Radio',
      publisher: 'Stephen J. Dubner',
      rssUrl: 'https://feeds.simplecast.com/Y8lFbOT4',
      imageUrl: 'https://media.npr.org/images/podcasts/primary/510326.png',
      description: 'Discover the hidden side of everything, from the economics of sleep to the history of the banana.',
      category: 'Economics',
    ),
    const PodcastFeed(
      id: 'planet_money',
      title: 'Planet Money',
      publisher: 'NPR',
      rssUrl: 'https://feeds.npr.org/510289/podcast.xml',
      imageUrl: 'https://media.npr.org/images/podcasts/primary/510289.png',
      description: 'The economy explained through highly entertaining, narrative storytelling.',
      category: 'Economics',
    ),
    const PodcastFeed(
      id: 'ted_radio_hour',
      title: 'TED Radio Hour',
      publisher: 'NPR',
      rssUrl: 'https://feeds.npr.org/510298/podcast.xml',
      imageUrl: 'https://media.npr.org/images/podcasts/primary/510298.png',
      description: 'A journey through fascinating ideas, inventions, and new ways to think and create.',
      category: 'Technology',
    ),
    const PodcastFeed(
      id: 'stuff_you_should_know',
      title: 'Stuff You Should Know',
      publisher: 'iHeartPodcasts',
      rssUrl: 'https://www.omnycontent.com/d/playlist/e73c998e-6e60-432f-8610-ae210140c5b1/a91018a4-ea4f-4130-bf55-ae270180c327/44710ecc-10bb-48d1-93c7-ae270180c33e/podcast.rss',
      imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/aa/82/91/aa82912f-23ee-6f6a-583c-a4e993164d0e/mza_12111158076643383507.jpg/600x600bb.jpg',
      description: 'Join Josh and Chuck as they explain everything from how champagne works to chaos theory.',
      category: 'Education',
    ),
  ];

  final http.Client _client;
  final Map<String, _CachedEpisodes> _episodesCache = {};

  PodcastService({http.Client? client}) : _client = client ?? http.Client();

  // ── Subscriptions ──────────────────────────────────────────────────────────

  /// Gets all subscribed podcast feeds
  Future<List<PodcastFeed>> getSubscribedFeeds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_subscribedFeedsPrefsKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        // Pre-populate with default feeds
        final feedsJson = jsonEncode(_defaultFeeds.map((f) => f.toJson()).toList());
        await prefs.setString(_subscribedFeedsPrefsKey, feedsJson);
        return _defaultFeeds;
      }
      final List<dynamic> decoded = jsonDecode(jsonStr);
      final list = decoded.map((f) => PodcastFeed.fromJson(f)).toList();
      
      // Auto-merge any new default feeds that are missing from subscriptions
      var hasChanges = false;
      for (final defaultFeed in _defaultFeeds) {
        if (!list.any((f) => f.id == defaultFeed.id)) {
          list.add(defaultFeed);
          hasChanges = true;
        }
      }
      if (hasChanges) {
        final feedsJson = jsonEncode(list.map((f) => f.toJson()).toList());
        await prefs.setString(_subscribedFeedsPrefsKey, feedsJson);
      }
      return list;
    } catch (e) {
      print('Error loading subscribed feeds: $e');
      return _defaultFeeds;
    }
  }

  /// Subscribe to a new podcast feed by fetching its RSS URL
  Future<PodcastFeed> subscribeToFeed(String rssUrl) async {
    final cleanUrl = rssUrl.trim();
    // Prevent duplicate subscriptions
    final currentFeeds = await getSubscribedFeeds();
    final existing = currentFeeds.firstWhere(
      (f) => f.rssUrl.toLowerCase() == cleanUrl.toLowerCase(),
      orElse: () => const PodcastFeed(id: '', title: '', publisher: '', rssUrl: '', imageUrl: '', description: '', category: ''),
    );
    if (existing.id.isNotEmpty) {
      return existing; // Already subscribed
    }

    try {
      final response = await _client.get(Uri.parse(cleanUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch RSS feed: ${response.statusCode}');
      }
      final xmlText = utf8.decode(response.bodyBytes);
      final feed = _parseFeedMetadata(xmlText, cleanUrl);
      
      final updatedFeeds = [...currentFeeds, feed];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_subscribedFeedsPrefsKey, jsonEncode(updatedFeeds.map((f) => f.toJson()).toList()));
      return feed;
    } catch (e) {
      print('Error subscribing to feed: $e');
      rethrow;
    }
  }

  /// Unsubscribe from a podcast feed
  Future<void> unsubscribeFromFeed(String feedId) async {
    try {
      final currentFeeds = await getSubscribedFeeds();
      final updatedFeeds = currentFeeds.where((f) => f.id != feedId).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_subscribedFeedsPrefsKey, jsonEncode(updatedFeeds.map((f) => f.toJson()).toList()));
    } catch (e) {
      print('Error unsubscribing from feed: $e');
    }
  }

  /// Helper to parse feed metadata (Title, cover art, etc.) from RSS XML
  PodcastFeed _parseFeedMetadata(String xmlText, String rssUrl) {
    // Title
    final titleRegex = RegExp(r'<channel>[\s\S]*?<title>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</title>');
    final titleMatch = titleRegex.firstMatch(xmlText);
    final title = (titleMatch?.group(1) ?? titleMatch?.group(2) ?? 'Unknown Podcast').trim();

    // Publisher / Author
    final authorRegex = RegExp(r'<itunes:author>([^<]+)</itunes:author>');
    final authorMatch = authorRegex.firstMatch(xmlText);
    var publisher = (authorMatch?.group(1) ?? 'Unknown Publisher').trim();
    if (publisher.isEmpty) {
      final ownerRegex = RegExp(r'<itunes:name>([^<]+)</itunes:name>');
      final ownerMatch = ownerRegex.firstMatch(xmlText);
      publisher = (ownerMatch?.group(1) ?? 'Unknown Publisher').trim();
    }

    // Image URL
    var imageUrl = '';
    final imageRegex = RegExp(r'<itunes:image[\s\S]*?href="([^"]+)"');
    final imageMatch = imageRegex.firstMatch(xmlText);
    if (imageMatch != null) {
      imageUrl = imageMatch.group(1)?.trim() ?? '';
    } else {
      final channelImageRegex = RegExp(r'<image>[\s\S]*?<url>([\s\S]*?)</url>[\s\S]*?</image>');
      final channelImageMatch = channelImageRegex.firstMatch(xmlText);
      imageUrl = (channelImageMatch?.group(1) ?? '').trim();
    }

    // Description
    final descRegex = RegExp(r'<channel>[\s\S]*?<description>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</description>');
    final descMatch = descRegex.firstMatch(xmlText);
    var description = (descMatch?.group(1) ?? descMatch?.group(2) ?? 'No description available.').trim();
    description = _sanitizeDescription(description);

    // Generate unique ID
    final id = rssUrl.hashCode.abs().toString();

    return PodcastFeed(
      id: id,
      title: title,
      publisher: publisher,
      rssUrl: rssUrl,
      imageUrl: imageUrl,
      description: description,
      category: 'Podcast',
    );
  }

  // ── Fetching Episodes ──────────────────────────────────────────────────────

  /// Fetches episodes for a specific podcast feed (caches in-memory for 30 minutes)
  Future<List<PodcastEpisode>> fetchEpisodes(PodcastFeed feed, {bool forceRefresh = false}) async {
    final cacheKey = feed.id;
    final cached = _episodesCache[cacheKey];
    if (!forceRefresh && cached != null) {
      final age = DateTime.now().difference(cached.cachedAt);
      if (age < const Duration(minutes: 30)) {
        return cached.episodes;
      }
    }

    try {
      final response = await _client.get(Uri.parse(feed.rssUrl));
      if (response.statusCode == 200) {
        final eps = _parseRss(utf8.decode(response.bodyBytes), feed);
        _episodesCache[cacheKey] = _CachedEpisodes(eps, DateTime.now());
        return eps;
      } else {
        if (cached != null) {
          return cached.episodes;
        }
        throw Exception('Failed to load feed episodes: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching episodes for ${feed.title}: $e');
      if (cached != null) {
        return cached.episodes;
      }
      rethrow;
    }
  }

  /// Parses RSS XML for episodes belonging to [feed]
  List<PodcastEpisode> _parseRss(String xmlText, PodcastFeed feed) {
    final List<PodcastEpisode> episodes = [];

    final itemRegex = RegExp(r'<item>([\s\S]*?)</item>');
    final titleRegex = RegExp(r'<title>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</title>');
    final descRegex = RegExp(r'<description>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</description>');
    final pubDateRegex = RegExp(r'<pubDate>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</pubDate>');
    final guidRegex = RegExp(r'<guid[\s\S]*?>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</guid>');
    final enclosureRegex = RegExp(r'<enclosure[\s\S]*?url="([^"]+)"');
    final durationRegex = RegExp(r'<itunes:duration>([^<]+)</itunes:duration>');
    final imageRegex = RegExp(r'<itunes:image[\s\S]*?href="([^"]+)"');

    final matches = itemRegex.allMatches(xmlText);
    for (final match in matches) {
      final itemContent = match.group(1) ?? '';

      // Title
      final titleMatch = titleRegex.firstMatch(itemContent);
      if (titleMatch == null) continue;
      final title = (titleMatch.group(1) ?? titleMatch.group(2) ?? '').trim();

      // Description
      final descMatch = descRegex.firstMatch(itemContent);
      var description = '';
      if (descMatch != null) {
        description = (descMatch.group(1) ?? descMatch.group(2) ?? '').trim();
        description = _sanitizeDescription(description);
      }

      // Guid
      final guidMatch = guidRegex.firstMatch(itemContent);
      var guid = '';
      if (guidMatch != null) {
        guid = (guidMatch.group(1) ?? guidMatch.group(2) ?? '').trim();
      }

      // Enclosure URL
      final enclosureMatch = enclosureRegex.firstMatch(itemContent);
      if (enclosureMatch == null) continue;
      final streamUrl = enclosureMatch.group(1) ?? '';

      if (guid.isEmpty) {
        guid = streamUrl;
      }

      // Pub Date
      final pubDateMatch = pubDateRegex.firstMatch(itemContent);
      var pubDate = DateTime.now();
      if (pubDateMatch != null) {
        final dateStr = (pubDateMatch.group(1) ?? pubDateMatch.group(2) ?? '').trim();
        pubDate = _parseRssDate(dateStr) ?? DateTime.now();
      }

      // Duration
      final durationMatch = durationRegex.firstMatch(itemContent);
      var duration = Duration.zero;
      if (durationMatch != null) {
        final durStr = durationMatch.group(1) ?? '0';
        duration = _parseDuration(durStr);
      }

      // Image (fallback to channel image)
      final imageMatch = imageRegex.firstMatch(itemContent);
      final imageUrl = imageMatch != null ? (imageMatch.group(1) ?? feed.imageUrl) : feed.imageUrl;

      episodes.add(PodcastEpisode(
        guid: guid,
        title: title,
        description: description,
        streamUrl: streamUrl,
        pubDate: pubDate,
        imageUrl: imageUrl,
        duration: duration,
        podcastFeedId: feed.id,
        podcastTitle: feed.title,
        podcastPublisher: feed.publisher,
      ));
    }
    return episodes;
  }

  /// Fetches latest week's worth of episodes aggregated from all active feeds
  Future<List<PodcastEpisode>> fetchRecentEpisodesAcrossAllFeeds() async {
    final feeds = await getSubscribedFeeds();
    final List<PodcastEpisode> allEpisodes = [];

    // Fetch all in parallel
    final results = await Future.wait(
      feeds.map((feed) => fetchEpisodes(feed).catchError((_) => <PodcastEpisode>[])),
    );

    for (final list in results) {
      allEpisodes.addAll(list);
    }

    // Filter to last 7 days and sort chronologically descending
    final now = DateTime.now();
    final recent = allEpisodes
        .where((ep) => now.difference(ep.pubDate).inDays <= 7)
        .toList();

    recent.sort((a, b) => b.pubDate.compareTo(a.pubDate));
    return recent;
  }

  // ── Parse Helpers ──────────────────────────────────────────────────────────

  DateTime? _parseRssDate(String dateStr) {
    var parsed = DateTime.tryParse(dateStr);
    if (parsed != null) return parsed;

    try {
      var cleanStr = dateStr;
      if (cleanStr.contains(',')) {
        cleanStr = cleanStr.substring(cleanStr.indexOf(',') + 1).trim();
      }
      cleanStr = cleanStr.replaceAll(RegExp(r'\s+'), ' ');

      final formats = [
        'd MMM yyyy HH:mm:ss Z',
        'd MMM yyyy HH:mm:ss zzz',
        'd MMM yyyy HH:mm:ss',
        'd MMM yyyy HH:mm',
      ];
      for (final format in formats) {
        try {
          final parsedDate = DateFormat(format).parse(cleanStr, true);
          return parsedDate.toLocal();
        } catch (_) {}
      }
    } catch (_) {}
    return DateTime.tryParse(dateStr);
  }

  Duration _parseDuration(String durStr) {
    if (durStr.contains(':')) {
      final parts = durStr.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s = int.tryParse(parts[1]) ?? 0;
        return Duration(minutes: m, seconds: s);
      } else if (parts.length == 3) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final s = int.tryParse(parts[2]) ?? 0;
        return Duration(hours: h, minutes: m, seconds: s);
      }
    } else {
      final seconds = int.tryParse(durStr) ?? 0;
      return Duration(seconds: seconds);
    }
    return Duration.zero;
  }

  // ── Listened Persistence ───────────────────────────────────────────────────

  Future<Set<String>> getListenedEpisodes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_listenedPrefsKey);
      return list?.toSet() ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<void> markAsListened(String guid, bool listened) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList(_listenedPrefsKey) ?? [];
      final currentSet = currentList.toSet();
      if (listened) {
        currentSet.add(guid);
      } else {
        currentSet.remove(guid);
      }
      await prefs.setStringList(_listenedPrefsKey, currentSet.toList());
    } catch (e) {
      print('Error saving listened status: $e');
    }
  }

  String _sanitizeDescription(String html) {
    if (html.isEmpty) return '';

    // Decode common HTML entities
    var text = html
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&apos;', "'");

    // Strip all HTML tags
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');

    // Normalize multiple newlines and trim
    text = text.replaceAll(RegExp(r'\n\s*\n+'), '\n\n').trim();

    return text;
  }
}

class _CachedEpisodes {
  final List<PodcastEpisode> episodes;
  final DateTime cachedAt;
  _CachedEpisodes(this.episodes, this.cachedAt);
}
