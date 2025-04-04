import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart'; // Add this import for Sqflite
import 'album_model.dart';
import 'logging.dart';
import 'custom_lists_page.dart';
import 'database/database_helper.dart';
import 'database/migration_utility.dart';

class UserData {
  // Flag to track initialization
  static bool _initialized = false;

  // Modified initialization method to ensure database is properly set up
  static Future<void> initializeDatabase() async {
    if (_initialized) return;

    try {
      // Initialize the database factory first
      await DatabaseHelper.initialize();

      // Check if migration is needed
      if (!await MigrationUtility.isMigrationCompleted()) {
        // We don't actually do the migration here - it will be triggered from the settings page
        Logging.severe(
            'Database migration required but not performed automatically');
      }

      _initialized = true;
    } catch (e, stack) {
      Logging.severe('Error initializing database', e, stack);
    }
  }

  /// Get database instance for direct operations
  static Future<Database> getDatabaseInstance() async {
    await initializeDatabase();
    return DatabaseHelper.instance.database;
  }

  /// Check if migration is needed
  static Future<bool> isMigrationNeeded() async {
    try {
      // Check migration flag first
      final prefs = await SharedPreferences.getInstance();
      final migrationCompleted =
          prefs.getBool('sqlite_migration_completed') ?? false;

      if (migrationCompleted) {
        return false;
      }

      // Check if there's SharedPreferences data to migrate
      final savedAlbums = prefs.getStringList('saved_albums') ?? [];
      return savedAlbums.isNotEmpty;
    } catch (e) {
      Logging.severe('Error checking migration status', e);
      return false;
    }
  }

  /// Export current data to backup file - improved for migration
  static Future<String?> exportMigrationBackup() async {
    try {
      // First check if we have SharedPreferences data to migrate
      final prefs = await SharedPreferences.getInstance();
      final savedAlbums = prefs.getStringList('saved_albums') ?? [];

      if (savedAlbums.isEmpty) {
        Logging.severe('No SharedPreferences data to migrate');
        return null;
      }

      // Create a temporary backup file automatically
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupPath = '${tempDir.path}/rateme_migration_$timestamp.json';

      // Build the legacy format backup data
      final backupData = <String, dynamic>{};

      // Export all SharedPreferences keys
      for (final key in prefs.getKeys()) {
        final value = prefs.get(key);
        if (value != null) {
          // Handle different value types
          if (value is List<String>) {
            backupData[key] = value;
          } else {
            backupData[key] = value;
          }
        }
      }

      // Add metadata
      backupData['_backup_meta'] = {
        'version': 1,
        'timestamp': timestamp,
        'format': 'legacy'
      };

      // Save to the temporary file
      final file = File(backupPath);
      await file.writeAsString(jsonEncode(backupData));

      Logging.severe('Created migration backup at: $backupPath');
      return backupPath;
    } catch (e, stack) {
      Logging.severe('Error creating migration backup', e, stack);
      return null;
    }
  }

  /// Migrate from SharedPreferences to SQLite using backup approach
  static Future<bool> migrateToSQLite() async {
    try {
      // Create a backup first
      final backupPath = await exportMigrationBackup();
      if (backupPath == null) {
        Logging.severe('Failed to create migration backup');
        return false;
      }

      // Import the backup into SQLite
      final backupFile = File(backupPath);
      final jsonData = await backupFile.readAsString();
      final backupData = jsonDecode(jsonData);

      // Import using the normal import function
      final success = await _importLegacyFormatBackup(
        backupData,
        (stage, progress) {
          // We don't need to do anything with the progress in this context
          // but we need to provide the callback to match the method signature
        },
      );

      if (success) {
        // Mark migration as completed
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('sqlite_migration_completed', true);

        Logging.severe('Migration to SQLite completed successfully');
        return true;
      } else {
        Logging.severe('Migration to SQLite failed');
        return false;
      }
    } catch (e, stack) {
      Logging.severe('Error during SQLite migration', e, stack);
      return false;
    }
  }

  // ALBUM METHODS

