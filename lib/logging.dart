import 'package:logging/logging.dart';

class Logging {
  static void setupLogging() {
    // Only log errors in production
    Logger.root.level = Level.SEVERE;
    Logger.root.onRecord.listen((record) {
      if (record.level >= Level.SEVERE) {
        print('${record.level.name}: ${record.time}: ${record.message}');
      }
    });
  }

  static void severe(String message, [dynamic error, StackTrace? stackTrace]) {
    // Only log actual errors, not debug info
    if (error != null) {
      Logger.root.severe(message, error, stackTrace);
    }
  }
}
