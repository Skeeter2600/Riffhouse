# Riffhouse

Riffhouse is a cross-platform music streaming client and audio player built with Flutter, designed to integrate seamlessly with personal Jellyfin media servers while providing native support for podcasts, smart dynamic mixes, offline caching, and automotive playback.

---

## Features

* **Jellyfin Integration:** Stream music directly from your self-hosted Jellyfin media server with full access to artists, albums, tracks, and personal playlists.
* **Offline Playback & Local Caching:** Cache tracks and download albums locally to enjoy uninterrupted listening without an active internet connection.
* **Smart & Dynamic Mixes:** Algorithmic and custom playlist curation including Daily Mixes, Heavy Rotation, and Undiscovered music based on your library.
* **Podcast Manager:** Add and stream your favorite RSS podcast feeds alongside your personal music library in a unified player.
* **Android Auto Support:** Native automotive integration for safe playback controls, queue browsing, and media navigation from your vehicle dashboard.
* **Background Audio & Queue Management:** Robust background playback service with persistent notification controls, lock screen metadata, and full reorderable queue support.
* **Multi-Platform:** Built from a single Flutter codebase supporting Android, iOS, macOS, Windows, and Linux.

---

## Tech Stack & Architecture

* **Framework:** [Flutter](https://flutter.dev/) (Dart)
* **Media Backend:** [Jellyfin REST API](https://jellyfin.org/)
* **State Management:** Riverpod / Provider pattern
* **Local Persistence:** Drift / SQLite local database for offline metadata and caching
* **Audio Engine:** Background audio handler architecture with platform-native integrations

---

## Project Structure

```text
lib/
├── audio/          # Background audio service, queue notifier, & Android Auto handler
├── database/       # SQLite schema definitions, DAOs, and generated database bindings
├── models/         # Jellyfin data models, podcast feeds, and mix configurations
├── providers/      # Application state management (Auth, Library, Podcasts, Database)
├── router/         # Declarative navigation and screen routing
├── screens/        # UI views (Player, Library, Playlists, Detail screens, Settings)
├── services/       # Network API clients (Jellyfin, Podcasts, Cache, Playlists)
├── theme/          # App styling, themes, colors, and typography
└── widgets/        # Reusable UI components (MiniPlayer, AlbumCard, TrackCard)
```

---

## Getting Started

### Prerequisites

* [Flutter SDK](https://docs.flutter.dev/get-started/install) (version 3.x or higher)
* A running [Jellyfin](https://jellyfin.org/) server instance
* Platform build tools:
  * **Android:** Android Studio & Android SDK
  * **iOS / macOS:** Xcode (macOS host required)
  * **Windows / Linux:** CMake, C++ build tools, and platform dependencies

### Installation & Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Skeeter2600/Riffhouse.git
   cd Riffhouse
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run code generation (if schema or models change):**
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Launch the application:**
   ```bash
   flutter run
   ```

---

## Configuration

1. Open Riffhouse and input your **Jellyfin Server URL** (e.g., `https://jellyfin.yourdomain.com`).
2. Log in with your Jellyfin username and password.
3. Your media libraries, albums, playlists, and tracks will automatically sync.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
