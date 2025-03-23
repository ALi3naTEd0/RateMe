import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart';

class Logging {
  static final _logger = Logger('RateMe');

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

  static void severe(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.severe(message, error, stackTrace);
  }
}