  /// Add an album to the saved albums list
  static Future<bool> addToSavedAlbums(Map<String, dynamic> album) async {
    try {
      // Create a clean copy of the album data to avoid modifying the original
      final Map<String, dynamic> albumToSave = Map<String, dynamic>.from(album);
      Logging.severe(
          'Preparing album for saving: ${albumToSave["collectionName"] ?? albumToSave["name"]}');

      // Add saved timestamp for sorting by date added
      albumToSave['savedTimestamp'] = DateTime.now().millisecondsSinceEpoch;

      // Ensure ID is consistently stored as a string
      var albumId = albumToSave['id'] ?? albumToSave['collectionId'];
      if (albumId == null) {
        Logging.severe('Cannot save album: No ID found');
        return false;
      }

      // Make sure albumId is a string
      final albumIdStr = albumId.toString();
      albumToSave['id'] = albumIdStr;

      // Get database instance
      final db = await getDatabaseInstance();

      // First, get the table info to see what columns exist
      final List<Map<String, dynamic>> tableInfo =
          await db.rawQuery("PRAGMA table_info(albums)");
      final List<String> existingColumns =
          tableInfo.map((col) => col['name'].toString()).toList();

      Logging.severe('Album table columns: $existingColumns');

      // Create a map with only the columns that exist in the table
      final Map<String, dynamic> compatibleData = {};

      // Always include ID
      compatibleData['id'] = albumIdStr;

      // Map standard fields to their possible column names in the database
      final fieldMappings = {
        // Common mappings between our data model and database schema
        'name': ['name', 'collection_name', 'collectionName'],
        'artist': ['artist', 'artist_name', 'artistName'],
        'artwork': [
          'artwork_url',
          'artworkUrl',
          'artwork_url100',
          'artworkUrl100'
        ],
        'platform': ['platform', 'source'],
        'url': ['url', 'album_url', 'albumUrl'],
        'savedTimestamp': ['saved_timestamp', 'savedTimestamp'],
      };

      // Process each field using the mappings
      for (var field in fieldMappings.keys) {
        final possibleColumns = fieldMappings[field]!;
        final valueFields = [
          ...possibleColumns
        ]; // Fields to check in source data

        // Find a value for this type of field
        dynamic fieldValue;
        for (var valueField in valueFields) {
          if (albumToSave.containsKey(valueField) &&
              albumToSave[valueField] != null) {
            fieldValue = albumToSave[valueField];
            break;
          }
        }

        // If we found a value, add it to any matching column in the database
        if (fieldValue != null) {
          for (var column in possibleColumns) {
            if (existingColumns.contains(column)) {
              compatibleData[column] = fieldValue;
            }
          }
        }
      }

      // Handle tracks separately - if the column exists and tracks are available
      if (existingColumns.contains('tracks') &&
          albumToSave.containsKey('tracks')) {
        try {
          // Convert tracks to a simple list if needed
          if (albumToSave['tracks'] is List) {
            compatibleData['tracks'] = jsonEncode(albumToSave['tracks']);
          } else if (albumToSave['tracks'] is String) {
            // Already a string, just copy it
            compatibleData['tracks'] = albumToSave['tracks'];
          }
        } catch (e) {
          Logging.severe('Error encoding tracks: $e');
        }
      }

      // Add any raw columns that exist in both album and database schema
      // This handles columns we didn't explicitly map above
      for (var key in albumToSave.keys) {
        if (existingColumns.contains(key) && !compatibleData.containsKey(key)) {
          compatibleData[key] = albumToSave[key];
        }
      }

      // Check if album already exists
      final existingAlbums = await db.query(
        'albums',
        where: 'id = ?',
        whereArgs: [albumIdStr],
      );

      Logging.severe(
          'Saving album with compatible fields: ${compatibleData.keys.join(", ")}');

      // Insert or update the album
      try {
        if (existingAlbums.isEmpty) {
          await db.insert('albums', compatibleData);
          Logging.severe('Inserted new album: $albumIdStr');
        } else {
          await db.update(
            'albums',
            compatibleData,
            where: 'id = ?',
            whereArgs: [albumIdStr],
          );
          Logging.severe('Updated existing album: $albumIdStr');
        }
        return true;
      } catch (e, stack) {
        Logging.severe(
            'Database operation failed, attempting fallback:', e, stack);

        // Fallback: use minimal required fields
        try {
          final minimalData = {
            'id': albumIdStr,
          };

          // Add any fields that definitely exist in the database
          for (var col in existingColumns) {
            if (compatibleData.containsKey(col)) {
              minimalData[col] = compatibleData[col];
            }
          }

          if (existingAlbums.isEmpty) {
            await db.insert('albums', minimalData);
          } else {
            await db.update(
              'albums',
              minimalData,
              where: 'id = ?',
              whereArgs: [albumIdStr],
            );
          }
          Logging.severe('Album saved with minimal data: $albumIdStr');
          return true;
        } catch (e2, stack2) {
          Logging.severe('Final fallback attempt failed:', e2, stack2);
          return false;
        }
      }
    } catch (e, stack) {
      Logging.severe('Error saving album:', e, stack);
      return false;
    }
  }

