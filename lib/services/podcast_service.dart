import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_feed.dart';

class PodcastService {
  static const String _listenedPrefsKey = 'listened_podcast_episodes';
  static const String _subscribedFeedsPrefsKey = 'subscribed_podcast_feeds';


  final http.Client _client;
  final Map<String, _CachedEpisodes> _episodesCache = {};

  PodcastService({http.Client? client}) : _client = client ?? http.Client();

  // ── Subscriptions ──────────────────────────────────────────────────────────

  /// Gets all subscribed podcast feeds
  Future<List<PodcastFeed>> getSubscribedFeeds() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // One-time cleanup to remove old pre-populated default podcasts
      if (prefs.getBool('podcasts_cleared_defaults_v3') != true) {
        final legacyJson = prefs.getString(_subscribedFeedsPrefsKey);
        if (legacyJson != null && legacyJson.isNotEmpty) {
          const defaultIds = {
            'up_first',
            'bbc_global_news',
            'marketplace',
            'pop_culture_happy_hour',
            'this_american_life',
            'science_vs',
            '99_invisible',
            'freakonomics',
            'planet_money',
            'ted_radio_hour',
            'stuff_you_should_know'
          };
          try {
            final List<dynamic> decoded = jsonDecode(legacyJson);
            final userOnlyFeeds = decoded
                .map((f) => PodcastFeed.fromJson(f))
                .where((f) => !defaultIds.contains(f.id))
                .toList();
            await prefs.setString(_subscribedFeedsPrefsKey,
                jsonEncode(userOnlyFeeds.map((f) => f.toJson()).toList()));
          } catch (_) {}
        }
        await prefs.setBool('podcasts_cleared_defaults_v3', true);
      }

