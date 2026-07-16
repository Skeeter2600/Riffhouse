import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/podcast_episode.dart';
import '../models/podcast_feed.dart';
import '../services/podcast_service.dart';

final podcastServiceProvider = Provider<PodcastService>((ref) {
  return PodcastService();
});

class SubscribedFeedsNotifier extends StateNotifier<AsyncValue<List<PodcastFeed>>> {
  final PodcastService _service;

  SubscribedFeedsNotifier(this._service) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final feeds = await _service.getSubscribedFeeds();
      state = AsyncValue.data(feeds);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> subscribe(String rssUrl) async {
    try {
      final feed = await _service.subscribeToFeed(rssUrl);
      final currentList = state.valueOrNull ?? [];
      if (!currentList.any((f) => f.id == feed.id)) {
        state = AsyncValue.data([...currentList, feed]);
      }
    } catch (e, st) {
      print('Subscribe provider error: $e');
    }
  }

  Future<void> unsubscribe(String feedId) async {
    try {
      await _service.unsubscribeFromFeed(feedId);
      final currentList = state.valueOrNull ?? [];
      state = AsyncValue.data(currentList.where((f) => f.id != feedId).toList());
    } catch (e, st) {
      print('Unsubscribe provider error: $e');
    }
  }
}

final subscribedFeedsProvider =
    StateNotifierProvider<SubscribedFeedsNotifier, AsyncValue<List<PodcastFeed>>>((ref) {
  final service = ref.watch(podcastServiceProvider);
  return SubscribedFeedsNotifier(service);
});

final podcastEpisodesProvider =
    FutureProvider.family<List<PodcastEpisode>, PodcastFeed>((ref, feed) async {
  final service = ref.watch(podcastServiceProvider);
  return service.fetchEpisodes(feed);
});

final recentEpisodesProvider = FutureProvider<List<PodcastEpisode>>((ref) async {
  final service = ref.watch(podcastServiceProvider);
  return service.fetchRecentEpisodesAcrossAllFeeds();
});

class ListenedEpisodesNotifier extends StateNotifier<Set<String>> {
  final PodcastService _service;

  ListenedEpisodesNotifier(this._service) : super({}) {
    _load();
  }

  Future<void> _load() async {
    final listened = await _service.getListenedEpisodes();
    state = listened;
  }

  Future<void> toggleListened(String guid) async {
    final isListened = state.contains(guid);
    final nextState = isListened ? false : true;
    
    // Snappy UI state update
    if (nextState) {
      state = {...state, guid};
    } else {
      state = state.where((g) => g != guid).toSet();
    }
    
    await _service.markAsListened(guid, nextState);
  }

  Future<void> setListened(String guid, bool listened) async {
    if (listened) {
      if (state.contains(guid)) return;
      state = {...state, guid};
    } else {
      if (!state.contains(guid)) return;
      state = state.where((g) => g != guid).toSet();
    }
    await _service.markAsListened(guid, listened);
  }
}

final listenedEpisodesProvider = StateNotifierProvider<ListenedEpisodesNotifier, Set<String>>((ref) {
  final service = ref.watch(podcastServiceProvider);
  return ListenedEpisodesNotifier(service);
});