  /// Save an album to the database (add or update)
  static Future<bool> saveAlbum(Map<String, dynamic> album) async {
    try {
      final albumName =
          album['name'] ?? album['collectionName'] ?? 'Unknown Album';
      Logging.severe('Preparing album for saving: $albumName');

      await initializeDatabase();
      final db = await getDatabaseInstance();

      // Check database schema to determine available columns
      final tableInfo = await db.rawQuery("PRAGMA table_info(albums)");
      Logging.severe(
          'Album table columns: ${tableInfo.map((row) => row['name']).toList()}');

      // Build insert data using only columns that exist in the schema
      Map<String, dynamic> insertData = {};

      // Required ID field (ensure it's a string)
      insertData['id'] = (album['id'] ?? album['collectionId']).toString();

      // Determine compatible fields based on schema
      final columnNames =
          tableInfo.map((col) => col['name'].toString()).toSet();
      Logging.severe(
          'Saving album with compatible fields: ${columnNames.join(', ')}');

      // Add fields that are present in both the album and the schema
      if (columnNames.contains('name')) {
        insertData['name'] =
            album['name'] ?? album['collectionName'] ?? 'Unknown Album';
      }
      if (columnNames.contains('artist')) {
        insertData['artist'] =
            album['artist'] ?? album['artistName'] ?? 'Unknown Artist';
      }
      if (columnNames.contains('artworkUrl')) {
        insertData['artworkUrl'] =
            album['artworkUrl'] ?? album['artworkUrl100'] ?? '';
      }
      if (columnNames.contains('platform')) {
        insertData['platform'] = album['platform'] ?? 'unknown';
      }
      if (columnNames.contains('url')) {
        insertData['url'] = album['url'] ?? album['collectionViewUrl'] ?? '';
      }
      if (columnNames.contains('releaseDate')) {
        if (album['releaseDate'] is String) {
          insertData['releaseDate'] = album['releaseDate'];
        } else if (album['releaseDate'] is DateTime) {
          insertData['releaseDate'] = album['releaseDate'].toIso8601String();
        }
      }
      if (columnNames.contains('data')) {
        // Convert entire album data to JSON string including tracks
        // Make sure we include tracks data for Deezer albums
        Map<String, dynamic> albumData = Map<String, dynamic>.from(album);

        // Ensure tracks are included in the saved data
        if (albumData['tracks'] != null) {
          // Keep tracks data as is
          Logging.severe(
              'Saving album with ${albumData['tracks'].length} tracks');
        }

        insertData['data'] = jsonEncode(albumData);
      }

      // Check if album already exists
      final List<Map<String, dynamic>> existingAlbums = await db.query(
        'albums',
        where: 'id = ?',
        whereArgs: [insertData['id']],
      );

      if (existingAlbums.isEmpty) {
        // Insert new album
        await db.insert('albums', insertData);
        Logging.severe('Inserted new album: ${insertData['id']}');
      } else {
        // Update existing album
        await db.update(
          'albums',
          insertData,
          where: 'id = ?',
          whereArgs: [insertData['id']],
        );
        Logging.severe('Updated existing album: ${insertData['id']}');
      }

      return true;
    } catch (e, stack) {
      Logging.severe('Error saving album', e, stack);
      return false;
    }
  }

  /// Get all saved albums
  static Future<List<Map<String, dynamic>>> getSavedAlbums() async {
    try {
      await initializeDatabase();

      // Get albums from database with full data
      final albums = await DatabaseHelper.instance.getAllAlbums();

      // Debug the returned data structure
      Logging.severe(
          'getSavedAlbums: Retrieved ${albums.length} albums from database');

      if (albums.isNotEmpty) {
        // Log the first album for debugging purposes
        final firstAlbum = albums.first;
        Logging.severe(
            'First album details: id=${firstAlbum['id']}, name=${firstAlbum['name']}, artist=${firstAlbum['artist']}');
        Logging.severe(
            'First album has artwork URL: ${firstAlbum['artworkUrl'] ?? firstAlbum['artworkUrl100'] ?? 'missing'}');
      } else {
        // Check if there's data in the database table despite the empty result
        final db = await DatabaseHelper.instance.database;
        final count = await db.rawQuery('SELECT COUNT(*) as count FROM albums');
        final albumCount = Sqflite.firstIntValue(count) ?? 0;
        Logging.severe(
            'Database has $albumCount albums in the table, but query returned empty result');

        // If there's a discrepancy, try a direct query to diagnose
        if (albumCount > 0) {
          final rawAlbums = await db.query('albums', limit: 3);
          Logging.severe(
              'Direct query sample (${rawAlbums.length} albums): ${rawAlbums.map((a) => a['name']).join(', ')}');
        }
      }

      return albums;
    } catch (e, stack) {
      Logging.severe('Error getting saved albums', e, stack);
      return [];
    }
  }

