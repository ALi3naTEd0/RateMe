import 'package:logging/logging.dart';

class Logging {
  static void setupLogging() {
    Logger.root.level = Level.SEVERE;
    Logger.root.onRecord.listen((LogRecord rec) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
      if (rec.error != null) print('Error: ${rec.error}');
      if (rec.stackTrace != null) print('Stack trace:\n${rec.stackTrace}');
    });
  }

  static void severe(String message, [Object? error, StackTrace? stackTrace]) {
    Logger('RateMe').severe(message, error, stackTrace);
  }
}
