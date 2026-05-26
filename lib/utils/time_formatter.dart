/// Formats a lap time given in milliseconds to "mm:ss.SSS" format.
///
/// Example: 83456 ms → "01:23.456"
String formatLapTime(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final ms = milliseconds % 1000;

  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${ms.toString().padLeft(3, '0')}';
}

/// Formats a duration given in seconds to "mm:ss" format.
///
/// Example: 330 seconds → "05:30"
String formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;

  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainingSeconds.toString().padLeft(2, '0')}';
}

/// Formats a speed value in km/h with 1 decimal place.
///
/// Example: 123.456 → "123.5 km/h"
String formatSpeed(double speedKmh) {
  return '${speedKmh.toStringAsFixed(1)} km/h';
}
