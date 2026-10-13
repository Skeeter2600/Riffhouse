part of '../library_provider.dart';

// ---------------------------------------------------------------------------
// Android Auto Background Library Sync
// ---------------------------------------------------------------------------

final androidAutoSyncProvider = Provider<void>((ref) {
  final service = ref.watch(musicServiceProvider);
  final handler = ref.watch(audioHandlerProvider);

  if (service != null) {
    handler.updateAndroidAutoService(service);
  }

  // Tracks are NOT watched here — Android Auto loads them on-demand per
  // container via getChildren(). Watching tracksProvider here caused a
  // notification storm that flooded the Binder IPC buffer.
  final albums = ref.watch(albumsProvider).valueOrNull ?? [];
  final artists = ref.watch(artistsProvider).valueOrNull ?? [];
  final playlists = ref.watch(playlistsProvider).valueOrNull ?? [];
  final recentlyPlayed = ref.watch(recentlyPlayedProvider).valueOrNull ?? [];
  final newAlbums = ref.watch(newAlbumsProvider).valueOrNull?.albums ?? [];

  if (service != null) {
    handler.updateAndroidAutoLibrary(
      playlists: playlists,
      albums: albums,
      artists: artists,
      tracksByContainer: const {},
      recentlyPlayed: recentlyPlayed,
      newAlbums: newAlbums,
    );
  }
});
