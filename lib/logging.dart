import 'package:logging/logging.dart';

class Logging {
  static final Logger _logger = Logger('AppLogger');

  // Configura el logger
  static void setupLogging() {
    Logger.root.level = Level.ALL; // Establece el nivel de logging
    Logger.root.onRecord.listen((record) {
      final logMessage =
          '${record.level.name}: ${record.time}: ${record.message}';
      
      // Imprime directamente el mensaje en la consola
      print(logMessage);

      // Si hay un error asociado, imprime el error y el stacktrace
      if (record.error != null) {
        print(
            '$logMessage, Error: ${record.error}, StackTrace: ${record.stackTrace}');
      }
    });
  }

  // Métodos de acceso para diferentes niveles de logging
  static void info(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.info(message, error, stackTrace);
  }

  static void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.warning(message, error, stackTrace);
  }

  static void severe(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.severe(message, error, stackTrace);
  }
}
