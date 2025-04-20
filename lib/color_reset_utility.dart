import 'dart:io';
import 'database/database_helper.dart';
import 'logging.dart';
import 'theme_service.dart' as ts;
import 'color_utility.dart';

/// Utility class to force reset theme color to default purple
/// Use this as an emergency fix if colors are still not being stored correctly
class ColorResetUtility {
  /// Forces the primary color back to default purple
  static Future<bool> resetColorToDefault() async {
    try {
      Logging.severe('COLOR RESET: Emergency reset to default purple');

      // CRITICAL FIX: Use exactPurple to avoid floating point issues
      final exactPurple = ColorUtility.exactPurple;

      // Log RGB values with integer precision
      final r = exactPurple.r.round();
      final g = exactPurple.g.round();
      final b = exactPurple.b.round();

      Logging.severe('COLOR RESET: Using exact RGB values: R=$r, G=$g, B=$b');

      // Use the fixed hex string constant
      const String purpleHex = '#FF864AF9';

      Logging.severe('COLOR RESET: Writing hex value $purpleHex to database');

      // CRITICAL FIX: Use direct SQL statements for maximum reliability
      final db = await DatabaseHelper.instance.database;

      // Delete any existing primary color setting directly
      await db.execute("DELETE FROM settings WHERE key = 'primaryColor'");

      // Insert the correct value with a direct SQL statement
      await db.execute(
          "INSERT INTO settings (key, value) VALUES ('primaryColor', '$purpleHex')");

      // Verify the write was successful
      final List<Map<String, dynamic>> result = await db
          .rawQuery("SELECT value FROM settings WHERE key = 'primaryColor'");

      final String? verifiedColor =
          result.isNotEmpty ? result.first['value'] as String? : null;

      Logging.severe('COLOR RESET: Database verification: $verifiedColor');

      // Force ThemeService to use our exact purple with integer RGB values
      ts.ThemeService.setPrimaryColorDirectly(exactPurple);

      // Force reload settings from DB
      await ts.ThemeService.loadThemeSettings();

      Logging.severe('COLOR RESET: Color has been reset to default purple');

      return true;
    } catch (e, stack) {
      Logging.severe('COLOR RESET: Failed to reset color', e, stack);
      return false;
    }
  }

  /// Command-line utility to reset color
  static Future<void> runFromCommandLine() async {
    try {
      Logging.severe('Running color reset utility from command line...');
      final success = await resetColorToDefault();
      Logging.severe('Color reset ${success ? "succeeded" : "failed"}');
      exit(success ? 0 : 1);
    } catch (e) {
      Logging.severe('Error in command-line execution: $e');
      exit(1);
    }
  }
}
