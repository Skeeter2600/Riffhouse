import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../services/jellyfin_service.dart';

import '../screens/album_detail_screen.dart';
import '../screens/artist_detail_screen.dart';
import '../screens/library_screen.dart';
import '../screens/login_screen.dart';
import '../screens/player_screen.dart';
import '../screens/playlist_detail_screen.dart';
import '../screens/playlist_add_tracks_screen.dart';
import '../screens/playlist_smart_add_screen.dart';
import '../screens/playlists_screen.dart';
import '../screens/podcasts_screen.dart';
import '../screens/podcast_detail_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/smart_mix_detail_screen.dart';
import '../screens/daily_mix_config_screen.dart';
import '../screens/downloads_screen.dart';
import '../providers/library_provider.dart';
import '../providers/update_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/update_dialog.dart';

// ---------------------------------------------------------------------------
// Shell scaffold
// ---------------------------------------------------------------------------

class _ShellScaffold extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const _ShellScaffold({required this.navigationShell});

  @override
  ConsumerState<_ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends ConsumerState<_ShellScaffold> {
  bool _initialRefreshDone = false;

  @override
  void initState() {
    super.initState();
    // Defer the initial library refresh until the JellyfinService is actually
    // available. Calling refresh() while service == null sets state to
    // AsyncData([]) and wipes out whatever the local DB cache had, making
    // all songs/playlists disappear until the next manual pull-to-refresh.
    //
    // We check once after the first frame. If service is already ready we
    // refresh immediately. If not, the listen() in build() will pick it up
    // on the first non-null emission from jellyfinServiceProvider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryInitialRefresh();
    });
  }

  void _tryInitialRefresh() {
    if (_initialRefreshDone) {
      debugPrint('[ShellScaffold._tryInitialRefresh] Already done, skipping');
      return;
    }
    final service = ref.read(jellyfinServiceProvider);
    debugPrint('[ShellScaffold._tryInitialRefresh] service=${service != null ? "READY" : "NULL"}');
    if (service == null) {
      debugPrint('[ShellScaffold._tryInitialRefresh] service null → waiting for listener');
      return; // build()'s listen will trigger this later
    }
    _initialRefreshDone = true;
    debugPrint('[ShellScaffold._tryInitialRefresh] Triggering refresh for all providers');
    ref.read(playlistsProvider.notifier).refresh();
    ref.read(albumsProvider.notifier).refresh();
    ref.read(artistsProvider.notifier).refresh();
    ref.read(tracksProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    // Keep Android Auto synced with background library data updates
    ref.watch(androidAutoSyncProvider);

    // Trigger the initial library refresh the moment the Jellyfin service
    // becomes available (i.e. after the async session restore completes).
    // This is a no-op if _tryInitialRefresh() already ran in initState.
    ref.listen<JellyfinService?>(jellyfinServiceProvider, (previous, next) {
      debugPrint('[ShellScaffold.listen] jellyfinServiceProvider changed: ${previous != null ? "was READY" : "was NULL"} → ${next != null ? "now READY" : "now NULL"}');
      if (previous == null && next != null) {
        _tryInitialRefresh();
      }
    });

    // Watching the update provider here starts the launch-time update check;
    // each new prompt (update found, or notes after updating) opens a dialog.
    ref.listen<int>(updateProvider.select((s) => s.promptSeq), (previous, next) {
      final prompt = ref.read(updateProvider).prompt;
      if (prompt != null && mounted) showUpdateDialog(context, prompt);
    });

    final currentIndex = widget.navigationShell.currentIndex;


    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (currentIndex != 0) {
          widget.navigationShell.goBranch(0);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: widget.navigationShell,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            NavigationBar(
              selectedIndex: widget.navigationShell.currentIndex,
              onDestinationSelected: (index) {
                widget.navigationShell.goBranch(
                  index,
                  initialLocation: index == widget.navigationShell.currentIndex,
                );
              },
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.queue_music_outlined),
                  selectedIcon: Icon(Icons.queue_music),
                  label: 'Playlists',
                ),
                NavigationDestination(
                  icon: Icon(Icons.podcasts_outlined),
                  selectedIcon: Icon(Icons.podcasts),
                  label: 'Podcasts',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Provider & Router Definition
// ---------------------------------------------------------------------------

/// Exposes the persistent [GoRouter] instance.
///
/// We watch [authProvider] so that GoRouter is re-initialized (triggering
/// the redirect callback) when the authentication state changes.
final routerProvider = Provider<GoRouter>((ref) {
  final user = ref.watch(authProvider);
  final isLoggedIn = user != null;

  return GoRouter(
    initialLocation: '/home/library',
    redirect: (context, state) {
      final isGoingToLogin = state.matchedLocation == '/login';

      if (!isLoggedIn && !isGoingToLogin) return '/login';
      if (isLoggedIn && isGoingToLogin) return '/home/library';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _ShellScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/library',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/playlists',
                builder: (context, state) => const PlaylistsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/podcasts',
                builder: (context, state) => const PodcastsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/home/search',
        redirect: (context, state) => '/home/library',
      ),
      GoRoute(
        path: '/home/downloads',
        builder: (context, state) => const DownloadsScreen(),
      ),
      GoRoute(
        path: '/downloads',
        builder: (context, state) => const DownloadsScreen(),
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) => const PlayerScreen(),
      ),
      GoRoute(
        path: '/album/:albumId',
        builder: (context, state) => AlbumDetailScreen(
          albumId: state.pathParameters['albumId']!,
        ),
      ),
      GoRoute(
        path: '/podcast/:feedId',
        builder: (context, state) => PodcastDetailScreen(
          feedId: state.pathParameters['feedId']!,
        ),
      ),
      GoRoute(
        path: '/artist/:artistId',
        builder: (context, state) => ArtistDetailScreen(
          artistId: state.pathParameters['artistId']!,
        ),
      ),
      GoRoute(
        path: '/playlist/:playlistId',
        builder: (context, state) => PlaylistDetailScreen(
          playlistId: state.pathParameters['playlistId']!,
        ),
      ),
      GoRoute(
        path: '/playlist/:playlistId/add',
        builder: (context, state) => PlaylistAddTracksScreen(
          playlistId: state.pathParameters['playlistId']!,
        ),
      ),
      GoRoute(
        path: '/playlist/:playlistId/smart-add',
        builder: (context, state) => PlaylistSmartAddScreen(
          playlistId: state.pathParameters['playlistId']!,
        ),
      ),
      GoRoute(
        path: '/smart-mix/:mixType',
        builder: (context, state) => SmartMixDetailScreen(
          mixType: state.pathParameters['mixType']!,
        ),
      ),
      GoRoute(
        path: '/daily-mix-config',
        builder: (context, state) => const DailyMixConfigScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