  /// Delete album and all associated data (ratings, list relationships)
  static Future<bool> deleteAlbum(Map<String, dynamic> album) async {
    try {
      final db = await getDatabaseInstance();

      // Get the album ID in a consistent format
      final albumId = album['id'] ?? album['collectionId'];
      if (albumId == null) {
        Logging.severe('Cannot delete album: No ID found');
        return false;
      }

      Logging.severe('Deleting album with ID: $albumId');

      // Use a transaction to ensure all operations succeed or fail together
      await db.transaction((txn) async {
        // Delete the album
        int deleted = await txn.delete(
          'albums',
          where: 'id = ?',
          whereArgs: [albumId],
        );

        // Delete any ratings associated with this album
        int ratingsDeleted = await txn.delete(
          'ratings',
          where: 'album_id = ?',
          whereArgs: [albumId],
        );

        // Delete list relationships
        int relationshipsDeleted = await txn.delete(
          'album_lists',
          where: 'album_id = ?',
          whereArgs: [albumId],
        );

        // Remove from album order
        await txn.delete(
          'album_order',
          where: 'album_id = ?',
          whereArgs: [albumId],
        );

        Logging.severe(
            'Deleted: $deleted album, $ratingsDeleted ratings, $relationshipsDeleted list relationships');
      });

      return true;
    } catch (e, stack) {
      Logging.severe('Error deleting album', e, stack);
      return false;
    }
  }

  /// Check if album exists in database
  static Future<bool> albumExists(String albumId) async {
    try {
      await initializeDatabase();

      final album = await DatabaseHelper.instance.getAlbum(albumId);
      return album != null;
    } catch (e) {
      Logging.severe('Error checking if album exists: $e');
      return false;
    }
  }

  /// Get album by any ID (handles both string and int IDs)
  static Future<Album?> getAlbumByAnyId(String albumId) async {
    try {
      await initializeDatabase();

      Logging.severe('Getting album by ID: $albumId (${albumId.runtimeType})');

      final album = await DatabaseHelper.instance.getAlbum(albumId);

      if (album != null) {
        Logging.severe(
            'Found album: ${album.name} with artwork URL: ${album.artworkUrl}');
      } else {
        Logging.severe('Album not found for ID: $albumId');
      }

      return album;
    } catch (e, stack) {
      Logging.severe('Error getting album by ID: $albumId', e, stack);
      return null;
    }
  }

  // RATINGS METHODS

  /// Save a track rating
  static Future<bool> saveRating(
      dynamic albumId, dynamic trackId, double rating) async {
    try {
      Logging.severe(
          'Saving rating for album: $albumId, track: $trackId, rating: $rating');

      await initializeDatabase();
      final db = await getDatabaseInstance();

      // Check the schema of the ratings table
      final tableInfo = await db.rawQuery("PRAGMA table_info(ratings)");
      final columnNames =
          tableInfo.map((col) => col['name'].toString()).toSet();

      Logging.severe('Ratings table columns: $columnNames');

      // Check which columns exist
      final hasUpdatedAt = columnNames.contains('updated_at');
      final hasTimestamp = columnNames.contains('timestamp');

      // Create a base rating data map with required fields
      Map<String, Object?> ratingData = {
        'album_id': albumId.toString(),
        'track_id': trackId.toString(),
        'rating': rating,
      };

      // Add required timestamp fields based on schema
      if (hasUpdatedAt) {
        ratingData['updated_at'] = DateTime.now().millisecondsSinceEpoch;
      }

      if (hasTimestamp) {
        // Add timestamp in ISO 8601 format as it might be expected in this format
        ratingData['timestamp'] = DateTime.now().toIso8601String();
      }

      Logging.severe(
          'Saving rating with fields: ${ratingData.keys.join(', ')}');

      // Check if rating already exists
      final existing = await db.query(
        'ratings',
        where: 'album_id = ? AND track_id = ?',
        whereArgs: [albumId.toString(), trackId.toString()],
      );

      try {
        if (existing.isEmpty) {
          // Insert new rating
          await db.insert('ratings', ratingData);
          Logging.severe('Inserted new rating successfully');
        } else {
          // Update existing rating
          await db.update(
            'ratings',
            ratingData,
            where: 'album_id = ? AND track_id = ?',
            whereArgs: [albumId.toString(), trackId.toString()],
          );
          Logging.severe('Updated existing rating successfully');
        }

        return true;
      } catch (e, stack) {
        Logging.severe(
            'Error with main rating operation, trying fallback', e, stack);

        // If the operation failed, try a more robust approach with explicit timestamp
        try {
          // Add timestamp if it doesn't exist already (likely the cause of the error)
          if (!ratingData.containsKey('timestamp')) {
            ratingData['timestamp'] = DateTime.now().toIso8601String();
          }

          if (existing.isEmpty) {
            await db.insert('ratings', ratingData);
          } else {
            await db.update(
              'ratings',
              ratingData,
              where: 'album_id = ? AND track_id = ?',
              whereArgs: [albumId.toString(), trackId.toString()],
            );
          }
          Logging.severe('Fallback rating operation succeeded');
          return true;
        } catch (e2, stack2) {
          // If even the fallback fails, try direct SQL as last resort
          Logging.severe('Fallback failed, trying direct SQL', e2, stack2);

          try {
            final timestamp = DateTime.now().toIso8601String();
            if (existing.isEmpty) {
              await db.rawInsert(
                  'INSERT INTO ratings (album_id, track_id, rating, timestamp) VALUES (?, ?, ?, ?)',
                  [albumId.toString(), trackId.toString(), rating, timestamp]);
            } else {
              await db.rawUpdate(
                  'UPDATE ratings SET rating = ?, timestamp = ? WHERE album_id = ? AND track_id = ?',
                  [rating, timestamp, albumId.toString(), trackId.toString()]);
            }
            Logging.severe('Direct SQL rating operation succeeded');
            return true;
          } catch (e3, stack3) {
            Logging.severe('All rating operations failed', e3, stack3);
            return false;
          }
        }
      }
    } catch (e, stack) {
      Logging.severe('Error saving rating', e, stack);
      return false;
    }
  }

