import 'package:flutter/foundation.dart';

/// A zero-cost static utility for logging that respects kDebugMode.
/// This prevents expensive string interpolations from occurring in release builds.
class AppLogger {
  AppLogger._();

  /// Logs a debug message.
  static void d(String message) {
    if (kDebugMode) {
      debugPrint('[DEBUG] $message');
    }
  }

  /// Alias for d() for legacy/convenience support.
  static void print(String message) => d(message);

  /// Logs an error message with optional error and stack trace.
  static void e(String message, [dynamic error, StackTrace? stack]) {
    if (kDebugMode) {
      debugPrint('[ERROR] $message');
      if (error != null) {
        debugPrint('Error Details: $error');
      }
      if (stack != null) {
        debugPrint('Stack Trace:\n$stack');
      }
    }
  }

  /// Logs an info message.
  static void i(String message) {
    if (kDebugMode) {
      debugPrint('[INFO] $message');
    }
  }

  /// Logs a warning message.
  static void w(String message) {
    if (kDebugMode) {
      debugPrint('[WARNING] $message');
    }
  }
}
