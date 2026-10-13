import 'package:intl/intl.dart';

/// Track length as `m:ss`.
String formatDuration(Duration d) {
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '${d.inMinutes}:$seconds';
}

/// Track length in milliseconds as `m:ss`.
String formatDurationMs(int ms) => formatDuration(Duration(milliseconds: ms));

/// Podcast episode length in whole minutes. Feeds that omit the length get
/// the typical range for the news briefings the app ships with.
String formatEpisodeLength(Duration duration) {
  if (duration == Duration.zero) return '10-15 mins';
  return '${duration.inMinutes} min';
}

/// "Today", "Yesterday" or a date such as "Monday, Oct 12"
/// ("Mon, Oct 12" when [shortWeekday] is set).
String formatRelativeDate(DateTime date, {bool shortWeekday = false}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final day = DateTime(date.year, date.month, date.day);

  if (day == today) return 'Today';
  if (day == yesterday) return 'Yesterday';
  return DateFormat(shortWeekday ? 'EEE, MMM d' : 'EEEE, MMM d').format(date);
}

/// A file size with a unit that keeps the number short.
String formatBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / gb).toStringAsFixed(2)} GB';
}