  /// Get all ratings for an album
  static Future<List<Map<String, dynamic>>> getSavedAlbumRatings(
      dynamic albumId) async {
    try {
      await initializeDatabase();
      final albumIdStr = albumId.toString();
      final ratings =
          await DatabaseHelper.instance.getRatingsForAlbum(albumIdStr);

      // Convert to compatible format for existing code
      return ratings
          .map((r) => {
                'trackId': r['track_id'],
                'rating': r['rating'],
                // The timestamp field is missing from the output but might be needed
                'timestamp': r['timestamp'] ?? DateTime.now().toIso8601String(),
              })
          .toList();
    } catch (e, stack) {
      Logging.severe('Error getting album ratings', e, stack);
      return [];
    }
  }

  // ALBUM ORDER METHODS

  /// Save album order
  static Future<bool> saveAlbumOrder(List<String> albumIds) async {
    try {
      await initializeDatabase();
      await DatabaseHelper.instance.saveAlbumOrder(albumIds);
      Logging.severe('Album order saved: ${albumIds.length} albums');
      return true;
    } catch (e, stack) {
      Logging.severe('Error saving album order', e, stack);
      return false;
    }
  }

  /// Get album order
  static Future<List<String>> getAlbumOrder() async {
    try {
      await initializeDatabase();
      return await DatabaseHelper.instance.getAlbumOrder();
    } catch (e, stack) {
      Logging.severe('Error getting album order', e, stack);
      return [];
    }
  }

  // CUSTOM LISTS METHODS

