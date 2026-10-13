import 'package:flutter/foundation.dart';

/// Logs [message] in debug builds only, so release builds never write server
/// addresses, user ids or response bodies to the system log.
void logDebug(String message) {
  if (kDebugMode) debugPrint(message);
}
