import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart';

class Logging {
  // Flag to track initialization status
  static bool _initialized = false;

  // Early message queue
  static final List<String> _earlyMessages = [];

  static void setupLogging() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      // Use debugPrint instead of print for better logging
      debugPrint('${record.level.name}: ${record.time}: ${record.message}');
      if (record.error != null) {
        debugPrint('Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        debugPrint('Stack trace: ${record.stackTrace}');
      }
    });
  }

  // Initialize the logging system
  static void initialize() {
    if (_initialized) return;

    // Process any early messages that were logged before initialization
    for (final message in _earlyMessages) {
      debugPrint('PROCESSED EARLY LOG: $message');
    }
    _earlyMessages.clear();

    _initialized = true;
    debugPrint('Logging system initialized');
  }

  static void severe(String message, [Object? error, StackTrace? stackTrace]) {
    // If not initialized yet, queue the message and also print it with a special prefix
    if (!_initialized) {
      _earlyMessages.add(message);
      debugPrint('EARLY LOG: $message');

      if (error != null) {
        debugPrint('EARLY ERROR: $error');
        if (stackTrace != null) {
          debugPrint('EARLY STACK: $stackTrace');
        }
      }
      return;
    }

    // Regular logging once initialized
    debugPrint('LOG: $message');
    if (error != null) {
      debugPrint('ERROR: $error');
      if (stackTrace != null) {
        debugPrint('STACK: $stackTrace');
      }
    }
  }

  // Mark the system as initialized - call this early in main()
  static void markInitialized() {
    _initialized = true;
    severe('Logging system manually marked as initialized');
  }

  // Add this method to flush early messages
  static void flushEarlyMessages() {
    _initialized = true;
    for (final message in _earlyMessages) {
      debugPrint(message);
    }
    _earlyMessages.clear();
  }
}
