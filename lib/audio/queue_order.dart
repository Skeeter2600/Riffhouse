import 'dart:math';

import '../models/jellyfin_models.dart';

/// Pure queue-ordering helpers used by the audio handler's shuffle support.
///
/// The queue is always `[source tracks..., smart-continue tail...]`, where the
/// first `sourceLength` entries are the album/playlist/mix that was played.
/// Shuffle only ever reorders the source portion; the tail keeps its order.

/// Returns [tracks] shuffled for a fresh play. When [startIndex] is given that
/// track is placed first; otherwise a random track leads.
List<JellyfinTrack> shuffledForPlay(
  List<JellyfinTrack> tracks, {
  int? startIndex,
  Random? random,
}) {
  if (tracks.length < 2) return List<JellyfinTrack>.from(tracks);
  final rng = random ?? Random();
  final rest = List<JellyfinTrack>.from(tracks);
  final first = rest.removeAt(startIndex ?? rng.nextInt(rest.length));
  rest.shuffle(rng);
  return [first, ...rest];
}

/// Returns [queue] with the not-yet-played source tracks (after
/// [currentIndex], before [sourceLength]) shuffled. Everything else stays put.
List<JellyfinTrack> shuffleUpcoming(
  List<JellyfinTrack> queue,
  int currentIndex,
  int sourceLength, {
  Random? random,
}) {
  final end = min(sourceLength, queue.length);
  final start = currentIndex + 1;
  if (start >= end) return List<JellyfinTrack>.from(queue);
  final upcoming = queue.sublist(start, end)..shuffle(random ?? Random());
  return [...queue.sublist(0, start), ...upcoming, ...queue.sublist(end)];
}

/// Returns [queue] with its source portion put back into [sourceOrder],
/// together with the new index of the track at [currentIndex].
///
/// If the current track is not part of the source (playback has moved into
/// the smart-continue tail) the queue is returned unchanged.
({List<JellyfinTrack> queue, int currentIndex}) restoreSourceOrder(
  List<JellyfinTrack> queue,
  int currentIndex,
  List<JellyfinTrack> sourceOrder,
  int sourceLength,
) {
  final end = min(sourceLength, queue.length);
  if (currentIndex < 0 || currentIndex >= end || sourceOrder.length != end) {
    return (queue: List<JellyfinTrack>.from(queue), currentIndex: currentIndex);
  }
  final restored = [...sourceOrder, ...queue.sublist(end)];
  final newIndex = sourceOrder.indexWhere((t) => t.id == queue[currentIndex].id);
  if (newIndex == -1) {
    return (queue: List<JellyfinTrack>.from(queue), currentIndex: currentIndex);
  }
  return (queue: restored, currentIndex: newIndex);
}
