import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';
import '../services/database_service.dart';

/// Provider that exposes the open [AppDatabase] (Drift) instance.
final databaseProvider = Provider<AppDatabase>((ref) {
  return DatabaseService.instance;
});
