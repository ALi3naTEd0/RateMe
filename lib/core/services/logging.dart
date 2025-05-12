import 'package:flutter/foundation.dart';

/// Enhanced logging system with categorization and filtering
class Logging {
  // Set the default log level (can be changed in settings)
  static LogLevel _currentLevel = LogLevel.info;

  // Enable or disable categories (can be exposed through settings)
  static final Map<String, bool> _enabledCategories = {
    'ALBUMS': true,
    'LISTS': true,
    'RATINGS': true,
    'ARTWORK': true,
    'SEARCH': true,
    'NETWORK': true,
    'DATABASE': true,
    'UI': false, // Disable verbose UI logs by default
    'DEBUG': kDebugMode, // Only enable DEBUG in debug builds
  };

  /// Initialize the logging system
  static void initialize() {
    severe('===== Logging system initialized =====');

    // In debug mode, show the enabled categories
    if (kDebugMode) {
      final enabledCats = _enabledCategories.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .join(', ');
      debug('[DEBUG] Enabled log categories: $enabledCats');
    }
  }

  /// Set the current log level
  static void setLogLevel(LogLevel level) {
    _currentLevel = level;
    severe('Log level set to: $_currentLevel');
  }

  /// Enable or disable a specific log category
  static void setCategory(String category, bool enabled) {
    _enabledCategories[category] = enabled;
  }

  /// Log a debug message (lowest priority)
  static void debug(String message, [Object? error, StackTrace? stackTrace]) {
    if (_currentLevel.index <= LogLevel.debug.index) {
      _log('DEBUG', message, error, stackTrace);
    }
  }

  /// Log an informational message
  static void info(String message, [Object? error, StackTrace? stackTrace]) {
    if (_currentLevel.index <= LogLevel.info.index) {
      _log('INFO', message, error, stackTrace);
    }
  }

  /// Log a warning message
  static void warning(String message, [Object? error, StackTrace? stackTrace]) {
    if (_currentLevel.index <= LogLevel.warning.index) {
      _log('WARNING', message, error, stackTrace);
    }
  }

  /// Log an error message
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (_currentLevel.index <= LogLevel.error.index) {
      _log('ERROR', message, error, stackTrace);
    }
  }

  /// Log a severe message (highest priority)
  static void severe(String message, [Object? error, StackTrace? stackTrace]) {
    if (_currentLevel.index <= LogLevel.severe.index) {
      _log('SEVERE', message, error, stackTrace);
    }
  }

  /// Internal log method that filters by category and formats the output
  static void _log(String level, String message,
      [Object? error, StackTrace? stackTrace]) {
    // Check if this message has a category tag like [CATEGORY]
    String? category;
    if (message.startsWith('[') && message.contains(']')) {
      category = message.substring(1, message.indexOf(']'));

      // Skip logging if category is disabled
      if (!(_enabledCategories[category] ?? true)) {
        return;
      }
    }

    // Format for regular debug.log
    final logMessage =
        '${DateTime.now().toIso8601String()} | $level | $message';

    // Print to console
    debugPrint('LOG: $logMessage');

    // If there's an error, log it too
    if (error != null) {
      debugPrint('ERROR: $error');
      if (stackTrace != null) {
        debugPrint(
            'STACK: ${stackTrace.toString().split('\n').take(10).join('\n')}');
      }
    }
  }
}

/// Log levels in order of increasing severity
enum LogLevel {
  debug, // Detailed debugging info
  info, // General operational info
  warning, // Potential problems, can continue
  error, // Error occurred but can recover
  severe // Critical error, may need to abort
}
