import 'dart:convert';
import '../../database/database_helper.dart';
import '../../core/services/logging.dart';

class AlbumMigrationUtility {
  /// Migrates all albums in the database from legacy format to the new format (format_version: 2).
  /// Returns the number of albums migrated.
  static Future<int> migrateAlbumFormats() async {
    final db = await DatabaseHelper.instance.database;

    // First, ensure the format_version column exists
    await _ensureFormatVersionColumn(db);

    final albums = await db.query('albums');
    int migratedCount = 0;

    for (final album in albums) {
      // Check if already migrated by looking at the data field
      bool needsMigration = true;

      if (album['data'] != null) {
        try {
          final data = jsonDecode(album['data'] as String);
          if (data is Map && data['format_version'] == 2) {
            needsMigration = false;
          }
        } catch (e) {
          // Invalid JSON, needs migration
          Logging.severe('Album ${album['id']} has invalid JSON data, migrating');
        }
      }

      if (!needsMigration) continue;

      // Convert legacy album to new format
      final newAlbum = _convertToNewFormat(album);
      if (newAlbum != null) {
        await db.update('albums', newAlbum, where: 'id = ?', whereArgs: [album['id']]);
        migratedCount++;
      }
    }

    Logging.severe('AlbumMigrationUtility: Migrated $migratedCount albums to new format');
    return migratedCount;
  }

  /// Ensures the format_version column exists in the albums table
  static Future<void> _ensureFormatVersionColumn(db) async {
    try {
      // Check if format_version column exists
      final tableInfo = await db.rawQuery("PRAGMA table_info(albums)");
      final columnNames = tableInfo.map((col) => col['name'] as String).toList();

      if (!columnNames.contains('format_version')) {
        Logging.severe('Adding format_version column to albums table');
        await db.execute('ALTER TABLE albums ADD COLUMN format_version INTEGER DEFAULT 1');
      }
    } catch (e) {
      Logging.severe('Error ensuring format_version column exists: $e');
      rethrow;
    }
  }

  /// Converts a legacy album map to the new format (format_version: 2).
  static Map<String, dynamic>? _convertToNewFormat(Map<String, dynamic> legacyAlbum) {
    try {
      final newAlbum = Map<String, dynamic>.from(legacyAlbum);

      // Parse existing data or create new data structure
      Map<String, dynamic> albumData;

      if (newAlbum['data'] != null) {
        try {
          albumData = Map<String, dynamic>.from(jsonDecode(newAlbum['data'] as String));
        } catch (e) {
          // Create new data structure if JSON is invalid
          albumData = <String, dynamic>{};
        }
      } else {
        albumData = <String, dynamic>{};
      }

      // Add format_version to the data field (this is what DebugUtil checks)
      albumData['format_version'] = 2;

      // Ensure essential fields are in the data
      albumData['id'] = newAlbum['id'];
      albumData['name'] = newAlbum['name'] ?? albumData['name'];
      albumData['artist'] = newAlbum['artist'] ?? albumData['artist'];
      albumData['platform'] = newAlbum['platform'] ?? albumData['platform'];

      // Copy other fields that might exist
      if (newAlbum['artwork_url'] != null) {
        albumData['artworkUrl'] = newAlbum['artwork_url'];
      }
      if (newAlbum['url'] != null) {
        albumData['url'] = newAlbum['url'];
      }
      if (newAlbum['release_date'] != null) {
        albumData['releaseDate'] = newAlbum['release_date'];
      }

      // Update the data field with the new format
      newAlbum['data'] = jsonEncode(albumData);

      // Set format_version in the table column as well
      newAlbum['format_version'] = 2;

      Logging.severe('Converted album ${newAlbum['id']} to new format');
      return newAlbum;
    } catch (e) {
      Logging.severe('Error converting album to new format: $e');
      return null;
    }
  }
}
