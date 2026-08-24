/// Turning instants into the two sentences this app has to say about time.
///
/// Pure Dart, no `material.dart` and no `intl`. Both callers need it — the
/// ViewModel that phrases a moderator's confirmation and the screen that shows
/// an attendee when the doors reopen — and a formatter that lived in one of
/// them would have been copied into the other within a week.
///
/// Deliberately **not** localised. `intl` would be a dependency, a bundle of
/// locale data and a `Future` to initialise, in exchange for month names in
/// languages this app does not otherwise speak: every other word on every
/// screen here is English. A 24-hour clock is the honest version of that
/// trade — it is unambiguous everywhere, which "6:30" is not.
library;

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats [instant] on the reader's own clock: `22 Aug 2026, 18:30`.
///
/// Converted to local time first, always. Everything about a maintenance
/// window travels in UTC precisely so that this one function decides what to
/// call it, and a screen that showed the server's timezone would be telling
/// somebody the right moment in the wrong language.
String formatLocalMoment(DateTime instant) {
  final local = instant.toLocal();
  final month = _months[local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} $month ${local.year}, $hour:$minute';
}

/// Formats how much of [left] there is, for a countdown that ticks.
///
/// Drops the unit below whatever is largest: an hour away does not need
/// seconds, and a minute away does not need hours. Anything at or below zero
/// is `now`, so a caller never has to special-case the moment it lands on.
///
/// Days are the top unit, and they earn their place now that a maintenance
/// window has no ceiling: "shut until the next edition" is a legitimate
/// answer, and `8760h 00m` is a number nobody can read as a year.
String formatCountdown(Duration left) {
  if (left <= Duration.zero) return 'now';
  if (left.inDays > 0) {
    final hours = (left.inHours % 24).toString().padLeft(2, '0');
    return '${left.inDays}d ${hours}h';
  }
  if (left.inHours > 0) {
    final minutes = (left.inMinutes % 60).toString().padLeft(2, '0');
    return '${left.inHours}h ${minutes}m';
  }
  if (left.inMinutes > 0) {
    final seconds = (left.inSeconds % 60).toString().padLeft(2, '0');
    return '${left.inMinutes}m ${seconds}s';
  }
  return '${left.inSeconds}s';
}
