import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';

/// Provider that exposes the open [AppDatabase] (Drift) instance.
///
/// `main()` opens the database before the first frame, because the audio
/// handler needs it, and overrides this provider with that instance.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
