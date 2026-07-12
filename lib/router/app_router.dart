import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../screens/album_detail_screen.dart';
import '../screens/artist_detail_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/library_screen.dart';
import '../screens/login_screen.dart';
import '../screens/player_screen.dart';
import '../screens/playlist_detail_screen.dart';
import '../screens/playlist_add_tracks_screen.dart';
import '../screens/playlists_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/smart_mix_detail_screen.dart';
import '../providers/library_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';

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
  @override
  void initState() {
    super.initState();
    // Eagerly warm the library cache so search is instant when the user opens
    // it. We fire this after the first frame so the build is not blocked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Preload library data in background (running asynchronously).
      // This warms the cache for Library, Playlists, and Smart Mixes.
      ref.read(tracksProvider);
      ref.read(albumsProvider);
      ref.read(artistsProvider);
      ref.read(playlistsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep Android Auto synced with background library data updates
    ref.watch(androidAutoSyncProvider);

    return Scaffold(
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
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music_outlined),
                selectedIcon: Icon(Icons.queue_music),
                label: 'Playlists',
              ),
              NavigationDestination(
                icon: Icon(Icons.download_outlined),
                selectedIcon: Icon(Icons.download),
                label: 'Downloads',
              ),
            ],
          ),
        ],
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
                path: '/home/search',
                builder: (context, state) => const SearchScreen(),
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
                path: '/home/downloads',
                builder: (context, state) => const DownloadsScreen(),
              ),
            ],
          ),
        ],
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
        path: '/smart-mix/:mixType',
        builder: (context, state) => SmartMixDetailScreen(
          mixType: state.pathParameters['mixType']!,
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