      final jsonStr = prefs.getString(_subscribedFeedsPrefsKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        return [];
      }
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((f) => PodcastFeed.fromJson(f)).toList();
    } catch (_) {
      return [];
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
    } catch (_) {
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
    } catch (_) {
      // Ignore error
    }
  }

  /// Helper to parse feed metadata (Title, cover art, etc.) from RSS XML
  PodcastFeed _parseFeedMetadata(String xmlText, String rssUrl) {
    // Title
    final titleRegex = RegExp(r'<channel>[\s\S]*?<title>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</title>', caseSensitive: false);
    final titleMatch = titleRegex.firstMatch(xmlText);
    final title = (titleMatch?.group(1) ?? titleMatch?.group(2) ?? 'Unknown Podcast').trim();

    // Publisher / Author
    final authorRegex = RegExp(r'<itunes:author>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([^<]+))</itunes:author>', caseSensitive: false);
    final authorMatch = authorRegex.firstMatch(xmlText);
    var publisher = (authorMatch?.group(1) ?? authorMatch?.group(2) ?? 'Unknown Publisher').trim();
    if (publisher.isEmpty) {
      final ownerRegex = RegExp(r'<itunes:name>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([^<]+))</itunes:name>', caseSensitive: false);
      final ownerMatch = ownerRegex.firstMatch(xmlText);
      publisher = (ownerMatch?.group(1) ?? ownerMatch?.group(2) ?? 'Unknown Publisher').trim();
    }

    // Image URL (support itunes:image, channel image url, and media thumbnail/content)
    var imageUrl = '';
    final imageRegex = RegExp(r'''<itunes:image[^>]*href=["']([^"']+)["']''', caseSensitive: false);
    final imageMatch = imageRegex.firstMatch(xmlText);
    if (imageMatch != null) {
      imageUrl = imageMatch.group(1)?.trim() ?? '';
    }
    if (imageUrl.isEmpty) {
      final channelImageRegex = RegExp(r'''<image>[\s\S]*?<url>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([^<]+))</url>''', caseSensitive: false);
      final channelImageMatch = channelImageRegex.firstMatch(xmlText);
      imageUrl = (channelImageMatch?.group(1) ?? channelImageMatch?.group(2) ?? '').trim();
    }
    if (imageUrl.isEmpty) {
      final mediaRegex = RegExp(r'''<media:(?:thumbnail|content)[^>]*url=["']([^"']+)["']''', caseSensitive: false);
      final mediaMatch = mediaRegex.firstMatch(xmlText);
      imageUrl = (mediaMatch?.group(1) ?? '').trim();
    }

    // Description
    final descRegex = RegExp(r'<channel>[\s\S]*?<description>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</description>', caseSensitive: false);
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
        final xmlText = utf8.decode(response.bodyBytes);
        final eps = _parseRss(xmlText, feed);
        _episodesCache[cacheKey] = _CachedEpisodes(eps, DateTime.now());

        // If feed artwork was missing or updated, update persisted feed metadata
        if (eps.isNotEmpty && eps.first.imageUrl.isNotEmpty && feed.imageUrl != eps.first.imageUrl) {
          unawaited(_updateFeedImage(feed.id, eps.first.imageUrl));
        }

        return eps;
      } else {
        if (cached != null) {
          return cached.episodes;
        }
        throw Exception('Failed to load feed episodes: ${response.statusCode}');
      }
    } catch (_) {
      if (cached != null) {
        return cached.episodes;
      }
      rethrow;
    }
  }

  /// Parses RSS XML for episodes belonging to [feed]
  List<PodcastEpisode> _parseRss(String xmlText, PodcastFeed feed) {
    final List<PodcastEpisode> episodes = [];

    // Extract channel-level fallback image from the live XML
    var channelImageUrl = feed.imageUrl;
    final firstItemIdx = xmlText.indexOf('<item>');
    final channelHeader = firstItemIdx != -1 ? xmlText.substring(0, firstItemIdx) : xmlText;

    final channelItunesMatch = RegExp(r'''<itunes:image[^>]*href=["']([^"']+)["']''', caseSensitive: false).firstMatch(channelHeader);
    if (channelItunesMatch != null && (channelItunesMatch.group(1)?.trim().isNotEmpty ?? false)) {
      channelImageUrl = channelItunesMatch.group(1)!.trim();
    } else {
      final channelImgMatch = RegExp(r'''<image>[\s\S]*?<url>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([^<]+))</url>''', caseSensitive: false).firstMatch(channelHeader);
      if (channelImgMatch != null) {
        final parsed = (channelImgMatch.group(1) ?? channelImgMatch.group(2) ?? '').trim();
        if (parsed.isNotEmpty) {
          channelImageUrl = parsed;
        }
      } else {
        final channelMediaMatch = RegExp(r'''<media:(?:thumbnail|content)[^>]*url=["']([^"']+)["']''', caseSensitive: false).firstMatch(channelHeader);
        if (channelMediaMatch != null && (channelMediaMatch.group(1)?.trim().isNotEmpty ?? false)) {
          channelImageUrl = channelMediaMatch.group(1)!.trim();
        }
      }
    }

    final itemRegex = RegExp(r'<item>([\s\S]*?)</item>');
    final titleRegex = RegExp(r'<title>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</title>');
    final descRegex = RegExp(r'<description>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</description>');
    final pubDateRegex = RegExp(r'<pubDate>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</pubDate>');
    final guidRegex = RegExp(r'<guid[\s\S]*?>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</guid>');
    final enclosureRegex = RegExp(r'<enclosure[\s\S]*?url="([^"]+)"');
    final durationRegex = RegExp(r'<itunes:duration>([^<]+)</itunes:duration>');

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

      // Image (item-level or fallback to channel image)
      var imageUrl = '';
      final imageMatch = RegExp(r'''<itunes:image[^>]*href=["']([^"']+)["']''', caseSensitive: false).firstMatch(itemContent);
      if (imageMatch != null) {
        imageUrl = imageMatch.group(1)?.trim() ?? '';
      }
      if (imageUrl.isEmpty) {
        final mediaMatch = RegExp(r'''<media:(?:thumbnail|content)[^>]*url=["']([^"']+)["']''', caseSensitive: false).firstMatch(itemContent);
        if (mediaMatch != null) {
          imageUrl = mediaMatch.group(1)?.trim() ?? '';
        }
      }
      if (imageUrl.isEmpty) {
        imageUrl = channelImageUrl;
      }

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

  Future<void> _updateFeedImage(String feedId, String newImageUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_subscribedFeedsPrefsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final list = decoded.map((f) => PodcastFeed.fromJson(f)).toList();
        var changed = false;
        final updated = list.map((f) {
          if (f.id == feedId && f.imageUrl != newImageUrl) {
            changed = true;
            return f.copyWith(imageUrl: newImageUrl);
          }
          return f;
        }).toList();
        if (changed) {
          await prefs.setString(_subscribedFeedsPrefsKey, jsonEncode(updated.map((f) => f.toJson()).toList()));
        }
      }
    } catch (_) {}
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
    } catch (_) {
      // Ignore error
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
