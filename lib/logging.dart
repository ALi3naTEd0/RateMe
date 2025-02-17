import 'package:logging/logging.dart';

class Logging {
  static void setupLogging() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((LogRecord rec) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
      if (rec.error != null) {
        print('Error: ${rec.error}');
      }
      if (rec.stackTrace != null) {
        print('Stack trace:\n${rec.stackTrace}');
      }
    });
  }

  static void info(String message, [Object? error, StackTrace? stackTrace]) {
    Logger('RateMe').info(message, error, stackTrace);
  }

  static void severe(String message, [Object? error, StackTrace? stackTrace]) {
    Logger('RateMe').severe(message, error, stackTrace);
  }

  // Agregar métodos útiles
  static void warning(String message, [Object? error, StackTrace? stackTrace]) {
    Logger('RateMe').warning(message, error, stackTrace);
  }

  static void debug(String message, [Object? error, StackTrace? stackTrace]) {
    Logger('RateMe').fine(message, error, stackTrace);
  }
}
