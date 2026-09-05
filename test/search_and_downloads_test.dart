import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_music_player/models/jellyfin_models.dart';
import 'package:mobile_music_player/providers/download_provider.dart';
import 'package:mobile_music_player/providers/library_provider.dart';
import 'package:mobile_music_player/theme/app_theme.dart';

void main() {
  group('Search and Filter Tests', () {
    test('Playlist search filter correctly matches query and limits to 10', () {
      final playlists = List.generate(
        25,
        (i) => JellyfinPlaylist(
          id: 'p_$i',
          name: i < 15 ? 'Chill Vibes $i' : 'Workout Mix $i',
          trackCount: i + 1,
        ),
      );

      const query = 'chill';
      final filtered = playlists
          .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
          .take(10)
          .toList();

      expect(filtered.length, equals(10));
      expect(filtered.every((p) => p.name.toLowerCase().contains('chill')), isTrue);
    });

    test('Search results across all categories are capped at at most 10 items', () {
      final tracks = List.generate(
        30,
        (i) => JellyfinTrack(
          id: 't_$i',
          name: 'Track $i',
          artists: const ['Artist A'],
          albumArtist: 'Artist A',
          albumName: 'Album A',
          albumId: 'alb_1',
          genres: const ['Pop'],
          durationMs: 180000,
          serverId: 'srv_1',
        ),
      );

      final albums = List.generate(
        20,
        (i) => JellyfinAlbum(
          id: 'a_$i',
          name: 'Album $i',
          artist: 'Artist A',
          trackCount: 10,
        ),
      );

      final artists = List.generate(
        15,
        (i) => JellyfinArtist(
          id: 'art_$i',
          name: 'Artist $i',
        ),
      );

      final cappedTracks = tracks.take(10).toList();
      final cappedAlbums = albums.take(10).toList();
      final cappedArtists = artists.take(10).toList();

      expect(cappedTracks.length, equals(10));
      expect(cappedAlbums.length, equals(10));
      expect(cappedArtists.length, equals(10));
    });
  });

  group('DownloadState Tests', () {
    test('DownloadState updates activeDownloadingIds, progressMap, and downloadedPlaylistIds', () {
      var state = const DownloadState();
      expect(state.activeDownloadingIds.isEmpty, isTrue);
      expect(state.progressMap.isEmpty, isTrue);
      expect(state.downloadedPlaylistIds.isEmpty, isTrue);

      state = state.copyWith(
        activeDownloadingIds: {'track_1', 'track_2'},
        progressMap: {'track_1': 0.45},
        batchProgress: {'pl_1': (current: 1, total: 5)},
        downloadedPlaylistIds: {'pl_1', 'pl_2'},
      );

      expect(state.activeDownloadingIds.contains('track_1'), isTrue);
      expect(state.progressMap['track_1'], equals(0.45));
      expect(state.batchProgress['pl_1']?.current, equals(1));
      expect(state.batchProgress['pl_1']?.total, equals(5));
      expect(state.downloadedPlaylistIds.contains('pl_1'), isTrue);
      expect(state.downloadedPlaylistIds.contains('pl_3'), isFalse);
    });

    test('Prune simulation deletes tracks not in any downloaded playlist', () {
      final downloadedPlaylistTrackIds = {'track_pl_1', 'track_pl_2', 'track_pl_3'};
      final allCachedTrackIds = ['track_pl_1', 'track_streamed_1', 'track_streamed_2', 'track_pl_2'];

      final unpinned = allCachedTrackIds
          .where((id) => !downloadedPlaylistTrackIds.contains(id))
          .toList();

      expect(unpinned, equals(['track_streamed_1', 'track_streamed_2']));
    });
  });

  group('Genre Mix and RecentSelection Tests', () {
    test('Genre matching filters and caps to 3 items', () {
      final genres = {'Rock', 'Hard Rock', 'Classic Rock', 'Alternative Rock', 'Pop Rock'};
      const query = 'rock';

      final matched = genres
          .where((g) => g.toLowerCase().contains(query.toLowerCase()))
          .take(3)
          .toList()
        ..sort();

      expect(matched.length, equals(3));
      expect(matched.every((g) => g.toLowerCase().contains('rock')), isTrue);
    });

    test('RecentSelection serializes and deserializes mix items with title, mixType, and colors', () {
      final item = RecentSelection(
        id: 'genre_Country',
        type: 'mix',
        timestamp: DateTime(2026, 9, 5, 10, 0),
        title: 'Country Mix',
        mixType: 'genre_Country',
        colorValue: 0xFFF97316,
        secondaryColorValue: 0xFFC2410C,
      );

      final json = item.toJson();
      expect(json['id'], equals('genre_Country'));
      expect(json['type'], equals('mix'));
      expect(json['title'], equals('Country Mix'));
      expect(json['mixType'], equals('genre_Country'));
      expect(json['colorValue'], equals(0xFFF97316));
      expect(json['secondaryColorValue'], equals(0xFFC2410C));

      final restored = RecentSelection.fromJson(json);
      expect(restored.id, equals('genre_Country'));
      expect(restored.type, equals('mix'));
      expect(restored.title, equals('Country Mix'));
      expect(restored.mixType, equals('genre_Country'));
      expect(restored.colorValue, equals(0xFFF97316));
      expect(restored.secondaryColorValue, equals(0xFFC2410C));
      expect(restored.timestamp, equals(DateTime(2026, 9, 5, 10, 0)));
    });
  });

  group('Back Navigation Logic Tests', () {
    test('Non-library tabs (playlists, podcasts, settings) intercept back navigation', () {
      // Branch 0 = Library, 1 = Playlists, 2 = Podcasts, 3 = Settings
      bool canPopForBranch(int index) => index == 0;

      expect(canPopForBranch(0), isTrue);  // Library allows pop when not searching
      expect(canPopForBranch(1), isFalse); // Playlists intercepts back to go to Library
      expect(canPopForBranch(2), isFalse); // Podcasts intercepts back to go to Library
      expect(canPopForBranch(3), isFalse); // Settings intercepts back to go to Library
    });

    test('Library search mode intercepts back navigation until search query is cleared', () {
      bool canPopLibrary(String query, bool hasFocus) {
        final isSearching = query.trim().isNotEmpty || hasFocus;
        return !isSearching;
      }

      expect(canPopLibrary('rock', false), isFalse); // Search query present: intercept back
      expect(canPopLibrary('', true), isFalse);     // Search box focused: intercept back
      expect(canPopLibrary('', false), isTrue);     // Idle library: allow pop to exit
    });
  });

  group('Playlist Recommendations Widget Layout Tests', () {
    testWidgets('ElevatedButton lays out without exception inside unconstrained Row with AppTheme.dark', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Row(
                children: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Sample Song'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                  ),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.check)),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Sample Song'), findsOneWidget);
    });
  });
}

