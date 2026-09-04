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
* **Multi-Platform Support:** Ready to run on Android, iOS, Windows, macOS, and Linux.

---

## Downloads & Installation

Pre-built binaries for all supported platforms are automatically generated and available on the [GitHub Releases](https://github.com/Skeeter2600/Riffhouse/releases) page.

| Platform | Download File | Installation Instructions |
| :--- | :--- | :--- |
| **Android** | `Riffhouse-Android.apk` | Download and open on your device. Allow installation from your browser or file manager if prompted. |
| **Windows** | `Riffhouse-Windows-x64.zip` | Download and extract the `.zip` archive. Run `Riffhouse.exe` inside the folder. |
| **Linux** | `Riffhouse-Linux-x64.tar.gz` | Extract with `tar -xvf Riffhouse-Linux-x64.tar.gz` and execute `./riffhouse`. |
| **macOS** | `Riffhouse-macOS.zip` | Extract the zip and move `Riffhouse.app` to your `/Applications` directory. (If macOS Gatekeeper blocks it, right-click and select **Open**). |
| **iOS** | `Riffhouse.ipa` | Requires sideloading via a free personal Apple ID using tools like Sideloadly or AltStore (see below). |

### Installing on iOS (Sideloading)

Because Apple restricts unverified browser-based `.ipa` installations without an Enterprise or paid App Store developer account, users can sideload the app using their own Apple ID:

#### Option A: Sideloadly (PC or Mac via USB / Wi-Fi)
1. Download `Riffhouse.ipa` from [Releases](https://github.com/Skeeter2600/Riffhouse/releases) and install [Sideloadly](https://sideloadly.io/).
2. Connect your iPhone to your computer and select it in Sideloadly.
3. Drag `Riffhouse.ipa` into Sideloadly, enter your Apple ID email, and click **Start**.
4. On your iPhone, go to **Settings > General > VPN & Device Management**, tap your Apple ID under *Developer App*, and tap **Trust**.
5. If prompted (iOS 16+), enable **Developer Mode** under **Settings > Privacy & Security** and restart your device.

#### Option B: AltStore or SideStore (On-Device Sideloading)
1. Set up [AltStore](https://altstore.io/) or [SideStore](https://sidestore.io/).
2. Download `Riffhouse.ipa` directly in Safari on your iPhone.
3. Open AltStore/SideStore, tap the `+` button in the *My Apps* tab, and select `Riffhouse.ipa` to install.
*(Note: Free personal Apple ID certificates automatically require refreshing every 7 days through AltStore/SideStore).*

---

## Building from Source

If you prefer to compile Riffhouse yourself or contribute to development:

### Prerequisites

* [Flutter SDK](https://docs.flutter.dev/get-started/install) (version 3.x or higher)
* [Git](https://git-scm.com/)
* Platform-specific requirements:
  * **Android:** Android Studio and Android SDK / command-line tools
  * **Windows:** Visual Studio 2022 with the "Desktop development with C++" workload
  * **macOS / iOS:** macOS machine with Xcode and CocoaPods installed
  * **Linux:** Clang, CMake, Ninja, and GTK packages (`sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`)

### 1. Clone the Repository
```bash
git clone https://github.com/Skeeter2600/Riffhouse.git
cd Riffhouse
```

### 2. Install Dependencies & Generate Code
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### 3. Build for Your Target Platform

* **Android APK:**
  ```bash
  flutter build apk --release
  # Binary location: build/app/outputs/flutter-apk/app-release.apk
  ```
* **Windows Desktop:**
  ```bash
  flutter build windows --release
  # Binary location: build/windows/x64/runner/Release/
  ```
* **macOS Desktop:**
  ```bash
  flutter build macos --release
  # Binary location: build/macos/Build/Products/Release/Riffhouse.app
  ```
* **Linux Desktop:**
  ```bash
  flutter build linux --release
  # Binary location: build/linux/x64/release/bundle/
  ```
* **iOS (Unsigned IPA for sideloading):**
  ```bash
  flutter build ipa --release --no-codesign
  mkdir -p Payload
  cp -r build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app Payload/
  zip -r Riffhouse.ipa Payload
  ```

---

## Tech Stack & Architecture

* **Framework:** [Flutter](https://flutter.dev/) (Dart)
* **Media Backend:** [Jellyfin REST API](https://jellyfin.org/)
* **State Management:** Riverpod / Provider pattern
* **Local Persistence:** Drift / SQLite local database for offline metadata and caching
* **Audio Engine:** Background audio handler architecture with lock-screen, notification, and automotive controls

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

## Configuration

1. Launch Riffhouse and enter your **Jellyfin Server URL** (e.g., `https://jellyfin.yourdomain.com`).
2. Log in with your Jellyfin username and password.
3. Your music libraries, albums, playlists, and tracks will automatically sync.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