  /// Save a custom list
  static Future<bool> saveCustomList(CustomList list) async {
    try {
      // Make sure IDs are cleaned before saving
      list.cleanupAlbumIds();

      Logging.severe(
          'Saving custom list: ${list.name} with ${list.albumIds.length} albums');

      final db = await getDatabaseInstance();

      // First save the list info
      final Map<String, dynamic> listData = {
        'id': list.id,
        'name': list.name,
        'description': list.description,
        'created_at': list.createdAt.toIso8601String(),
        'updated_at': list.updatedAt.toIso8601String(),
      };

      // Begin transaction
      await db.transaction((txn) async {
        // Check if list exists
        final existing = await txn
            .query('custom_lists', where: 'id = ?', whereArgs: [list.id]);
        if (existing.isEmpty) {
          await txn.insert('custom_lists', listData);
          Logging.severe('Created new list: ${list.name}');
        } else {
          await txn.update(
            'custom_lists',
            listData,
            where: 'id = ?',
            whereArgs: [list.id],
          );
          Logging.severe('Updated existing list: ${list.name}');
        }

        // Delete old album associations
        await txn.delete(
          'album_lists',
          where: 'list_id = ?',
          whereArgs: [list.id],
        );

        // Add new album associations
        for (int i = 0; i < list.albumIds.length; i++) {
          final albumId = list.albumIds[i];
          // Skip empty IDs
          if (albumId.isEmpty) continue;
          Logging.severe('Adding album ID: $albumId to list ${list.name}');

          await txn.insert(
            'album_lists',
            {
              'list_id': list.id,
              'album_id': albumId,
              'position': i,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      return true;
    } catch (e, stack) {
      Logging.severe('Error saving custom list', e, stack);
      return false;
    }
  }

  /// Get all custom lists
  static Future<List<CustomList>> getCustomLists() async {
    try {
      await initializeDatabase();
      // Get lists from database
      final lists = await DatabaseHelper.instance.getAllCustomLists();
      final result = <CustomList>[];

      for (final list in lists) {
        try {
          // Get album IDs for this list
          final albumIds =
              await DatabaseHelper.instance.getAlbumIdsForList(list['id']);

          // Create CustomList object
          result.add(CustomList(
            id: list['id'],
            name: list['name'],
            description: list['description'] ?? '',
            albumIds: albumIds,
            createdAt: DateTime.parse(list['created_at']),
            updatedAt: DateTime.parse(list['updated_at']),
          ));
        } catch (e) {
          Logging.severe('Error loading custom list: $e');
        }
      }

      return result;
    } catch (e, stack) {
      Logging.severe('Error getting custom lists', e, stack);
      return [];
    }
  }

  /// Delete a custom list
  static Future<bool> deleteCustomList(String listId) async {
    try {
      await initializeDatabase();

      await DatabaseHelper.instance.deleteCustomList(listId);
      Logging.severe('Custom list deleted: $listId');
      return true;
    } catch (e, stack) {
      Logging.severe('Error deleting custom list', e, stack);
      return false;
    }
  }

  // SETTINGS METHODS

  /// Save a setting
  static Future<bool> saveSetting(String key, String value) async {
    try {
      await initializeDatabase();

      await DatabaseHelper.instance.saveSetting(key, value);

      Logging.severe('Setting saved: $key = $value');
      return true;
    } catch (e) {
      Logging.severe('Error saving setting: $e');
      return false;
    }
  }

  /// Get a setting
  static Future<String?> getSetting(String key) async {
    try {
      await initializeDatabase();

      return await DatabaseHelper.instance.getSetting(key);
    } catch (e) {
      Logging.severe('Error getting setting: $e');
      return null;
    }
  }

  // Import/Export methods can remain largely the same but need adapting to the new database structure

  /// Import album from JSON file
  static Future<Map<String, dynamic>?> importAlbum() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Import Album',
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final file = File(result.files.first.path!);
      final jsonData = await file.readAsString();
      final albumData = jsonDecode(jsonData);
      // Save to database
      await addToSavedAlbums(albumData);

      return albumData;
    } catch (e) {
      Logging.severe('Error importing album: $e');
      return null;
    }
  }

  /// Export album to JSON file
  static Future<bool> exportAlbum(Map<String, dynamic> albumData) async {
    try {
      final jsonData = jsonEncode(albumData);
      final albumName =
          albumData['name'] ?? albumData['collectionName'] ?? 'Unknown';
      final safeAlbumName = albumName.replaceAll(RegExp(r'[^\w\s-]'), '_');

      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Album',
        fileName: '$safeAlbumName.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputPath == null) {
        return false;
      }

      final file = File(outputPath);
      await file.writeAsString(jsonData);

      return true;
    } catch (e) {
      Logging.severe('Error exporting album: $e');
      return false;
    }
  }

  /// Export all data to backup file
  static Future<bool> exportData() async {
    try {
      await initializeDatabase();

      // Create backup data structure
      final backupData = <String, dynamic>{};

      // 1. Export albums
      final albums = await DatabaseHelper.instance.getAllAlbums();
      backupData['albums'] = albums;

      // 2. Export ratings
      final db = await DatabaseHelper.instance.database;
      final ratings = await db.query('ratings');
      backupData['ratings'] = ratings;

      // 3. Export custom lists
      final lists = await db.query('custom_lists');
      backupData['custom_lists'] = lists;

      // 4. Export album-list relationships
      final albumLists = await db.query('album_lists');
      backupData['album_lists'] = albumLists;

      // 5. Export album order
      final albumOrder = await db.query('album_order', orderBy: 'position ASC');
      backupData['album_order'] = albumOrder;

      // 6. Export settings
      final settings = await db.query('settings');
      backupData['settings'] = settings;

      // Add metadata
      backupData['_backup_meta'] = {
        'version': 2, // SQLite backup version
        'timestamp': DateTime.now().toIso8601String(),
        'format': 'sqlite'
      };

      // Save to file
      final jsonData = jsonEncode(backupData);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');

      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export All Data',
        fileName: 'rateme_backup_$timestamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputPath == null) {
        return false;
      }

      final file = File(outputPath);
      await file.writeAsString(jsonData);

      return true;
    } catch (e, stack) {
      Logging.severe('Error exporting data', e, stack);
      return false;
    }
  }

  /// Import data from backup file
  static Future<bool> importData(
      {String? fromFile,
      bool skipFilePicker = false,
      Function(String stage, double progress)? progressCallback}) async {
    try {
      String jsonData;

      if (skipFilePicker && fromFile != null) {
        // Use the provided file path directly
        final file = File(fromFile);
        jsonData = await file.readAsString();
        Logging.severe('Importing directly from file: $fromFile');
      } else {
        // Use file picker as usual
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
          dialogTitle: 'Import Data',
        );

        if (result == null || result.files.isEmpty) {
          return false;
        }

        final file = File(result.files.first.path!);
        jsonData = await file.readAsString();
        // Update progress
        progressCallback?.call('Analyzing backup file...', 0.1);
      }

      final backupData = jsonDecode(jsonData);

      // Record start time for performance metrics
      final startTime = DateTime.now();

      // Check backup format
      final meta = backupData['_backup_meta'];
      final format = meta?['format'] ?? 'legacy';

      // Update progress
      progressCallback?.call('Preparing database...', 0.2);

      bool importSuccess = false;
      if (format == 'sqlite') {
        // SQLite format backup
        progressCallback?.call('Importing SQLite format backup...', 0.3);
        await _importSQLiteFormatBackup(backupData, (stage, progress) {
          // Map the progress to the range 0.3-0.9
          final scaledProgress = 0.3 + (progress * 0.6);
          progressCallback?.call(stage, scaledProgress);
        });
        importSuccess = true;
      } else {
        // Legacy format backup - convert via migration
        progressCallback?.call('Importing legacy format backup...', 0.3);
        importSuccess =
            await _importLegacyFormatBackup(backupData, (stage, progress) {
          // Map the progress to the range 0.3-0.9
          final scaledProgress = 0.3 + (progress * 0.6);
          progressCallback?.call(stage, scaledProgress);
        });
      }

      // Final progress update
      progressCallback?.call('Finalizing import...', 0.95);

      // Record performance metrics
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      Logging.severe('Import completed in ${duration.inMilliseconds}ms');

      // Complete progress
      progressCallback?.call('Import complete!', 1.0);

      return importSuccess;
    } catch (e, stack) {
      Logging.severe('Error importing data', e, stack);
      return false;
    }
  }

