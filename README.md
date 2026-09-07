<div align="center">
  <img width="150" height="150" alt="Riffhouse Logo" src="https://github.com/user-attachments/assets/9d61bfa1-f5ed-4f75-9689-634041852850" />
  
  # Riffhouse
  
  **A native music streaming client for your self-hosted Jellyfin server**
  
  [![GitHub Release](https://img.shields.io/badge/release-v1.0-blue)](https://github.com/Skeeter2600/Riffhouse/releases)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
  [![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)](https://flutter.dev)
  [![Platform Support](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-brightgreen)](#platform-support)

</div>

---

## What is Riffhouse?

Riffhouse is a lightweight, cross-platform music streaming client that connects to your **self-hosted Jellyfin media server**. No subscriptions, no tracking, no ads—just your music library, your way. Stream your personal collection anywhere, offline-first caching, integrated podcasts, and built-in Android Auto support.

**Perfect for:** Anyone with a Jellyfin server who wants a native, feature-rich music app that works offline and feels at home on their device.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Features](#features)
- [Installation](#installation)
  - [Pre-built Downloads](#pre-built-downloads)
  - [iOS Sideloading](#ios-sideloading)
- [Building from Source](#building-from-source)
- [Configuration](#configuration)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Quick Start

1. **Download** the latest [release](https://github.com/Skeeter2600/Riffhouse/releases) for your platform
2. **Install** using the instructions below
3. **Launch** Riffhouse
4. **Enter** your Jellyfin server URL (e.g., `https://jellyfin.yourdomain.com`)
5. **Log in** with your Jellyfin credentials
6. **Start streaming** your library instantly

Done! Your playlists, artists, and albums sync automatically.

---

## Features

### Core Streaming
- 🎵 **Full Jellyfin Integration** — Stream your entire music library with full artist, album, and playlist support
- 📱 **Cross-Platform** — Native apps for Android, iOS, Windows, macOS, and Linux
- 🔄 **Persistent Playback** — Background audio service with lock-screen controls and persistent notifications

### Offline & Caching
- 💾 **Offline Playback** — Download albums and tracks to listen without internet
- ⚡ **Smart Caching** — Automatic metadata caching for offline library browsing

### Discovery & Organization
- 🎼 **Smart Mixes** — Daily Mixes, Heavy Rotation, and Undiscovered Tracks based on your listening habits
- 🎙️ **Integrated Podcasts** — Add RSS feeds alongside your music library in a unified player
- 📊 **Queue Management** — Full reorderable queue with persistent controls

### Mobile & Automotive
- 🚗 **Android Auto Integration** — Native automotive UI with safe controls and queue browsing
- 🔒 **Lock Screen Controls** — Quick playback controls directly from your device lock screen

---

## Installation

### Pre-built Downloads

All releases are available on the [GitHub Releases](https://github.com/Skeeter2600/Riffhouse/releases) page.

| Platform | File | Installation |
|----------|------|--------------|
| **Android** | `Riffhouse-Android.apk` | Download and tap to install. Allow installation from your browser if prompted. |
| **Windows** | `Riffhouse-Windows-x64.zip` | Extract and run `Riffhouse.exe`. Windows Defender SmartScreen may appear—click "Run anyway." |
| **macOS** | `Riffhouse-macOS.zip` | Extract and drag `Riffhouse.app` to `/Applications`. If Gatekeeper blocks it, right-click → **Open**. |
| **Linux** | `Riffhouse-Linux-x64.tar.gz` | Extract: `tar -xvf Riffhouse-Linux-x64.tar.gz && ./riffhouse` |
| **iOS** | `Riffhouse.ipa` | See [iOS Sideloading](#ios-sideloading) below. |

#### Platform Notes

- **Android:** Works best on Android 8.0+. Android Auto requires Android 5.0+.
- **iOS:** Requires personal Apple ID for sideloading (free). Certificate refreshes every 7 days with AltStore.
- **Windows/macOS:** First launch may take 10–15 seconds on initial startup.

---

### iOS Sideloading

Since Riffhouse isn't on the App Store, you'll use your Apple ID to sideload it. I am working on getting this (and adding Apple CarPlay support as well), but need further testing with it. For the time being, to just use it, there are two methods:

#### Method A: Sideloadly (Recommended for Beginners)
1. Download `Riffhouse.ipa` and install [Sideloadly](https://sideloadly.io/)
2. Connect your iPhone via USB (or Wi-Fi after initial pairing)
3. Drag `Riffhouse.ipa` into Sideloadly
4. Enter your Apple ID email and tap **Start**
5. On your iPhone: **Settings → General → VPN & Device Management**
6. Tap your Apple ID and trust the app
7. (iOS 16+) Enable **Developer Mode** in **Settings → Privacy & Security**

**✅ You're set!** The app stays installed until your certificate expires (7 days), then refresh via Sideloadly.

#### Method B: AltStore / SideStore (On-Device)
1. Install [AltStore](https://altstore.io/) or [SideStore](https://sidestore.io/)
2. Download `Riffhouse.ipa` in Safari on your iPhone
3. Open AltStore/SideStore → **My Apps** → **+**
4. Select the IPA to install
5. App auto-refreshes every 7 days if AltStore/SideStore stays open

---

## Building from Source

Want to contribute or customize Riffhouse? Here's how to build it yourself.

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.x or higher)
- [Git](https://git-scm.com/)
- Platform-specific tools:
  - **Android:** Android Studio + Android SDK
  - **Windows:** Visual Studio 2022 (Desktop C++ development)
  - **macOS/iOS:** Xcode + CocoaPods
  - **Linux:** Clang, CMake, Ninja, GTK 3 dev libraries
    ```bash
    sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
    ```

### Build Steps

```bash
# 1. Clone & enter the repo
git clone https://github.com/Skeeter2600/Riffhouse.git
cd Riffhouse

# 2. Install Dart & Flutter dependencies
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# 3. Build for your platform (see below)
```

**Android:**
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

**Windows:**
```bash
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

**macOS:**
```bash
flutter build macos --release
# Output: build/macos/Build/Products/Release/Riffhouse.app
```

**Linux:**
```bash
flutter build linux --release
# Output: build/linux/x64/release/bundle/
```

**iOS (Sideloadable IPA):**
```bash
flutter build ipa --release --no-codesign
mkdir -p Payload
cp -r build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app Payload/
zip -r Riffhouse.ipa Payload
```

---

## Configuration

### First Launch

1. Enter your **Jellyfin Server URL** (e.g., `https://jellyfin.example.com`)
2. Log in with your Jellyfin username & password
3. Your libraries sync automatically in the background

### Optional Settings

- **Cache Limit** — Set how much local storage to use for offline downloads
- **Audio Quality** — Choose between high-quality and mobile-friendly bitrates
- **Server URL** — Change servers anytime in Settings

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| **Framework** | [Flutter](https://flutter.dev/) (Dart) |
| **Media Backend** | [Jellyfin REST API](https://jellyfin.org/) |
| **State Management** | Riverpod / Provider pattern |
| **Local Database** | Drift / SQLite (offline metadata, caching) |
| **Audio Engine** | Flutter Audio Background Service with lock screen & automotive controls |

---

## Project Structure

```
lib/
├── audio/          # Background playback, queue, Android Auto integration
├── database/       # SQLite schema, DAOs, generated bindings
├── models/         # Jellyfin data models, podcasts, mix configs
├── providers/      # State management (Auth, Library, Podcasts, Database)
├── router/         # Navigation routing
├── screens/        # UI screens (Player, Library, Playlists, Settings)
├── services/       # API clients (Jellyfin, Podcasts, Cache, Playlists)
├── theme/          # Theming, colors, typography
└── widgets/        # Reusable components (MiniPlayer, AlbumCard, etc.)
```

---

## Contributing

We'd love your help! Whether it's bug reports, feature requests, or code contributions:

1. **Found a bug?** Open an [Issue](https://github.com/Skeeter2600/Riffhouse/issues)
2. **Have a feature idea?** Start a [Discussion](https://github.com/Skeeter2600/Riffhouse/discussions)
3. **Want to code?** Fork the repo and submit a [Pull Request](https://github.com/Skeeter2600/Riffhouse/pulls)

### Development Tips
- Use `flutter run` during development (hot reload enabled)
- Run tests with `flutter test`
- Code style follows Dart conventions (enforced by `dart format`)
- For Android Auto features, test on a real device or emulator with Google Play Services

---

## License

This project is licensed under the [MIT License](LICENSE) — free to use, modify, and distribute. Just please give me credit :)

---

**Have questions?** Open an Issue or start a Discussion on GitHub.
