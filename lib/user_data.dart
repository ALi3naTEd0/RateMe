import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:rateme/search_service.dart';
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
      final db = DatabaseHelper.instance;
      final migrationCompleted =
          (await db.getSetting('sqlite_migration_completed')) == 'true';

      if (migrationCompleted) {
        return false;
      }

      // Check if there's SharedPreferences data to migrate
      final savedAlbums =
          (await db.getSetting('saved_albums'))?.split(',') ?? [];
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
      final db = DatabaseHelper.instance;
      final savedAlbums =
          (await db.getSetting('saved_albums'))?.split(',') ?? [];

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
      final settings = await db.getAllSettings();
      for (final setting in settings) {
        final key = setting['key'];
        final value = setting['value'];
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
        final db = DatabaseHelper.instance;
        await db.saveSetting('sqlite_migration_completed', 'true');

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
      Logging.severe(
          'Preparing album for saving: ${album['name'] ?? album['collectionName']}');

      // Get database instance
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;

      // Get table info to ensure we only insert compatible fields
      final tableInfo = await db.rawQuery("PRAGMA table_info(albums)");
      final columnNames =
          tableInfo.map((col) => col['name'] as String).toList();
      Logging.severe('Album table columns: $columnNames');

      // Create a compatible album entry
      final albumEntry = <String, dynamic>{};

      // Handle ID field correctly
      final id = album['id'] ?? album['collectionId'];
      if (id != null) {
        albumEntry['id'] = id.toString();
      }

      // Map common fields
      final compatibleFields = [
        'name',
        'artist',
        'artwork_url',
        'artworkUrl100',
        'platform',
        'release_date',
        'url',
        'data'
      ];

      for (final field in compatibleFields) {
        if (album.containsKey(field) && columnNames.contains(field)) {
          albumEntry[field] = album[field];
        }
      }

      // Special case for release date - ensure it's properly stored in database format
      if (columnNames.contains('release_date')) {
        // Try both camelCase and snake_case versions
        final releaseDate = album['releaseDate'] ?? album['release_date'];

        if (releaseDate != null) {
          String formattedDate;

          // Handle different input formats
          if (releaseDate is DateTime) {
            formattedDate = releaseDate.toIso8601String();
          } else if (releaseDate is String) {
            try {
              // Try to parse and normalize
              final date = DateTime.parse(releaseDate);
              formattedDate = date.toIso8601String();
            } catch (e) {
              // Use as-is if parsing fails
              formattedDate = releaseDate;
            }
          } else {
            // Default for other types
            formattedDate = releaseDate.toString();
          }

          // Store the date in database
          albumEntry['release_date'] = formattedDate;
          Logging.severe('Stored release_date in database as: $formattedDate');
        } else {
          Logging.severe('No release date found to save in database');
        }
      }

      // Special case for artwork - try multiple fields
      if (album.containsKey('artworkUrl100') &&
          columnNames.contains('artwork_url')) {
        albumEntry['artwork_url'] = album['artworkUrl100'];
      } else if (album.containsKey('artworkUrl') &&
          columnNames.contains('artwork_url')) {
        albumEntry['artwork_url'] = album['artworkUrl'];
      }

      // Map artist name fields
      if (album.containsKey('artistName') && columnNames.contains('artist')) {
        albumEntry['artist'] = album['artistName'];
      }

      // Map collection name fields
      if (album.containsKey('collectionName') && columnNames.contains('name')) {
        albumEntry['name'] = album['collectionName'];
      }

      // CRITICAL FIX: Check for tracks and save them to the database
      List<Map<String, dynamic>>? tracks;

      // Try to extract tracks from various locations
      if (album.containsKey('tracks') && album['tracks'] is List) {
        tracks = List<Map<String, dynamic>>.from(album['tracks']);
        Logging.severe('Found ${tracks.length} tracks in album data');
      } else if (album.containsKey('data')) {
        // Try to extract tracks from the data field
        if (album['data'] is String) {
          try {
            final dataMap = jsonDecode(album['data']);
            if (dataMap != null &&
                dataMap.containsKey('tracks') &&
                dataMap['tracks'] is List) {
              tracks = List<Map<String, dynamic>>.from(dataMap['tracks']);
              Logging.severe(
                  'Found ${tracks.length} tracks in album data field');
            }
          } catch (e) {
            Logging.severe('Error extracting tracks from data field: $e');
          }
        } else if (album['data'] is Map &&
            album['data'].containsKey('tracks')) {
          tracks = List<Map<String, dynamic>>.from(album['data']['tracks']);
          Logging.severe('Found ${tracks.length} tracks in album data map');
        }
      }

      // Make sure the album ID is ready for database
      albumEntry['id'] = albumEntry['id'].toString();

      // IMPORTANT: Always save a complete data field to ensure all metadata is preserved
      if (columnNames.contains('data')) {
        // Create a deep copy of the album to modify
        Map<String, dynamic> dataToStore = Map<String, dynamic>.from(album);

        // Make sure release date is included in data field
        if (!dataToStore.containsKey('releaseDate') &&
            albumEntry.containsKey('release_date')) {
          dataToStore['releaseDate'] = albumEntry['release_date'];
          Logging.severe(
              'Added missing releaseDate to data field: ${albumEntry['release_date']}');
        }

        albumEntry['data'] = jsonEncode(dataToStore);
      }

      Logging.severe(
          'Saving album with compatible fields: ${albumEntry.keys.join(", ")}');

      // Check if album already exists
      final existingAlbum = await db.query(
        'albums',
        where: 'id = ?',
        whereArgs: [albumEntry['id']],
      );

      if (existingAlbum.isNotEmpty) {
        // Update existing album
        await db.update(
          'albums',
          albumEntry,
          where: 'id = ?',
          whereArgs: [albumEntry['id']],
        );
        Logging.severe('Updated existing album: ${albumEntry['id']}');
      } else {
        // Insert new album
        await db.insert('albums', albumEntry);
        Logging.severe('Inserted new album: ${albumEntry['id']}');
      }

      // CRITICAL FIX: If we have tracks, save them to the tracks table
      if (tracks != null && tracks.isNotEmpty) {
        await dbHelper.insertTracks(albumEntry['id'].toString(), tracks);
        Logging.severe(
            'Saved ${tracks.length} tracks for album ${albumEntry['id']}');
      }

      return true;
    } catch (e, stack) {
      Logging.severe('Error saving album', e, stack);
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

      // Improved release date handling - normalize format before storage
      if (columnNames.contains('releaseDate') ||
          columnNames.contains('release_date')) {
        String? formattedDate;
        final releaseDate = album['releaseDate'];

        if (releaseDate != null) {
          if (releaseDate is DateTime) {
            formattedDate = releaseDate.toIso8601String();
          } else if (releaseDate is String) {
            // Ensure it's a valid date string
            try {
              final date = DateTime.parse(releaseDate);
              formattedDate = date.toIso8601String();
            } catch (e) {
              Logging.severe('Error formatting release date: $e');
            }
          }
        }

        // Use the appropriate column name based on schema
        if (formattedDate != null) {
          if (columnNames.contains('releaseDate')) {
            insertData['releaseDate'] = formattedDate;
          }
          if (columnNames.contains('release_date')) {
            insertData['release_date'] = formattedDate;
          }
        }
      }

      if (columnNames.contains('data')) {
        // Convert entire album data to JSON string including tracks
        // Make sure we include tracks data for Deezer albums
        Map<String, dynamic> albumData = Map<String, dynamic>.from(album);

        // Special handling for Deezer albums to ensure release date is preserved
        if (albumData['platform']?.toString().toLowerCase() == 'deezer' &&
            albumData['releaseDate'] != null) {
          Logging.severe(
              'Ensuring Deezer releaseDate is preserved in data field: ${albumData['releaseDate']}');
        }

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
        int orderDeleted = await txn.delete(
          'album_order',
          where: 'album_id = ?',
          whereArgs: [albumId],
        );

        Logging.severe(
            'Deleted: $deleted album, $ratingsDeleted ratings, $relationshipsDeleted list relationships, $orderDeleted album order entries');
      });

      // Verify the album was actually deleted by checking if it still exists
      final verifyResult = await db.query(
        'albums',
        where: 'id = ?',
        whereArgs: [albumId],
      );

      if (verifyResult.isNotEmpty) {
        Logging.severe('ERROR: Album still exists after deletion attempt!');
        return false;
      }

      Logging.severe(
          'Verification successful: Album $albumId was removed from database');
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

  // Get tracks for an album
  static Future<List<Map<String, dynamic>>> getTracksForAlbum(
      String albumId) async {
    try {
      final db = await getDatabaseInstance();

      // Query the tracks table using the album ID
      List<Map<String, dynamic>> trackMaps = await db.query(
        'tracks',
        where: 'album_id = ?',
        whereArgs: [albumId],
        orderBy: 'position ASC',
      );

      Logging.severe(
          'Retrieved ${trackMaps.length} tracks from database for album $albumId');

      if (trackMaps.isNotEmpty) {
        return trackMaps;
      }

      // If no tracks in database, see if we have stored track data in the album's 'data' field
      final albumResult = await db.query(
        'albums',
        columns: ['data'],
        where: 'id = ?',
        whereArgs: [albumId],
      );

      if (albumResult.isNotEmpty && albumResult[0]['data'] != null) {
        try {
          Map<String, dynamic> albumData =
              jsonDecode(albumResult[0]['data'].toString());

          if (albumData.containsKey('tracks') && albumData['tracks'] is List) {
            Logging.severe('Found tracks in album data for $albumId');
            return List<Map<String, dynamic>>.from(albumData['tracks']);
          }
        } catch (e) {
          Logging.severe('Error parsing album data: $e');
        }
      }

      // Return empty list if nothing found
      return [];
    } catch (e, stack) {
      Logging.severe('Error getting tracks for album: $albumId', e, stack);
      return [];
    }
  }

  /// Save tracks for an album to the database
  static Future<void> saveTracksForAlbum(
      String albumId, List<Map<String, dynamic>> tracks) async {
    try {
      await initializeDatabase();

      final db = await DatabaseHelper.instance.database;

      // Store each track
      for (var track in tracks) {
        // Update the track data to match the correct database schema
        final Map<String, dynamic> trackData = {
          'id': track['id'] ??
              track['trackId'] ??
              '', // Ensure we use the right field name
          'album_id': albumId, // Add album_id column
          'name': track['name'],
          'position': track['position'],
          'duration_ms': track['duration_ms'],
          'data': track['data'] ?? '{}',
        };

        await db.insert(
          'tracks',
          trackData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      Logging.severe(
          'Saved ${tracks.length} tracks to database for album $albumId');
    } catch (e, stack) {
      Logging.severe('Error saving tracks for album $albumId', e, stack);
      rethrow; // Re-throw for caller to handle
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

  static Future<List<CustomList>> getCustomLists() async {
    try {
      // Replace SharedPreferences usage with DatabaseHelper
      final lists = await DatabaseHelper.instance.getAllCustomLists();
      return lists.map((map) => CustomList.fromJson(map)).toList();
    } catch (e, stack) {
      Logging.severe('Error getting custom lists', e, stack);
      return [];
    }
  }

  static Future<bool> saveCustomList(CustomList list) async {
    try {
      await DatabaseHelper.instance.saveCustomList(
        list.id,
        list.name,
        list.description,
        list.albumIds,
        createdAt: list.createdAt,
        updatedAt: list.updatedAt,
      );
      return true;
    } catch (e, stack) {
      Logging.severe('Error saving custom list', e, stack);
      return false;
    }
  }

  static Future<bool> deleteCustomList(String listId) async {
    try {
      await DatabaseHelper.instance.deleteCustomList(listId);
      return true;
    } catch (e, stack) {
      Logging.severe('Error deleting custom list', e, stack);
      return false;
    }
  }

  /// Get custom lists in the saved order
  static Future<List<CustomList>> getOrderedCustomLists() async {
    try {
      // Get all lists first
      final lists = await getCustomLists();

      // Get custom list order from DatabaseHelper
      final orderResult = await DatabaseHelper.instance.getCustomListOrder();

      if (orderResult.isNotEmpty) {
        // Create a map for sorting
        final listMap = {for (var list in lists) list.id: list};
        final orderedLists = <CustomList>[];

        // First add lists in saved order
        for (final id in orderResult) {
          if (listMap.containsKey(id)) {
            orderedLists.add(listMap[id]!);
            listMap.remove(id);
          }
        }

        // Add any remaining lists
        orderedLists.addAll(listMap.values);

        return orderedLists;
      } else {
        // Fall back to sorting by creation date
        lists.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return lists;
      }
    } catch (e, stack) {
      Logging.error('Error getting ordered custom lists', e, stack);
      return [];
    }
  }

  // Add the missing method for saveCustomListOrder
  static Future<bool> saveCustomListOrder(List<String> listIds) async {
    try {
      await initializeDatabase();
      await DatabaseHelper.instance.saveCustomListOrder(listIds);
      return true;
    } catch (e, stack) {
      Logging.error('Error saving custom list order', e, stack);
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

  /// Get default search platform from preferences
  static Future<SearchPlatform> getDefaultSearchPlatform() async {
    try {
      final db = DatabaseHelper.instance;
      final platformIndex =
          int.tryParse(await db.getSetting('defaultSearchPlatform') ?? '0') ??
              0;

      if (platformIndex < SearchPlatform.values.length) {
        return SearchPlatform.values[platformIndex];
      }

      return SearchPlatform.itunes; // Default
    } catch (e) {
      Logging.severe('Error getting default search platform', e);
      return SearchPlatform.itunes; // Default on error
    }
  }

  static Future<String?> getDefaultPlatform() async {
    return await DatabaseHelper.instance.getSetting('default_platform');
  }

  static Future<void> setDefaultPlatform(String platform) async {
    try {
      // Remove the unused 'db' variable
      await DatabaseHelper.instance.saveSetting('default_platform', platform);
    } catch (e, stack) {
      Logging.severe('Error setting default platform', e, stack);
    }
  }

  static Future<String?> getSearchPlatform() async {
    try {
      final dbHelper = DatabaseHelper.instance;
      return await dbHelper.getSetting('searchPlatform');
    } catch (e, stack) {
      Logging.severe('Error getting search platform', e, stack);
      return null;
    }
  }

  static Future<void> setSearchPlatform(String platform) async {
    await DatabaseHelper.instance.saveSetting('searchPlatform', platform);
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
      final db = DatabaseHelper.instance;

      progressCallback?.call('Clearing existing data...', 0.1);

      // Clear existing SharedPreferences data
      await db.clearSettings();

      progressCallback?.call('Importing data to SharedPreferences...', 0.2);

      // Import all keys from backup
      int processedCount = 0;
      final totalKeys = data.keys.length;

      for (final entry in data.entries) {
        final key = entry.key;
        final value = entry.value;

        if (key == '_backup_meta') continue; // Skip metadata

        if (value is String) {
          await db.saveSetting(key, value);
        } else if (value is bool) {
          await db.saveSetting(key, value.toString());
        } else if (value is int) {
          await db.saveSetting(key, value.toString());
        } else if (value is double) {
          await db.saveSetting(key, value.toString());
        } else if (value is List) {
          if (value.every((item) => item is String)) {
            await db.saveSetting(key, value.join(','));
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
      final savedAlbums =
          (await db.getSetting('saved_albums'))?.split(',') ?? [];
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
    } catch (e, stack) {
      Logging.severe('Error checking database integrity', e, stack);
      return false;
    }
  }

  /// Save a single track to the database
  static Future<void> saveTrack(String albumId, String trackId, String name,
      int position, int durationMs) async {
    try {
      await initializeDatabase();
      final db = await getDatabaseInstance();

      // Create a JSON object to store as data
      final trackData = {
        'title': name,
        'position': position,
        'durationMs': durationMs
      };

      await db.insert(
        'tracks',
        {
          'id': trackId,
          'album_id': albumId,
          'name': name,
          'position': position,
          'duration_ms': durationMs,
          'data': json
              .encode(trackData), // Store JSON data for additional information
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e, stack) {
      Logging.severe('Error saving track', e, stack);
    }
  }

  // Replace db.getAllSettings() with a manual query to the settings table
  Future<List<Map<String, dynamic>>> getAllSettings() async {
    final db = await DatabaseHelper.instance.database;
    return await db.query('settings');
  }

  // Replace db.clearSettings() with a manual delete from the settings table
  Future<void> clearSettings() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('settings');
  }

  static Future<void> saveAlbumNote(String albumId, String note) async {
    try {
      Logging.severe(
          'Saving album note for ID: $albumId (length: ${note.length})');

      if (albumId.isEmpty) {
        Logging.severe('Cannot save album note: Empty album ID');
        return;
      }

      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;

      // First check if the table exists and create it if not
      try {
        final tableCheck = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='album_notes'");

        if (tableCheck.isEmpty) {
          Logging.severe('Album notes table not found, forcing recreation');
          // Force recreation of the table using the specialized method
          final success = await dbHelper.recreateAlbumNotesTable();
          if (!success) {
            Logging.severe(
                'Failed to create album_notes table, cannot save note');
            return;
          }
        }
      } catch (e) {
        Logging.severe('Error checking for album_notes table: $e');
        // Force recreation as a fallback
        await dbHelper.recreateAlbumNotesTable();
      }

      try {
        // Check if a note already exists for this album
        final existing = await db.query(
          'album_notes',
          where: 'album_id = ?',
          whereArgs: [albumId],
        );

        if (existing.isEmpty) {
          // Insert new note
          await db.insert(
            'album_notes',
            {'album_id': albumId, 'note': note},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          Logging.severe('Inserted new album note for ID: $albumId');
        } else {
          // Update existing note
          await db.update(
            'album_notes',
            {'note': note},
            where: 'album_id = ?',
            whereArgs: [albumId],
          );
          Logging.severe('Updated existing album note for ID: $albumId');
        }
      } catch (e) {
        Logging.severe('Error with standard approach to save note: $e');

        // Try a different approach with direct SQL
        try {
          // Ensure the table exists
          await db.execute('''
            CREATE TABLE IF NOT EXISTS album_notes (
              album_id TEXT PRIMARY KEY,
              note TEXT
            )
          ''');

          // Delete any existing note
          await db.rawDelete(
              'DELETE FROM album_notes WHERE album_id = ?', [albumId]);

          // Insert new note
          await db.rawInsert(
              'INSERT INTO album_notes (album_id, note) VALUES (?, ?)',
              [albumId, note]);

          Logging.severe('Saved album note using direct SQL approach');
        } catch (e2, stack2) {
          Logging.severe('All attempts to save album note failed', e2, stack2);
        }
      }
    } catch (e, stack) {
      Logging.severe('Error saving album note', e, stack);
    }
  }

  static Future<String?> getAlbumNote(String albumId) async {
    try {
      Logging.severe('Retrieving album note for ID: $albumId');

      if (albumId.isEmpty) {
        Logging.severe('Cannot get album note: Empty album ID');
        return null;
      }

      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;

      // Check if the table exists first to avoid errors
      try {
        final tableCheck = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='album_notes'");

        if (tableCheck.isEmpty) {
          Logging.severe('Album notes table not found, forcing recreation');
          // Force recreation of the table
          final success = await dbHelper.recreateAlbumNotesTable();
          if (!success) {
            Logging.severe(
                'Failed to create album_notes table, cannot retrieve note');
            return null;
          }
        }
      } catch (e) {
        Logging.severe('Error checking album_notes table: $e');
        // Try to recreate the table
        await dbHelper.recreateAlbumNotesTable();
      }

      try {
        // Get the note
        final result = await db.rawQuery(
            'SELECT note FROM album_notes WHERE album_id = ?', [albumId]);

        if (result.isNotEmpty) {
          final note = result.first['note'] as String?;
          Logging.severe(
              'Retrieved album note for ID: $albumId (found: ${note != null})');
          return note;
        }
      } catch (e) {
        Logging.severe('Error querying album note: $e');
      }

      Logging.severe('No album note found for ID: $albumId');
      return null;
    } catch (e) {
      Logging.severe('Error retrieving album note: $e');
      return null;
    }
  }
}
