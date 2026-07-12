/// Plain data classes used to map Jellyfin API responses.
/// These are NOT Isar collections — they are transient models for network data.

class JellyfinUser {
  final String id;
  final String name;
  final String accessToken;
  final bool isAdmin;

  String get jellyfinId => id;

  const JellyfinUser({
    required this.id,
    required this.name,
    required this.accessToken,
    required this.isAdmin,
  });

  factory JellyfinUser.fromJson(Map<String, dynamic> json) {
    final user = json['User'] as Map<String, dynamic>? ?? json;
    return JellyfinUser(
      id: (user['Id'] as String?) ?? '',
      name: (user['Name'] as String?) ?? '',
      accessToken: (json['AccessToken'] as String?) ?? '',
      isAdmin: (user['Policy']?['IsAdministrator'] as bool?) ?? false,
    );
  }

  @override
  String toString() =>
      'JellyfinUser(id: $id, name: $name, isAdmin: $isAdmin)';
}

class JellyfinTrack {
  final String id;
  final String name;
  final List<String> artists;
  final String albumArtist;
  final String albumId;
  final String albumName;
  final List<String> genres;
  final int durationMs;
  final String serverId;
  final String? imageTag;

  String get jellyfinId => id;
  String get title => name;
  String get album => albumName;
  String get artist => artists.isNotEmpty ? artists.join(', ') : albumArtist;
  Duration get duration => Duration(milliseconds: durationMs);
  String? get artUri => null;
  String? get streamUrl => null;

  const JellyfinTrack({
    required this.id,
    required this.name,
    required this.artists,
    required this.albumArtist,
    required this.albumId,
    required this.albumName,
    required this.genres,
    required this.durationMs,
    required this.serverId,
    this.imageTag,
  });

  factory JellyfinTrack.fromJson(Map<String, dynamic> json) {
    // Artists may come as a list of strings or list of objects
    List<String> parseArtists(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) {
        return raw.map((a) {
          if (a is String) return a;
          if (a is Map) return (a['Name'] as String?) ?? '';
          return '';
        }).where((s) => s.isNotEmpty).toList();
      }
      return [];
    }

    // Jellyfin stores duration in ticks (100-nanosecond intervals)
    final ticks = json['RunTimeTicks'] as int? ?? 0;
    final durationMs = (ticks / 10000).round();

    // Primary image tag lives at ImageTags.Primary
    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    final imageTag = imageTags?['Primary'] as String?;

    return JellyfinTrack(
      id: (json['Id'] as String?) ?? '',
      name: (json['Name'] as String?) ?? '',
      artists: parseArtists(json['Artists']),
      albumArtist: (json['AlbumArtist'] as String?) ?? '',
      albumId: (json['AlbumId'] as String?) ?? '',
      albumName: (json['Album'] as String?) ?? '',
      genres: List<String>.from(json['Genres'] as List? ?? []),
      durationMs: durationMs,
      serverId: (json['ServerId'] as String?) ?? '',
      imageTag: imageTag,
    );
  }

  @override
  String toString() =>
      'JellyfinTrack(id: $id, name: $name, artists: $artists)';
}

class JellyfinAlbum {
  final String id;
  final String name;
  final String artist;
  final int? year;
  final String? imageTag;
  final int trackCount;

  String get jellyfinId => id;
  String? get artUri => null;
  String get artistId => '';

  const JellyfinAlbum({
    required this.id,
    required this.name,
    required this.artist,
    this.year,
    this.imageTag,
    required this.trackCount,
  });

  factory JellyfinAlbum.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    final imageTag = imageTags?['Primary'] as String?;

    return JellyfinAlbum(
      id: (json['Id'] as String?) ?? '',
      name: (json['Name'] as String?) ?? '',
      artist: (json['AlbumArtist'] as String?) ?? '',
      year: json['ProductionYear'] as int?,
      imageTag: imageTag,
      trackCount: (json['ChildCount'] as int?) ?? 0,
    );
  }

  @override
  String toString() =>
      'JellyfinAlbum(id: $id, name: $name, artist: $artist, year: $year)';
}

class JellyfinArtist {
  final String id;
  final String name;
  final String? imageTag;

  String get jellyfinId => id;
  String? get artUri => null;

  const JellyfinArtist({
    required this.id,
    required this.name,
    this.imageTag,
  });

  factory JellyfinArtist.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    final imageTag = imageTags?['Primary'] as String?;

    return JellyfinArtist(
      id: (json['Id'] as String?) ?? '',
      name: (json['Name'] as String?) ?? '',
      imageTag: imageTag,
    );
  }

  @override
  String toString() => 'JellyfinArtist(id: $id, name: $name)';
}

class JellyfinPlaylist {
  final String id;
  final String name;
  final int trackCount;
  final String? imageTag;

  String get jellyfinId => id;
  String? get artUri => null;

  const JellyfinPlaylist({
    required this.id,
    required this.name,
    required this.trackCount,
    this.imageTag,
  });

  factory JellyfinPlaylist.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    final imageTag = imageTags?['Primary'] as String?;

    return JellyfinPlaylist(
      id: (json['Id'] as String?) ?? '',
      name: (json['Name'] as String?) ?? '',
      trackCount: (json['ChildCount'] as int?) ?? 0,
      imageTag: imageTag,
    );
  }

  @override
  String toString() =>
      'JellyfinPlaylist(id: $id, name: $name, trackCount: $trackCount)';
}
