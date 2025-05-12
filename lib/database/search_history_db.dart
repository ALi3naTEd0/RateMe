import 'package:rateme/core/services/logging.dart';
import '../database/database_helper.dart';

/// Helper class to manage search history in SQLite
class SearchHistoryDb {
  /// Save a search query to database
  static Future<void> saveQuery(String query, String platform) async {
    try {
      final db = await DatabaseHelper.instance.database;

      await db.insert(
        'search_history',
        {
          'query': query,
          'platform': platform,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      // Log success
      Logging.severe('Search query saved to database: $query ($platform)');
    } catch (e) {
      // Log error
      Logging.severe('Error saving search query to database: $e');
    }
  }

  /// Get recent search history
  static Future<List<Map<String, dynamic>>> getSearchHistory(
      {int limit = 20}) async {
    try {
      final db = await DatabaseHelper.instance.database;

      return await db.query(
        'search_history',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } catch (e) {
      Logging.severe('Error getting search history: $e');
      return [];
    }
  }

  /// Clear search history
  static Future<void> clearSearchHistory() async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('search_history');
      Logging.severe('Search history cleared');
    } catch (e) {
      Logging.severe('Error clearing search history: $e');
    }
  }
}