  /// Import backup in SQLite format
  static Future<void> _importSQLiteFormatBackup(Map<String, dynamic> data,
      Function(String stage, double progress)? progressCallback) async {
    final db = await DatabaseHelper.instance.database;

    // Track imported item counts
    int albumCount = 0;
    int ratingCount = 0;
    int listCount = 0;
    int albumListCount = 0;
    int settingsCount = 0;

    // Count total items for progress tracking
    final totalItems = (data['albums']?.length ?? 0) +
        (data['ratings']?.length ?? 0) +
        (data['custom_lists']?.length ?? 0) +
        (data['album_lists']?.length ?? 0) +
        (data['album_order']?.length ?? 0) +
        (data['settings']?.length ?? 0);

    int processedItems = 0;

    // Start transaction
    await db.transaction((txn) async {
      // Import albums
      if (data['albums'] != null) {
        progressCallback?.call(
            'Importing albums...', processedItems / totalItems);
        for (final album in data['albums']) {
          await txn.insert('albums', album);
          albumCount++;
          processedItems++;
          // Update progress every 5 items to avoid too many updates
          if (albumCount % 5 == 0) {
            progressCallback?.call(
                'Importing albums...', processedItems / totalItems);
          }
        }
      }

      // Import ratings
      if (data['ratings'] != null) {
        progressCallback?.call(
            'Importing ratings...', processedItems / totalItems);
        for (final rating in data['ratings']) {
          await txn.insert('ratings', rating);
          ratingCount++;
          processedItems++;
          // Update progress every 20 items
          if (ratingCount % 20 == 0) {
            progressCallback?.call(
                'Importing ratings...', processedItems / totalItems);
          }
        }
      }

      // Import custom lists
      if (data['custom_lists'] != null) {
        progressCallback?.call(
            'Importing lists...', processedItems / totalItems);
        for (final list in data['custom_lists']) {
          await txn.insert('custom_lists', list);
          listCount++;
          processedItems++;
        }
      }

      // Import album-list relationships
      if (data['album_lists'] != null) {
        progressCallback?.call('Importing album-list relationships...',
            processedItems / totalItems);
        for (final albumList in data['album_lists']) {
          await txn.insert('album_lists', albumList);
          albumListCount++;
          processedItems++;
          // Update progress every 10 items
          if (albumListCount % 10 == 0) {
            progressCallback?.call('Importing album-list relationships...',
                processedItems / totalItems);
          }
        }
      }

      // Import album order
      if (data['album_order'] != null) {
        progressCallback?.call(
            'Importing album order...', processedItems / totalItems);
        for (final order in data['album_order']) {
          await txn.insert('album_order', order);
          processedItems++;
        }
      }

      // Import settings
      if (data['settings'] != null) {
        progressCallback?.call(
            'Importing settings...', processedItems / totalItems);
        for (final setting in data['settings']) {
          await txn.insert('settings', setting);
          settingsCount++;
          processedItems++;
        }
      }
    });

    progressCallback?.call('Verifying imported data...', 0.95);

    Logging.severe('SQLite format backup imported successfully:');
    Logging.severe('- Albums: $albumCount');
    Logging.severe('- Ratings: $ratingCount');
    Logging.severe('- Lists: $listCount');
    Logging.severe('- Album-List relationships: $albumListCount');
    Logging.severe('- Settings: $settingsCount');
  }

