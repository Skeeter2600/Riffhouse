// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CachedTracksTable extends CachedTracks
    with TableInfo<$CachedTracksTable, CachedTrack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedTracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _jellyfinIdMeta =
      const VerificationMeta('jellyfinId');
  @override
  late final GeneratedColumn<String> jellyfinId = GeneratedColumn<String>(
      'jellyfin_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _localPathMeta =
      const VerificationMeta('localPath');
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
      'local_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sizeBytesMeta =
      const VerificationMeta('sizeBytes');
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
      'size_bytes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, jellyfinId, localPath, sizeBytes, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_tracks';
  @override
  VerificationContext validateIntegrity(Insertable<CachedTrack> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('jellyfin_id')) {
      context.handle(
          _jellyfinIdMeta,
          jellyfinId.isAcceptableOrUnknown(
              data['jellyfin_id']!, _jellyfinIdMeta));
    } else if (isInserting) {
      context.missing(_jellyfinIdMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(_localPathMeta,
          localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta));
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(_sizeBytesMeta,
          sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta));
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedTrack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedTrack(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      jellyfinId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}jellyfin_id'])!,
      localPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_path'])!,
      sizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}size_bytes'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $CachedTracksTable createAlias(String alias) {
    return $CachedTracksTable(attachedDatabase, alias);
  }
}

