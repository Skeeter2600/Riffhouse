import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps the last good answer to every library request on disk and serves it
/// when the server cannot be reached, so albums, artists and playlists stay
/// browsable offline.
///
/// Only connection problems fall back to the cache. An answer from the server
/// (including an error such as 401) is always passed through unchanged.
class OfflineCacheInterceptor extends Interceptor {
  /// Set in a request's `extra` to keep it out of the cache: requests whose
  /// result must reflect the server right now (session checks, full library
  /// syncs) or that make no sense offline (search).
  static const skip = 'skipOfflineCache';

  /// Set in the `extra` of a response that was served from the cache.
  static const servedFromCache = 'servedFromOfflineCache';

  /// After a connection failure, cached answers are used straight away for
  /// this long instead of waiting for every request to time out again.
  static const _unreachableWindow = Duration(seconds: 30);

  static DateTime? _unreachableUntil;
  static Directory? _directory;

  final String _userId;

  /// Override for tests.
  final Directory? directory;

  OfflineCacheInterceptor(this._userId, {this.directory});

  /// Forget that the server was unreachable, e.g. after signing in again.
  static void resetReachability() => _unreachableUntil = null;

  Future<Directory> _cacheDir() async {
    final override = directory;
    if (override != null) return override;
    var dir = _directory;
    if (dir == null) {
      final support = await getApplicationSupportDirectory();
      dir = Directory(p.join(support.path, 'api_cache'));
      await dir.create(recursive: true);
      _directory = dir;
    }
    return dir;
  }

  bool _eligible(RequestOptions options) =>
      options.method == 'GET' &&
      options.extra[skip] != true &&
      options.responseType == ResponseType.json &&
      _userId.isNotEmpty;

  Future<File> _fileFor(RequestOptions options) async {
    final key = sha1.convert(utf8.encode('$_userId|${options.uri}')).toString();
    return File(p.join((await _cacheDir()).path, '$key.json'));
  }

  Future<Response<dynamic>?> _cached(RequestOptions options) async {
    try {
      final file = await _fileFor(options);
      if (!await file.exists()) return null;
      return Response<dynamic>(
        requestOptions: options,
        data: jsonDecode(await file.readAsString()),
        statusCode: 200,
        extra: {servedFromCache: true},
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _store(RequestOptions options, Object data) async {
    try {
      final file = await _fileFor(options);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(data));
      await temp.rename(file.path);
    } catch (_) {
      // The cache is best effort.
    }
  }

  static bool _isConnectionProblem(DioException error) {
    if (error.response != null) return false;
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      default:
        // Cancelled, a bad certificate, or an answer we could not use.
        return false;
    }
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final until = _unreachableUntil;
    if (until != null && DateTime.now().isBefore(until) && _eligible(options)) {
      final cached = await _cached(options);
      if (cached != null) return handler.resolve(cached);
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    _unreachableUntil = null;
    final data = response.data;
    if (response.statusCode == 200 &&
        (data is Map || data is List) &&
        _eligible(response.requestOptions)) {
      await _store(response.requestOptions, data as Object);
    }
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (_isConnectionProblem(err)) {
      _unreachableUntil = DateTime.now().add(_unreachableWindow);
      if (_eligible(err.requestOptions)) {
        final cached = await _cached(err.requestOptions);
        if (cached != null) return handler.resolve(cached);
      }
    }
    handler.next(err);
  }
}
