import 'dart:io';
import 'database/database_helper.dart';
import 'logging.dart';
import 'theme_service.dart' as ts;
import 'color_utility.dart';
import 'package:flutter/material.dart';

/// Utility class to force reset theme color to default purple
/// Use this as an emergency fix if colors are still not being stored correctly
class ColorResetUtility {
  /// Forces the primary color back to default purple
  static Future<bool> resetColorToDefault() async {
    try {
      final db = DatabaseHelper.instance;

      // Get the default purple color
      final Color defaultColor = getDefaultPurple();

      // Convert to hex string
      final hexString = ColorUtility.colorToHexString(defaultColor);

      // Update database directly
      await db.saveSetting('primaryColor', hexString);

      // Update ThemeService color
      await ts.ThemeService.updatePrimaryColorFromImport(hexString);

      Logging.severe(
          'COLOR RESET: Successfully reset color to default purple ($hexString)');
      return true;
    } catch (e, stack) {
      Logging.severe('Error resetting colors to default', e, stack);
      return false;
    }
  }

  static Color getDefaultPurple() {
    // Use ColorUtility.defaultColor instead of exactPurple
    return ColorUtility.defaultColor;
  }

  static Future<void> resetToDefaultPurple() async {
    try {
      // Reset the color in database and ThemeService
      final success = await resetColorToDefault();

      if (success) {
        Logging.severe('COLOR RESET: Successfully reset to default purple');
      } else {
        Logging.severe('COLOR RESET: Failed to reset to default purple');
      }
    } catch (e) {
      Logging.severe('COLOR RESET: Error resetting to default purple', e);
    }
  }

  /// Command-line utility to reset color
  static Future<void> runFromCommandLine() async {
    try {
      Logging.severe('COLOR RESET: Running from command line');

      // Initialize database
      await DatabaseHelper.initialize();

      // Reset color
      final success = await resetColorToDefault();

      Logging.severe(
          'COLOR RESET: Command line execution ${success ? 'successful' : 'failed'}');

      exit(success ? 0 : 1);
    } catch (e) {
      Logging.severe('COLOR RESET: Command line execution error', e);
      exit(1);
    }
  }
}