class CachedTrack extends DataClass implements Insertable<CachedTrack> {
  final int id;
  final String jellyfinId;
  final String localPath;
  final int sizeBytes;
  final DateTime cachedAt;
  const CachedTrack(
      {required this.id,
      required this.jellyfinId,
      required this.localPath,
      required this.sizeBytes,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['jellyfin_id'] = Variable<String>(jellyfinId);
    map['local_path'] = Variable<String>(localPath);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  CachedTracksCompanion toCompanion(bool nullToAbsent) {
    return CachedTracksCompanion(
      id: Value(id),
      jellyfinId: Value(jellyfinId),
      localPath: Value(localPath),
      sizeBytes: Value(sizeBytes),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedTrack.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedTrack(
      id: serializer.fromJson<int>(json['id']),
      jellyfinId: serializer.fromJson<String>(json['jellyfinId']),
      localPath: serializer.fromJson<String>(json['localPath']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'jellyfinId': serializer.toJson<String>(jellyfinId),
      'localPath': serializer.toJson<String>(localPath),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  CachedTrack copyWith(
          {int? id,
          String? jellyfinId,
          String? localPath,
          int? sizeBytes,
          DateTime? cachedAt}) =>
      CachedTrack(
        id: id ?? this.id,
        jellyfinId: jellyfinId ?? this.jellyfinId,
        localPath: localPath ?? this.localPath,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  CachedTrack copyWithCompanion(CachedTracksCompanion data) {
    return CachedTrack(
      id: data.id.present ? data.id.value : this.id,
      jellyfinId:
          data.jellyfinId.present ? data.jellyfinId.value : this.jellyfinId,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedTrack(')
          ..write('id: $id, ')
          ..write('jellyfinId: $jellyfinId, ')
          ..write('localPath: $localPath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, jellyfinId, localPath, sizeBytes, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedTrack &&
          other.id == this.id &&
          other.jellyfinId == this.jellyfinId &&
          other.localPath == this.localPath &&
          other.sizeBytes == this.sizeBytes &&
          other.cachedAt == this.cachedAt);
}

class CachedTracksCompanion extends UpdateCompanion<CachedTrack> {
  final Value<int> id;
  final Value<String> jellyfinId;
  final Value<String> localPath;
  final Value<int> sizeBytes;
  final Value<DateTime> cachedAt;
  const CachedTracksCompanion({
    this.id = const Value.absent(),
    this.jellyfinId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.cachedAt = const Value.absent(),
  });
  CachedTracksCompanion.insert({
    this.id = const Value.absent(),
    required String jellyfinId,
    required String localPath,
    required int sizeBytes,
    required DateTime cachedAt,
  })  : jellyfinId = Value(jellyfinId),
        localPath = Value(localPath),
        sizeBytes = Value(sizeBytes),
        cachedAt = Value(cachedAt);
  static Insertable<CachedTrack> custom({
    Expression<int>? id,
    Expression<String>? jellyfinId,
    Expression<String>? localPath,
    Expression<int>? sizeBytes,
    Expression<DateTime>? cachedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (jellyfinId != null) 'jellyfin_id': jellyfinId,
      if (localPath != null) 'local_path': localPath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (cachedAt != null) 'cached_at': cachedAt,
    });
  }

  CachedTracksCompanion copyWith(
      {Value<int>? id,
      Value<String>? jellyfinId,
      Value<String>? localPath,
      Value<int>? sizeBytes,
      Value<DateTime>? cachedAt}) {
    return CachedTracksCompanion(
      id: id ?? this.id,
      jellyfinId: jellyfinId ?? this.jellyfinId,
      localPath: localPath ?? this.localPath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      cachedAt: cachedAt ?? this.cachedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (jellyfinId.present) {
      map['jellyfin_id'] = Variable<String>(jellyfinId.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedTracksCompanion(')
          ..write('id: $id, ')
          ..write('jellyfinId: $jellyfinId, ')
          ..write('localPath: $localPath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }
}

class $PlaybackRecordsTable extends PlaybackRecords
    with TableInfo<$PlaybackRecordsTable, PlaybackRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaybackRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _jellyfinIdMeta =
      const VerificationMeta('jellyfinId');
  @override
  late final GeneratedColumn<String> jellyfinId = GeneratedColumn<String>(
      'jellyfin_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _playCountMeta =
      const VerificationMeta('playCount');
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
      'play_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _skipCountMeta =
      const VerificationMeta('skipCount');
  @override
  late final GeneratedColumn<int> skipCount = GeneratedColumn<int>(
      'skip_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastPlayedAtMeta =
      const VerificationMeta('lastPlayedAt');
  @override
  late final GeneratedColumn<DateTime> lastPlayedAt = GeneratedColumn<DateTime>(
      'last_played_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, jellyfinId, playCount, skipCount, lastPlayedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_records';
  @override
  VerificationContext validateIntegrity(Insertable<PlaybackRecord> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('jellyfin_id')) {
      context.handle(
          _jellyfinIdMeta,
          jellyfinId.isAcceptableOrUnknown(
              data['jellyfin_id']!, _jellyfinIdMeta));
    } else if (isInserting) {
      context.missing(_jellyfinIdMeta);
    }
    if (data.containsKey('play_count')) {
      context.handle(_playCountMeta,
          playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta));
    }
    if (data.containsKey('skip_count')) {
      context.handle(_skipCountMeta,
          skipCount.isAcceptableOrUnknown(data['skip_count']!, _skipCountMeta));
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
          _lastPlayedAtMeta,
          lastPlayedAt.isAcceptableOrUnknown(
              data['last_played_at']!, _lastPlayedAtMeta));
    } else if (isInserting) {
      context.missing(_lastPlayedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaybackRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackRecord(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      jellyfinId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}jellyfin_id'])!,
      playCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}play_count'])!,
      skipCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}skip_count'])!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_played_at'])!,
    );
  }

  @override
  $PlaybackRecordsTable createAlias(String alias) {
    return $PlaybackRecordsTable(attachedDatabase, alias);
  }
}

class PlaybackRecord extends DataClass implements Insertable<PlaybackRecord> {
  final int id;
  final String jellyfinId;
  final int playCount;
  final int skipCount;
  final DateTime lastPlayedAt;
  const PlaybackRecord(
      {required this.id,
      required this.jellyfinId,
      required this.playCount,
      required this.skipCount,
      required this.lastPlayedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['jellyfin_id'] = Variable<String>(jellyfinId);
    map['play_count'] = Variable<int>(playCount);
    map['skip_count'] = Variable<int>(skipCount);
    map['last_played_at'] = Variable<DateTime>(lastPlayedAt);
    return map;
  }

  PlaybackRecordsCompanion toCompanion(bool nullToAbsent) {
    return PlaybackRecordsCompanion(
      id: Value(id),
      jellyfinId: Value(jellyfinId),
      playCount: Value(playCount),
      skipCount: Value(skipCount),
      lastPlayedAt: Value(lastPlayedAt),
    );
  }

  factory PlaybackRecord.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackRecord(
      id: serializer.fromJson<int>(json['id']),
      jellyfinId: serializer.fromJson<String>(json['jellyfinId']),
      playCount: serializer.fromJson<int>(json['playCount']),
      skipCount: serializer.fromJson<int>(json['skipCount']),
      lastPlayedAt: serializer.fromJson<DateTime>(json['lastPlayedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'jellyfinId': serializer.toJson<String>(jellyfinId),
      'playCount': serializer.toJson<int>(playCount),
      'skipCount': serializer.toJson<int>(skipCount),
      'lastPlayedAt': serializer.toJson<DateTime>(lastPlayedAt),
    };
  }

  PlaybackRecord copyWith(
          {int? id,
          String? jellyfinId,
          int? playCount,
          int? skipCount,
          DateTime? lastPlayedAt}) =>
      PlaybackRecord(
        id: id ?? this.id,
        jellyfinId: jellyfinId ?? this.jellyfinId,
        playCount: playCount ?? this.playCount,
        skipCount: skipCount ?? this.skipCount,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      );
  PlaybackRecord copyWithCompanion(PlaybackRecordsCompanion data) {
    return PlaybackRecord(
      id: data.id.present ? data.id.value : this.id,
      jellyfinId:
          data.jellyfinId.present ? data.jellyfinId.value : this.jellyfinId,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      skipCount: data.skipCount.present ? data.skipCount.value : this.skipCount,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackRecord(')
          ..write('id: $id, ')
          ..write('jellyfinId: $jellyfinId, ')
          ..write('playCount: $playCount, ')
          ..write('skipCount: $skipCount, ')
          ..write('lastPlayedAt: $lastPlayedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, jellyfinId, playCount, skipCount, lastPlayedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackRecord &&
          other.id == this.id &&
          other.jellyfinId == this.jellyfinId &&
          other.playCount == this.playCount &&
          other.skipCount == this.skipCount &&
          other.lastPlayedAt == this.lastPlayedAt);
}

class PlaybackRecordsCompanion extends UpdateCompanion<PlaybackRecord> {
  final Value<int> id;
  final Value<String> jellyfinId;
  final Value<int> playCount;
  final Value<int> skipCount;
  final Value<DateTime> lastPlayedAt;
  const PlaybackRecordsCompanion({
    this.id = const Value.absent(),
    this.jellyfinId = const Value.absent(),
    this.playCount = const Value.absent(),
    this.skipCount = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
  });
  PlaybackRecordsCompanion.insert({
    this.id = const Value.absent(),
    required String jellyfinId,
    this.playCount = const Value.absent(),
    this.skipCount = const Value.absent(),
    required DateTime lastPlayedAt,
  })  : jellyfinId = Value(jellyfinId),
        lastPlayedAt = Value(lastPlayedAt);
  static Insertable<PlaybackRecord> custom({
    Expression<int>? id,
    Expression<String>? jellyfinId,
    Expression<int>? playCount,
    Expression<int>? skipCount,
    Expression<DateTime>? lastPlayedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (jellyfinId != null) 'jellyfin_id': jellyfinId,
      if (playCount != null) 'play_count': playCount,
      if (skipCount != null) 'skip_count': skipCount,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
    });
  }

  PlaybackRecordsCompanion copyWith(
      {Value<int>? id,
      Value<String>? jellyfinId,
      Value<int>? playCount,
      Value<int>? skipCount,
      Value<DateTime>? lastPlayedAt}) {
    return PlaybackRecordsCompanion(
      id: id ?? this.id,
      jellyfinId: jellyfinId ?? this.jellyfinId,
      playCount: playCount ?? this.playCount,
      skipCount: skipCount ?? this.skipCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (jellyfinId.present) {
      map['jellyfin_id'] = Variable<String>(jellyfinId.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (skipCount.present) {
      map['skip_count'] = Variable<int>(skipCount.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackRecordsCompanion(')
          ..write('id: $id, ')
          ..write('jellyfinId: $jellyfinId, ')
          ..write('playCount: $playCount, ')
          ..write('skipCount: $skipCount, ')
          ..write('lastPlayedAt: $lastPlayedAt')
          ..write(')'))
        .toString();
  }
}

class $LocalPlaylistsTable extends LocalPlaylists
    with TableInfo<$LocalPlaylistsTable, LocalPlaylist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _jellyfinIdMeta =
      const VerificationMeta('jellyfinId');
  @override
  late final GeneratedColumn<String> jellyfinId = GeneratedColumn<String>(
      'jellyfin_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _trackIdsJsonMeta =
      const VerificationMeta('trackIdsJson');
  @override
  late final GeneratedColumn<String> trackIdsJson = GeneratedColumn<String>(
      'track_ids_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastSyncedAtMeta =
      const VerificationMeta('lastSyncedAt');
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
      'last_synced_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, jellyfinId, name, trackIdsJson, lastSyncedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_playlists';
  @override
  VerificationContext validateIntegrity(Insertable<LocalPlaylist> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('jellyfin_id')) {
      context.handle(
          _jellyfinIdMeta,
          jellyfinId.isAcceptableOrUnknown(
              data['jellyfin_id']!, _jellyfinIdMeta));
    } else if (isInserting) {
      context.missing(_jellyfinIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('track_ids_json')) {
      context.handle(
          _trackIdsJsonMeta,
          trackIdsJson.isAcceptableOrUnknown(
              data['track_ids_json']!, _trackIdsJsonMeta));
    } else if (isInserting) {
      context.missing(_trackIdsJsonMeta);
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
          _lastSyncedAtMeta,
          lastSyncedAt.isAcceptableOrUnknown(
              data['last_synced_at']!, _lastSyncedAtMeta));
    } else if (isInserting) {
      context.missing(_lastSyncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalPlaylist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalPlaylist(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      jellyfinId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}jellyfin_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      trackIdsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}track_ids_json'])!,
      lastSyncedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_synced_at'])!,
    );
  }

  @override
  $LocalPlaylistsTable createAlias(String alias) {
    return $LocalPlaylistsTable(attachedDatabase, alias);
  }
}

class LocalPlaylist extends DataClass implements Insertable<LocalPlaylist> {
  final int id;
  final String jellyfinId;
  final String name;
  final String trackIdsJson;
  final DateTime lastSyncedAt;
  const LocalPlaylist(
      {required this.id,
      required this.jellyfinId,
      required this.name,
      required this.trackIdsJson,
      required this.lastSyncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['jellyfin_id'] = Variable<String>(jellyfinId);
    map['name'] = Variable<String>(name);
    map['track_ids_json'] = Variable<String>(trackIdsJson);
    map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    return map;
  }

  LocalPlaylistsCompanion toCompanion(bool nullToAbsent) {
    return LocalPlaylistsCompanion(
      id: Value(id),
      jellyfinId: Value(jellyfinId),
      name: Value(name),
      trackIdsJson: Value(trackIdsJson),
      lastSyncedAt: Value(lastSyncedAt),
    );
  }

  factory LocalPlaylist.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalPlaylist(
      id: serializer.fromJson<int>(json['id']),
      jellyfinId: serializer.fromJson<String>(json['jellyfinId']),
      name: serializer.fromJson<String>(json['name']),
      trackIdsJson: serializer.fromJson<String>(json['trackIdsJson']),
      lastSyncedAt: serializer.fromJson<DateTime>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'jellyfinId': serializer.toJson<String>(jellyfinId),
      'name': serializer.toJson<String>(name),
      'trackIdsJson': serializer.toJson<String>(trackIdsJson),
      'lastSyncedAt': serializer.toJson<DateTime>(lastSyncedAt),
    };
  }

  LocalPlaylist copyWith(
          {int? id,
          String? jellyfinId,
          String? name,
          String? trackIdsJson,
          DateTime? lastSyncedAt}) =>
      LocalPlaylist(
        id: id ?? this.id,
        jellyfinId: jellyfinId ?? this.jellyfinId,
        name: name ?? this.name,
        trackIdsJson: trackIdsJson ?? this.trackIdsJson,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      );
  LocalPlaylist copyWithCompanion(LocalPlaylistsCompanion data) {
    return LocalPlaylist(
      id: data.id.present ? data.id.value : this.id,
      jellyfinId:
          data.jellyfinId.present ? data.jellyfinId.value : this.jellyfinId,
      name: data.name.present ? data.name.value : this.name,
      trackIdsJson: data.trackIdsJson.present
          ? data.trackIdsJson.value
          : this.trackIdsJson,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalPlaylist(')
          ..write('id: $id, ')
          ..write('jellyfinId: $jellyfinId, ')
          ..write('name: $name, ')
          ..write('trackIdsJson: $trackIdsJson, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, jellyfinId, name, trackIdsJson, lastSyncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalPlaylist &&
          other.id == this.id &&
          other.jellyfinId == this.jellyfinId &&
          other.name == this.name &&
          other.trackIdsJson == this.trackIdsJson &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class LocalPlaylistsCompanion extends UpdateCompanion<LocalPlaylist> {
  final Value<int> id;
  final Value<String> jellyfinId;
  final Value<String> name;
  final Value<String> trackIdsJson;
  final Value<DateTime> lastSyncedAt;
  const LocalPlaylistsCompanion({
    this.id = const Value.absent(),
    this.jellyfinId = const Value.absent(),
    this.name = const Value.absent(),
    this.trackIdsJson = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
  });
  LocalPlaylistsCompanion.insert({
    this.id = const Value.absent(),
    required String jellyfinId,
    required String name,
    required String trackIdsJson,
    required DateTime lastSyncedAt,
  })  : jellyfinId = Value(jellyfinId),
        name = Value(name),
        trackIdsJson = Value(trackIdsJson),
        lastSyncedAt = Value(lastSyncedAt);
  static Insertable<LocalPlaylist> custom({
    Expression<int>? id,
    Expression<String>? jellyfinId,
    Expression<String>? name,
    Expression<String>? trackIdsJson,
    Expression<DateTime>? lastSyncedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (jellyfinId != null) 'jellyfin_id': jellyfinId,
      if (name != null) 'name': name,
      if (trackIdsJson != null) 'track_ids_json': trackIdsJson,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
    });
  }

  LocalPlaylistsCompanion copyWith(
      {Value<int>? id,
      Value<String>? jellyfinId,
      Value<String>? name,
      Value<String>? trackIdsJson,
      Value<DateTime>? lastSyncedAt}) {
    return LocalPlaylistsCompanion(
      id: id ?? this.id,
      jellyfinId: jellyfinId ?? this.jellyfinId,
      name: name ?? this.name,
      trackIdsJson: trackIdsJson ?? this.trackIdsJson,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (jellyfinId.present) {
      map['jellyfin_id'] = Variable<String>(jellyfinId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (trackIdsJson.present) {
      map['track_ids_json'] = Variable<String>(trackIdsJson.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPlaylistsCompanion(')
          ..write('id: $id, ')
          ..write('jellyfinId: $jellyfinId, ')
          ..write('name: $name, ')
          ..write('trackIdsJson: $trackIdsJson, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }
}

class $ServerConfigsTable extends ServerConfigs
    with TableInfo<$ServerConfigsTable, ServerConfig> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServerConfigsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _serverUrlMeta =
      const VerificationMeta('serverUrl');
  @override
  late final GeneratedColumn<String> serverUrl = GeneratedColumn<String>(
      'server_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _usernameMeta =
      const VerificationMeta('username');
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
      'username', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _accessTokenMeta =
      const VerificationMeta('accessToken');
  @override
  late final GeneratedColumn<String> accessToken = GeneratedColumn<String>(
      'access_token', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, serverUrl, userId, username, accessToken];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'server_configs';
  @override
  VerificationContext validateIntegrity(Insertable<ServerConfig> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_url')) {
      context.handle(_serverUrlMeta,
          serverUrl.isAcceptableOrUnknown(data['server_url']!, _serverUrlMeta));
    } else if (isInserting) {
      context.missing(_serverUrlMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('username')) {
      context.handle(_usernameMeta,
          username.isAcceptableOrUnknown(data['username']!, _usernameMeta));
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('access_token')) {
      context.handle(
          _accessTokenMeta,
          accessToken.isAcceptableOrUnknown(
              data['access_token']!, _accessTokenMeta));
    } else if (isInserting) {
      context.missing(_accessTokenMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ServerConfig map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ServerConfig(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      serverUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_url'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      username: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}username'])!,
      accessToken: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}access_token'])!,
    );
  }

  @override
  $ServerConfigsTable createAlias(String alias) {
    return $ServerConfigsTable(attachedDatabase, alias);
  }
}

class ServerConfig extends DataClass implements Insertable<ServerConfig> {
  final int id;
  final String serverUrl;
  final String userId;
  final String username;
  final String accessToken;
  const ServerConfig(
      {required this.id,
      required this.serverUrl,
      required this.userId,
      required this.username,
      required this.accessToken});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['server_url'] = Variable<String>(serverUrl);
    map['user_id'] = Variable<String>(userId);
    map['username'] = Variable<String>(username);
    map['access_token'] = Variable<String>(accessToken);
    return map;
  }

  ServerConfigsCompanion toCompanion(bool nullToAbsent) {
    return ServerConfigsCompanion(
      id: Value(id),
      serverUrl: Value(serverUrl),
      userId: Value(userId),
      username: Value(username),
      accessToken: Value(accessToken),
    );
  }

  factory ServerConfig.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ServerConfig(
      id: serializer.fromJson<int>(json['id']),
      serverUrl: serializer.fromJson<String>(json['serverUrl']),
      userId: serializer.fromJson<String>(json['userId']),
      username: serializer.fromJson<String>(json['username']),
      accessToken: serializer.fromJson<String>(json['accessToken']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serverUrl': serializer.toJson<String>(serverUrl),
      'userId': serializer.toJson<String>(userId),
      'username': serializer.toJson<String>(username),
      'accessToken': serializer.toJson<String>(accessToken),
    };
  }

  ServerConfig copyWith(
          {int? id,
          String? serverUrl,
          String? userId,
          String? username,
          String? accessToken}) =>
      ServerConfig(
        id: id ?? this.id,
        serverUrl: serverUrl ?? this.serverUrl,
        userId: userId ?? this.userId,
        username: username ?? this.username,
        accessToken: accessToken ?? this.accessToken,
      );
  ServerConfig copyWithCompanion(ServerConfigsCompanion data) {
    return ServerConfig(
      id: data.id.present ? data.id.value : this.id,
      serverUrl: data.serverUrl.present ? data.serverUrl.value : this.serverUrl,
      userId: data.userId.present ? data.userId.value : this.userId,
      username: data.username.present ? data.username.value : this.username,
      accessToken:
          data.accessToken.present ? data.accessToken.value : this.accessToken,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ServerConfig(')
          ..write('id: $id, ')
          ..write('serverUrl: $serverUrl, ')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('accessToken: $accessToken')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, serverUrl, userId, username, accessToken);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerConfig &&
          other.id == this.id &&
          other.serverUrl == this.serverUrl &&
          other.userId == this.userId &&
          other.username == this.username &&
          other.accessToken == this.accessToken);
}

class ServerConfigsCompanion extends UpdateCompanion<ServerConfig> {
  final Value<int> id;
  final Value<String> serverUrl;
  final Value<String> userId;
  final Value<String> username;
  final Value<String> accessToken;
  const ServerConfigsCompanion({
    this.id = const Value.absent(),
    this.serverUrl = const Value.absent(),
    this.userId = const Value.absent(),
    this.username = const Value.absent(),
    this.accessToken = const Value.absent(),
  });
  ServerConfigsCompanion.insert({
    this.id = const Value.absent(),
    required String serverUrl,
    required String userId,
    required String username,
    required String accessToken,
  })  : serverUrl = Value(serverUrl),
        userId = Value(userId),
        username = Value(username),
        accessToken = Value(accessToken);
  static Insertable<ServerConfig> custom({
    Expression<int>? id,
    Expression<String>? serverUrl,
    Expression<String>? userId,
    Expression<String>? username,
    Expression<String>? accessToken,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverUrl != null) 'server_url': serverUrl,
      if (userId != null) 'user_id': userId,
      if (username != null) 'username': username,
      if (accessToken != null) 'access_token': accessToken,
    });
  }

  ServerConfigsCompanion copyWith(
      {Value<int>? id,
      Value<String>? serverUrl,
      Value<String>? userId,
      Value<String>? username,
      Value<String>? accessToken}) {
    return ServerConfigsCompanion(
      id: id ?? this.id,
      serverUrl: serverUrl ?? this.serverUrl,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      accessToken: accessToken ?? this.accessToken,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverUrl.present) {
      map['server_url'] = Variable<String>(serverUrl.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (accessToken.present) {
      map['access_token'] = Variable<String>(accessToken.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServerConfigsCompanion(')
          ..write('id: $id, ')
          ..write('serverUrl: $serverUrl, ')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('accessToken: $accessToken')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedTracksTable cachedTracks = $CachedTracksTable(this);
  late final $PlaybackRecordsTable playbackRecords =
      $PlaybackRecordsTable(this);
  late final $LocalPlaylistsTable localPlaylists = $LocalPlaylistsTable(this);
  late final $ServerConfigsTable serverConfigs = $ServerConfigsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [cachedTracks, playbackRecords, localPlaylists, serverConfigs];
}

typedef $$CachedTracksTableCreateCompanionBuilder = CachedTracksCompanion
    Function({
  Value<int> id,
  required String jellyfinId,
  required String localPath,
  required int sizeBytes,
  required DateTime cachedAt,
});
typedef $$CachedTracksTableUpdateCompanionBuilder = CachedTracksCompanion
    Function({
  Value<int> id,
  Value<String> jellyfinId,
  Value<String> localPath,
  Value<int> sizeBytes,
  Value<DateTime> cachedAt,
});

class $$CachedTracksTableFilterComposer
    extends Composer<_$AppDatabase, $CachedTracksTable> {
  $$CachedTracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get jellyfinId => $composableBuilder(
      column: $table.jellyfinId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sizeBytes => $composableBuilder(
      column: $table.sizeBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedTracksTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedTracksTable> {
  $$CachedTracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get jellyfinId => $composableBuilder(
      column: $table.jellyfinId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
      column: $table.sizeBytes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedTracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedTracksTable> {
  $$CachedTracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get jellyfinId => $composableBuilder(
      column: $table.jellyfinId, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedTracksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedTracksTable,
    CachedTrack,
    $$CachedTracksTableFilterComposer,
    $$CachedTracksTableOrderingComposer,
    $$CachedTracksTableAnnotationComposer,
    $$CachedTracksTableCreateCompanionBuilder,
    $$CachedTracksTableUpdateCompanionBuilder,
    (
      CachedTrack,
      BaseReferences<_$AppDatabase, $CachedTracksTable, CachedTrack>
    ),
    CachedTrack,
    PrefetchHooks Function()> {
  $$CachedTracksTableTableManager(_$AppDatabase db, $CachedTracksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedTracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedTracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedTracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> jellyfinId = const Value.absent(),
            Value<String> localPath = const Value.absent(),
            Value<int> sizeBytes = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
          }) =>
              CachedTracksCompanion(
            id: id,
            jellyfinId: jellyfinId,
            localPath: localPath,
            sizeBytes: sizeBytes,
            cachedAt: cachedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String jellyfinId,
            required String localPath,
            required int sizeBytes,
            required DateTime cachedAt,
          }) =>
              CachedTracksCompanion.insert(
            id: id,
            jellyfinId: jellyfinId,
            localPath: localPath,
            sizeBytes: sizeBytes,
            cachedAt: cachedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedTracksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedTracksTable,
    CachedTrack,
    $$CachedTracksTableFilterComposer,
    $$CachedTracksTableOrderingComposer,
    $$CachedTracksTableAnnotationComposer,
    $$CachedTracksTableCreateCompanionBuilder,
    $$CachedTracksTableUpdateCompanionBuilder,
    (
      CachedTrack,
      BaseReferences<_$AppDatabase, $CachedTracksTable, CachedTrack>
    ),
    CachedTrack,
    PrefetchHooks Function()>;
typedef $$PlaybackRecordsTableCreateCompanionBuilder = PlaybackRecordsCompanion
    Function({
  Value<int> id,
  required String jellyfinId,
  Value<int> playCount,
  Value<int> skipCount,
  required DateTime lastPlayedAt,
});
typedef $$PlaybackRecordsTableUpdateCompanionBuilder = PlaybackRecordsCompanion
    Function({
  Value<int> id,
  Value<String> jellyfinId,
  Value<int> playCount,
  Value<int> skipCount,
  Value<DateTime> lastPlayedAt,
});

class $$PlaybackRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaybackRecordsTable> {
  $$PlaybackRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get jellyfinId => $composableBuilder(
      column: $table.jellyfinId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get playCount => $composableBuilder(
      column: $table.playCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get skipCount => $composableBuilder(
      column: $table.skipCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastPlayedAt => $composableBuilder(
      column: $table.lastPlayedAt, builder: (column) => ColumnFilters(column));
}

class $$PlaybackRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaybackRecordsTable> {
  $$PlaybackRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get jellyfinId => $composableBuilder(
      column: $table.jellyfinId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get playCount => $composableBuilder(
      column: $table.playCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get skipCount => $composableBuilder(
      column: $table.skipCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastPlayedAt => $composableBuilder(
      column: $table.lastPlayedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$PlaybackRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaybackRecordsTable> {
  $$PlaybackRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get jellyfinId => $composableBuilder(
      column: $table.jellyfinId, builder: (column) => column);

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<int> get skipCount =>
      $composableBuilder(column: $table.skipCount, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPlayedAt => $composableBuilder(
      column: $table.lastPlayedAt, builder: (column) => column);
}

class $$PlaybackRecordsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PlaybackRecordsTable,
    PlaybackRecord,
    $$PlaybackRecordsTableFilterComposer,
    $$PlaybackRecordsTableOrderingComposer,
    $$PlaybackRecordsTableAnnotationComposer,
    $$PlaybackRecordsTableCreateCompanionBuilder,
    $$PlaybackRecordsTableUpdateCompanionBuilder,
    (
      PlaybackRecord,
      BaseReferences<_$AppDatabase, $PlaybackRecordsTable, PlaybackRecord>
    ),
    PlaybackRecord,
    PrefetchHooks Function()> {
  $$PlaybackRecordsTableTableManager(
      _$AppDatabase db, $PlaybackRecordsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaybackRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaybackRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaybackRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> jellyfinId = const Value.absent(),
            Value<int> playCount = const Value.absent(),
            Value<int> skipCount = const Value.absent(),
            Value<DateTime> lastPlayedAt = const Value.absent(),
          }) =>
              PlaybackRecordsCompanion(
            id: id,
            jellyfinId: jellyfinId,
            playCount: playCount,
            skipCount: skipCount,
            lastPlayedAt: lastPlayedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String jellyfinId,
            Value<int> playCount = const Value.absent(),
            Value<int> skipCount = const Value.absent(),
            required DateTime lastPlayedAt,
          }) =>
              PlaybackRecordsCompanion.insert(
            id: id,
            jellyfinId: jellyfinId,
            playCount: playCount,
            skipCount: skipCount,
            lastPlayedAt: lastPlayedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PlaybackRecordsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PlaybackRecordsTable,
    PlaybackRecord,
    $$PlaybackRecordsTableFilterComposer,
    $$PlaybackRecordsTableOrderingComposer,
    $$PlaybackRecordsTableAnnotationComposer,
    $$PlaybackRecordsTableCreateCompanionBuilder,
    $$PlaybackRecordsTableUpdateCompanionBuilder,
    (
      PlaybackRecord,
      BaseReferences<_$AppDatabase, $PlaybackRecordsTable, PlaybackRecord>
    ),
    PlaybackRecord,
    PrefetchHooks Function()>;
typedef $$LocalPlaylistsTableCreateCompanionBuilder = LocalPlaylistsCompanion
    Function({
  Value<int> id,
  required String jellyfinId,
  required String name,
  required String trackIdsJson,
  required DateTime lastSyncedAt,
});
typedef $$LocalPlaylistsTableUpdateCompanionBuilder = LocalPlaylistsCompanion
    Function({
  Value<int> id,
  Value<String> jellyfinId,
  Value<String> name,
  Value<String> trackIdsJson,
  Value<DateTime> lastSyncedAt,
});

class $$LocalPlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalPlaylistsTable> {
  $$LocalPlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get jellyfinId => $composableBuilder(
      column: $table.jellyfinId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get trackIdsJson => $composableBuilder(
      column: $table.trackIdsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalPlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalPlaylistsTable> {
  $$LocalPlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get jellyfinId => $composableBuilder(
      column: $table.jellyfinId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get trackIdsJson => $composableBuilder(
      column: $table.trackIdsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$LocalPlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalPlaylistsTable> {
  $$LocalPlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get jellyfinId => $composableBuilder(
      column: $table.jellyfinId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get trackIdsJson => $composableBuilder(
      column: $table.trackIdsJson, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => column);
}

class $$LocalPlaylistsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalPlaylistsTable,
    LocalPlaylist,
    $$LocalPlaylistsTableFilterComposer,
    $$LocalPlaylistsTableOrderingComposer,
    $$LocalPlaylistsTableAnnotationComposer,
    $$LocalPlaylistsTableCreateCompanionBuilder,
    $$LocalPlaylistsTableUpdateCompanionBuilder,
    (
      LocalPlaylist,
      BaseReferences<_$AppDatabase, $LocalPlaylistsTable, LocalPlaylist>
    ),
    LocalPlaylist,
    PrefetchHooks Function()> {
  $$LocalPlaylistsTableTableManager(
      _$AppDatabase db, $LocalPlaylistsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalPlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalPlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> jellyfinId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> trackIdsJson = const Value.absent(),
            Value<DateTime> lastSyncedAt = const Value.absent(),
          }) =>
              LocalPlaylistsCompanion(
            id: id,
            jellyfinId: jellyfinId,
            name: name,
            trackIdsJson: trackIdsJson,
            lastSyncedAt: lastSyncedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String jellyfinId,
            required String name,
            required String trackIdsJson,
            required DateTime lastSyncedAt,
          }) =>
              LocalPlaylistsCompanion.insert(
            id: id,
            jellyfinId: jellyfinId,
            name: name,
            trackIdsJson: trackIdsJson,
            lastSyncedAt: lastSyncedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalPlaylistsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalPlaylistsTable,
    LocalPlaylist,
    $$LocalPlaylistsTableFilterComposer,
    $$LocalPlaylistsTableOrderingComposer,
    $$LocalPlaylistsTableAnnotationComposer,
    $$LocalPlaylistsTableCreateCompanionBuilder,
    $$LocalPlaylistsTableUpdateCompanionBuilder,
    (
      LocalPlaylist,
      BaseReferences<_$AppDatabase, $LocalPlaylistsTable, LocalPlaylist>
    ),
    LocalPlaylist,
    PrefetchHooks Function()>;
typedef $$ServerConfigsTableCreateCompanionBuilder = ServerConfigsCompanion
    Function({
  Value<int> id,
  required String serverUrl,
  required String userId,
  required String username,
  required String accessToken,
});
typedef $$ServerConfigsTableUpdateCompanionBuilder = ServerConfigsCompanion
    Function({
  Value<int> id,
  Value<String> serverUrl,
  Value<String> userId,
  Value<String> username,
  Value<String> accessToken,
});

class $$ServerConfigsTableFilterComposer
    extends Composer<_$AppDatabase, $ServerConfigsTable> {
  $$ServerConfigsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverUrl => $composableBuilder(
      column: $table.serverUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get accessToken => $composableBuilder(
      column: $table.accessToken, builder: (column) => ColumnFilters(column));
}

class $$ServerConfigsTableOrderingComposer
    extends Composer<_$AppDatabase, $ServerConfigsTable> {
  $$ServerConfigsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverUrl => $composableBuilder(
      column: $table.serverUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get accessToken => $composableBuilder(
      column: $table.accessToken, builder: (column) => ColumnOrderings(column));
}

class $$ServerConfigsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ServerConfigsTable> {
  $$ServerConfigsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverUrl =>
      $composableBuilder(column: $table.serverUrl, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get accessToken => $composableBuilder(
      column: $table.accessToken, builder: (column) => column);
}

class $$ServerConfigsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ServerConfigsTable,
    ServerConfig,
    $$ServerConfigsTableFilterComposer,
    $$ServerConfigsTableOrderingComposer,
    $$ServerConfigsTableAnnotationComposer,
    $$ServerConfigsTableCreateCompanionBuilder,
    $$ServerConfigsTableUpdateCompanionBuilder,
    (
      ServerConfig,
      BaseReferences<_$AppDatabase, $ServerConfigsTable, ServerConfig>
    ),
    ServerConfig,
    PrefetchHooks Function()> {
  $$ServerConfigsTableTableManager(_$AppDatabase db, $ServerConfigsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ServerConfigsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ServerConfigsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ServerConfigsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> serverUrl = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<String> username = const Value.absent(),
            Value<String> accessToken = const Value.absent(),
          }) =>
              ServerConfigsCompanion(
            id: id,
            serverUrl: serverUrl,
            userId: userId,
            username: username,
            accessToken: accessToken,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String serverUrl,
            required String userId,
            required String username,
            required String accessToken,
          }) =>
              ServerConfigsCompanion.insert(
            id: id,
            serverUrl: serverUrl,
            userId: userId,
            username: username,
            accessToken: accessToken,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ServerConfigsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ServerConfigsTable,
    ServerConfig,
    $$ServerConfigsTableFilterComposer,
    $$ServerConfigsTableOrderingComposer,
    $$ServerConfigsTableAnnotationComposer,
    $$ServerConfigsTableCreateCompanionBuilder,
    $$ServerConfigsTableUpdateCompanionBuilder,
    (
      ServerConfig,
      BaseReferences<_$AppDatabase, $ServerConfigsTable, ServerConfig>
    ),
    ServerConfig,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedTracksTableTableManager get cachedTracks =>
      $$CachedTracksTableTableManager(_db, _db.cachedTracks);
  $$PlaybackRecordsTableTableManager get playbackRecords =>
      $$PlaybackRecordsTableTableManager(_db, _db.playbackRecords);
  $$LocalPlaylistsTableTableManager get localPlaylists =>
      $$LocalPlaylistsTableTableManager(_db, _db.localPlaylists);
  $$ServerConfigsTableTableManager get serverConfigs =>
      $$ServerConfigsTableTableManager(_db, _db.serverConfigs);
}