  /// Import backup in legacy format (SharedPreferences)
  static Future<bool> _importLegacyFormatBackup(Map<String, dynamic> data,
      Function(String stage, double progress)? progressCallback) async {
    try {
      // First import to SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      progressCallback?.call('Clearing existing data...', 0.1);

      // Clear existing SharedPreferences data
      await prefs.clear();

      progressCallback?.call('Importing data to SharedPreferences...', 0.2);

      // Import all keys from backup
      int processedCount = 0;
      final totalKeys = data.keys.length;

      for (final entry in data.entries) {
        final key = entry.key;
        final value = entry.value;

        if (key == '_backup_meta') continue; // Skip metadata

        if (value is String) {
          await prefs.setString(key, value);
        } else if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else if (value is List) {
          if (value.every((item) => item is String)) {
            await prefs.setStringList(key, List<String>.from(value));
          }
        }

        processedCount++;
        // Update progress periodically
        if (processedCount % 5 == 0 || processedCount == totalKeys) {
          progressCallback?.call('Importing data to SharedPreferences...',
              0.2 + (0.3 * processedCount / totalKeys));
        }
      }

      // Verify SharedPreferences data was imported
      final savedAlbums = prefs.getStringList('saved_albums') ?? [];
      Logging.severe(
          'Imported ${savedAlbums.length} albums to SharedPreferences');

      progressCallback?.call('Preparing migration to SQLite...', 0.5);

      // IMPORTANT: Make sure we reset migration status before running migration
      await MigrationUtility.resetMigrationStatus();

      progressCallback?.call('Migrating data to SQLite...', 0.6);

      // Then run migration to SQLite
      final success = await MigrationUtility.migrateToSQLite(
          progressCallback: (stage, progress) {
        // Map the migration progress to 0.6-0.9 range
        final scaledProgress = 0.6 + (progress * 0.3);
        progressCallback?.call('Migrating: $stage', scaledProgress);
      });

      if (success) {
        progressCallback?.call('Migration completed successfully', 0.95);
        Logging.severe('Legacy format backup imported and migrated to SQLite');
        return true;
      } else {
        progressCallback?.call('Migration failed', 0.9);
        Logging.severe('Failed to migrate imported data to SQLite');
        return false;
      }
    } catch (e, stack) {
      Logging.severe('Error importing legacy format backup', e, stack);
      return false;
    }
  }

  /// Vacuum the database to optimize storage and performance
  static Future<bool> vacuumDatabase() async {
    try {
      await initializeDatabase();
      return await DatabaseHelper.instance.vacuumDatabase();
    } catch (e, stack) {
      Logging.severe('Error vacuuming database', e, stack);
      return false;
    }
  }

  /// Get the database size in bytes
  static Future<int> getDatabaseSize() async {
    try {
      await initializeDatabase();
      return await DatabaseHelper.instance.getDatabaseSize();
    } catch (e) {
      Logging.severe('Error getting database size', e);
      return 0;
    }
  }

  /// Check database integrity
  static Future<bool> checkDatabaseIntegrity() async {
    try {
      await initializeDatabase();
      return await DatabaseHelper.instance.checkDatabaseIntegrity();
    } catch (e) {
      Logging.severe('Error checking database integrity', e);
      return false;
    }
  }
}
