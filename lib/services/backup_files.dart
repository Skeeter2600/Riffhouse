import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Lets the user choose where a backup file is saved, and pick one to restore.
class BackupFiles {
  static const _channel = MethodChannel('com.riffhouse/files');

  static const _jsonFiles = XTypeGroup(
    label: 'Riffhouse backup',
    extensions: ['json'],
    mimeTypes: ['application/json'],
    uniformTypeIdentifiers: ['public.json'],
  );

  /// Saves [bytes] as [fileName] where the user chooses. Returns a short
  /// description of where it went, or null if the user cancelled.
  static Future<String?> save(String fileName, Uint8List bytes) async {
    if (!kIsWeb && Platform.isAndroid) {
      // Android's "create document" picker; the activity writes the file.
      final saved = await _channel.invokeMethod<bool>('saveFile', {
        'name': fileName,
        'mimeType': 'application/json',
        'bytes': bytes,
      });
      return saved == true ? fileName : null;
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [_jsonFiles],
      );
      if (location == null) return null;
      await File(location.path).writeAsBytes(bytes, flush: true);
      return location.path;
    }

    // No save dialog here (iOS): the app's documents folder is the one place
    // the user can reach, through the Files app.
    final documents = await getApplicationDocumentsDirectory();
    final file = File(p.join(documents.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Lets the user pick a backup file and returns its contents, or null if
  /// they cancelled.
  static Future<Uint8List?> pick() async {
    final file = await openFile(acceptedTypeGroups: const [_jsonFiles]);
    return file?.readAsBytes();
  }
}
