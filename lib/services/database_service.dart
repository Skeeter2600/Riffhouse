import '../database/app_database.dart';

class DatabaseService {
  static AppDatabase? _instance;

  static AppDatabase get instance {
    _instance ??= AppDatabase();
    return _instance!;
  }
}
