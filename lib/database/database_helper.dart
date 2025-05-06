import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import '../logging.dart';
import '../album_model.dart';
import '../platforms/platform_service_factory.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  // Private constructor
  DatabaseHelper._privateConstructor();

  // Database initialization flag
  static bool _initialized = false;

  // Initialize the database helper
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Initialize FFI for desktop platforms
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        // Initialize FFI
        sqfliteFfiInit();
        // Set the database factory to use FFI
        databaseFactory = databaseFactoryFfi;
        Logging.severe('Initialized database with FFI for desktop platform');
      } else {
        Logging.severe('Using standard SQLite for mobile platform');
      }

      // Get database instance and ensure tables exist
      final db = await instance.database;
      await _ensureTables(db);
      _initialized = true;
      Logging.severe('Database initialized successfully');
    } catch (e, stack) {
      Logging.severe('Error initializing database helper', e, stack);
    }
  }

  // Add a new method to verify and create tables if needed
  static Future<void> _ensureTables(Database db) async {
    try {
      // Check if tracks table exists
      final tableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='tracks'");

      if (tableCheck.isEmpty) {
        Logging.severe('Tracks table not found, creating it now');
        // Create the tracks table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS tracks (
            id TEXT,
            album_id TEXT,
            name TEXT NOT NULL,
            position INTEGER,
            duration_ms INTEGER,
            data TEXT,
            PRIMARY KEY (id, album_id),
            FOREIGN KEY (album_id) REFERENCES albums(id)
          )
        ''');

        // Create index for tracks
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_tracks_album_id ON tracks(album_id)');

        Logging.severe('Tracks table created successfully');
      }

      // Check for album_notes table and create if missing
      final albumNotesCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='album_notes'");

      if (albumNotesCheck.isEmpty) {
        // Table doesn't exist, create it
        Logging.severe('Album notes table not found, creating it now');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS album_notes (
            album_id TEXT PRIMARY KEY,
            note TEXT
          )
        ''');
        Logging.severe('Album notes table created successfully');

        // Explicitly check that the table was created
        final verifyCheck = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='album_notes'");
        if (verifyCheck.isEmpty) {
          Logging.severe('ERROR: Failed to create album_notes table!');
        } else {
          Logging.severe('Verified album_notes table was created properly');
        }
      } else {
        Logging.severe('Album notes table already exists');
      }
    } catch (e, stack) {
      Logging.severe('Error ensuring database tables exist', e, stack);
    }
  }

  // Add this new method specifically for recreating the album_notes table
  Future<bool> recreateAlbumNotesTable() async {
    try {
      final db = await database;
      Logging.severe('Force recreating album_notes table');

      // Try to drop the table first in case it exists but is corrupted
      try {
        await db.execute('DROP TABLE IF EXISTS album_notes');
        Logging.severe('Dropped existing album_notes table');
      } catch (e) {
        Logging.severe('Could not drop album_notes table: $e');
      }

      // Create the table
      await db.execute('''
        CREATE TABLE album_notes (
          album_id TEXT PRIMARY KEY,
          note TEXT
        )
      ''');

      // Verify table was created
      final check = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='album_notes'");

      if (check.isEmpty) {
        Logging.severe(
            'Failed to recreate album_notes table after explicit attempt');
        return false;
      }

      Logging.severe('Successfully recreated album_notes table');
      return true;
    } catch (e, stack) {
      Logging.severe('Error recreating album_notes table', e, stack);
      return false;
    }
  }

  // Add this new method after the _ensureTables method
  Future<void> updateDatabaseSchema() async {
    try {
      Logging.severe('Checking and updating database schema if needed');
      final db = await database;
      await _updateDatabaseSchemaInternal(db);
    } catch (e, stack) {
      Logging.severe('Error updating database schema', e, stack);
    }
  }

  // Get the database instance with locking to prevent concurrent access issues
  Future<Database> get database async {
    _database ??= await _initDb();
    return _database!;
  }

  // Helper method for synchronization - simplified without using unused lock object
  Future<T> synchronized<T>(Object lock, Future<T> Function() action) async {
    if (_database != null) return action();
    try {
      Logging.severe('Acquiring database lock');
      return await action();
    } finally {
      Logging.severe('Released database lock');
    }
  }

  // Initialize the database with proper error handling and timeouts
  Future<Database> _initDb() async {
    try {
      Logging.severe('Initializing database at ${await getDatabasePath()}');
      final path = await getDatabasePath();
      // Add proper timeout settings
      Database db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await _createDb(db, version);
        },
        onOpen: (db) async {
          // Check if indices exist and create them if not
          await _ensureIndices(db);
        },
        // Add timeout settings
        singleInstance: true,
        readOnly: false,
        // Remove the unsupported queryTimeoutDuration parameter
      );
      try {
        // Try to set WAL mode using rawQuery instead of execute for better Android compatibility
        await db.rawQuery('PRAGMA journal_mode = WAL');
        Logging.severe('Successfully set WAL journal mode');
      } catch (e) {
        // If setting WAL fails, log it but continue (don't crash)
        Logging.severe(
            'Failed to set WAL journal mode: $e (continuing anyway)');
      }
      // Update schema directly with the db instance
      await _updateDatabaseSchemaInternal(db);
      try {
        // Set pragmas for better performance and stability
        await db.execute('PRAGMA synchronous = NORMAL;');
        await db.execute('PRAGMA cache_size = 1000;');
        await db.execute('PRAGMA temp_store = MEMORY;');
      } catch (e) {
        Logging.severe('Error setting pragmas: $e');
      }
      return db;
    } catch (e, stack) {
      Logging.severe('Error initializing database', e, stack);
      rethrow;
    }
  }

  // Create a non-recursive version of updateDatabaseSchema that accepts a database instance
  Future<void> _updateDatabaseSchemaInternal(Database db) async {
    try {
      Logging.severe('Updating database schema internally');

      // Check if master_release_map table exists
      final masterReleaseTableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='master_release_map'");
      if (masterReleaseTableCheck.isEmpty) {
        Logging.severe('Creating missing master_release_map table');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS master_release_map (
            master_id TEXT,
            release_id TEXT,
            timestamp TEXT,
            PRIMARY KEY (master_id)
          )
        ''');
      } else {
        // Check if release_id column exists in master_release_map table
        final columnCheck =
            await db.rawQuery('PRAGMA table_info(master_release_map)');
        final columnNames =
            columnCheck.map((c) => c['name'].toString()).toList();
        if (!columnNames.contains('release_id')) {
          Logging.severe(
              'Adding missing release_id column to master_release_map table');
          // SQLite doesn't directly support adding columns with constraints, so we need to recreate the table
          await db.transaction((txn) async {
            // Create temporary table with correct schema
            await txn.execute('''
              CREATE TABLE master_release_map_temp (
                master_id TEXT,
                release_id TEXT,
                timestamp TEXT,
                PRIMARY KEY (master_id)
              )
            ''');
            // Copy data from old table to new one
            await txn.execute('''
              INSERT INTO master_release_map_temp (master_id, timestamp)
              SELECT master_id, timestamp FROM master_release_map
            ''');
            // Drop old table
            await txn.execute('DROP TABLE master_release_map');
            // Rename new table to original name
            await txn.execute(
                'ALTER TABLE master_release_map_temp RENAME TO master_release_map');
          });
        }
      }

      // Check for platform_matches table
      final platformMatchesTableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='platform_matches'");
      if (platformMatchesTableCheck.isEmpty) {
        Logging.severe('Creating missing platform_matches table');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS platform_matches (
            album_id TEXT,
            platform TEXT,
            url TEXT,
            verified INTEGER DEFAULT 0,
            timestamp TEXT,
            PRIMARY KEY (album_id, platform)
          )
        ''');
      }

      // Check for custom_list_order table
      final customListOrderCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='custom_list_order'");
      if (customListOrderCheck.isEmpty) {
        Logging.severe('Creating missing custom_list_order table');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS custom_list_order (
            list_id TEXT PRIMARY KEY,
            position INTEGER,
            FOREIGN KEY (list_id) REFERENCES custom_lists(id)
          )
        ''');
      }

      Logging.severe('Database schema update completed');
    } catch (e, stack) {
      Logging.severe('Error in _updateDatabaseSchemaInternal', e, stack);
    }
  }

  // Get the database path
  Future<String> getDatabasePath() async {
    try {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        // For desktop apps, use app documents directory
        final appDir = await getApplicationDocumentsDirectory();
        return join(appDir.path, 'rateme.db');
      } else {
        // For mobile, use the default database location
        final dbPath = await getDatabasesPath();
        return join(dbPath, 'rateme.db');
      }
    } catch (e, stack) {
      Logging.severe('Error getting database path', e, stack);
      rethrow;
    }
  }

  // Function to create database tables
  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE albums (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        artist TEXT NOT NULL,
        artwork_url TEXT,
        url TEXT,
        platform TEXT,
        release_date TEXT,
        data TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE tracks (
        id TEXT,
        album_id TEXT,
        name TEXT NOT NULL,
        position INTEGER,
        duration_ms INTEGER,
        data TEXT,
        PRIMARY KEY (id, album_id),
        FOREIGN KEY (album_id) REFERENCES albums(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE ratings (
        album_id TEXT,
        track_id TEXT,
        rating REAL,
        timestamp TEXT,
        PRIMARY KEY (album_id, track_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE custom_lists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        createdAt TEXT,
        updatedAt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE album_lists (
        list_id TEXT,
        album_id TEXT,
        position INTEGER,
        PRIMARY KEY (list_id, album_id),
        FOREIGN KEY (list_id) REFERENCES custom_lists(id),
        FOREIGN KEY (album_id) REFERENCES albums(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE album_order (
        album_id TEXT PRIMARY KEY,
        position INTEGER,
        FOREIGN KEY (album_id) REFERENCES albums(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // Add search history table
    await db.execute('''
      CREATE TABLE search_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        query TEXT NOT NULL,
        platform TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    // Add platform matches table
    await db.execute('''
      CREATE TABLE platform_matches (
        album_id TEXT,
        platform TEXT,
        url TEXT,
        verified INTEGER DEFAULT 0,
        timestamp TEXT,
        PRIMARY KEY (album_id, platform)
      )
    ''');

    // Add master-release mapping table for Discogs
    await db.execute('''
      CREATE TABLE master_release_map (
        master_id TEXT PRIMARY KEY,
        release_id TEXT,
        timestamp TEXT
      )
    ''');

    // Add album notes table
    await db.execute('''
      CREATE TABLE album_notes (
        album_id TEXT PRIMARY KEY,
        note TEXT
      )
    ''');

    // Add indices for common lookups
    await _createIndices(db);
  }

  // Create indices for better performance
  Future<void> _createIndices(Database db) async {
    try {
      Logging.severe('Creating database indices');

      // Index for ratings lookups by album_id
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ratings_album_id ON ratings(album_id)');
      // Index for ratings lookups by track_id
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ratings_track_id ON ratings(track_id)');
      // Index for album platform (useful for filtering by source)
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_albums_platform ON albums(platform)');
      // Compound index for album_lists to speed up list retrieval
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_album_lists_list_id ON album_lists(list_id, position)');
      // Index for album_order to speed up ordered album retrieval
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_album_order_position ON album_order(position)');
      Logging.severe('Database indices created successfully');
    } catch (e, stack) {
      Logging.severe('Error creating database indices', e, stack);
    }
  }

  // Ensure indices exist (for database upgrades/migrations)
  Future<void> _ensureIndices(Database db) async {
    try {
      // Check if the ratings album_id index exists
      var result = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_ratings_album_id'");
      if (result.isEmpty) {
        // Indices don't exist, create them
        await _createIndices(db);
      }
    } catch (e, stack) {
      Logging.severe('Error checking indices', e, stack);
    }
  }

  // Add a vacuum method to optimize the database
  Future<bool> vacuumDatabase() async {
    try {
      Logging.severe('Starting database vacuum');
      final db = await database;
      // Run VACUUM to rebuild the database file, reclaiming unused space
      await db.execute('VACUUM');
      // Run ANALYZE to update statistics used by the query optimizer
      await db.execute('ANALYZE');
      Logging.severe('Database vacuum completed successfully');
      return true;
    } catch (e, stack) {
      Logging.severe('Error vacuuming database', e, stack);
      return false;
    }
  }

  // Add a method to get database size
  Future<int> getDatabaseSize() async {
    try {
      final dbPath = await getDatabasePath();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        final size = await dbFile.length();
        Logging.severe(
            'Database size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
        return size;
      }
      return 0;
    } catch (e, stack) {
      Logging.severe('Error getting database size', e, stack);
      return 0;
    }
  }

  // Add a method to run integrity check
  Future<bool> checkDatabaseIntegrity() async {
    try {
      Logging.severe('Running database integrity check');
      final db = await database;
      final results = await db.rawQuery('PRAGMA integrity_check');
      final isOk = results.isNotEmpty &&
          results.first.containsKey('integrity_check') &&
          results.first['integrity_check'] == 'ok';
      if (isOk) {
        Logging.severe('Database integrity check passed');
      } else {
        Logging.severe('Database integrity check failed: $results');
      }
      return isOk;
    } catch (e, stack) {
      Logging.severe('Error checking database integrity', e, stack);
      return false;
    }
  }

  // Album methods
  Future<void> insertAlbum(Album album) async {
    final db = await database;
    await db.insert(
      'albums',
      {
        'id': album.id.toString(),
        'name': album.name,
        'artist': album.artist,
        'artwork_url': album.artworkUrl, // <-- fix column name
        'url': album.url,
        'platform': album.platform,
        'release_date':
            album.releaseDate.toIso8601String(), // <-- fix column name
        'data': jsonEncode(album.metadata),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Album?> getAlbum(String id) async {
    final db = await database;
    final maps = await db.query(
      'albums',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    try {
      return Album.fromJson(maps.first);
    } catch (e, stack) {
      Logging.severe('Error parsing album from database', e, stack);
      return null;
    }
  }

  // Improved getAllAlbums method with proper transaction handling
  Future<List<Map<String, dynamic>>> getAllAlbums() async {
    final db = await database;
    try {
      return await db.query('albums');
    } catch (e, stack) {
      Logging.severe(
          'Error getting all albums, attempting to fix locks', e, stack);
      await fixDatabaseLocks();
      // Retry once after fixing locks
      final retryDb = await database;
      return await retryDb.query('albums');
    }
  }

  Future<void> deleteAlbum(String id) async {
    final db = await database;
    await db.delete(
      'albums',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Rating methods
  Future<void> saveRating(String albumId, String trackId, double rating) async {
    final db = await database;
    // Check if rating exists
    final existingRating = await db.query(
      'ratings',
      where: 'album_id = ? AND track_id = ?',
      whereArgs: [albumId, trackId],
    );
    if (existingRating.isEmpty) {
      // Insert new rating
      await db.insert(
        'ratings',
        {
          'album_id': albumId,
          'track_id': trackId,
          'rating': rating,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } else {
      // Update existing rating
      await db.update(
        'ratings',
        {
          'rating': rating,
          'timestamp': DateTime.now().toIso8601String(),
        },
        where: 'album_id = ? AND track_id = ?',
        whereArgs: [albumId, trackId],
      );
    }
  }

  Future<List<Map<String, dynamic>>> getRatingsForAlbum(String albumId) async {
    final db = await database;
    return await db.query(
      'ratings',
      where: 'album_id = ?',
      whereArgs: [albumId],
    );
  }

  // Album order methods
  Future<void> saveAlbumOrder(List<String> albumIds) async {
    final db = await database;
    // Clear existing order
    await db.delete('album_order');
    // Insert new order
    for (int i = 0; i < albumIds.length; i++) {
      await db.insert(
        'album_order',
        {
          'album_id': albumIds[i],
          'position': i,
        },
      );
    }
  }

  Future<List<String>> getAlbumOrder() async {
    final db = await database;
    final result = await db.query(
      'album_order',
      orderBy: 'position ASC',
    );
    return result.map((map) => map['album_id'].toString()).toList();
  }

  // Custom list methods
  Future<void> insertCustomList(Map<String, dynamic> list) async {
    try {
      final db = await database;

      // Check table schema
      final columns = await db.rawQuery('PRAGMA table_info(custom_lists)');
      final columnNames = columns.map((c) => c['name'].toString()).toList();
      // Adapt field names to match database schema
      final Map<String, dynamic> data = {};
      // Handle required fields
      data['id'] = list['id'];
      data['name'] = list['name'];
      data['description'] = list['description'] ?? '';

      // Handle timestamps based on actual table schema
      if (columnNames.contains('created_at') && list.containsKey('createdAt')) {
        data['created_at'] = list['createdAt'];
      }

      if (columnNames.contains('updated_at') && list.containsKey('updatedAt')) {
        data['updated_at'] = list['updatedAt'];
      }

      // For legacy schema that uses camelCase directly
      if (columnNames.contains('createdAt') && list.containsKey('createdAt')) {
        data['createdAt'] = list['createdAt'];
      }

      if (columnNames.contains('updatedAt') && list.containsKey('updatedAt')) {
        data['updatedAt'] = list['updatedAt'];
      }

      Logging.severe('Saving custom list with adapted data: $data');
      await db.insert(
        'custom_lists',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e, stack) {
      Logging.severe('Error inserting custom list', e, stack);
      rethrow;
    }
  }

  Future<void> addAlbumToList(
      String albumId, String listId, int position) async {
    final db = await database;
    await db.insert(
      'album_lists',
      {
        'album_id': albumId,
        'list_id': listId,
        'position': position,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getAlbumsInList(String listId) async {
    try {
      final db = await database;
      // Join album_lists with albums to get album data
      final results = await db.rawQuery('''
        SELECT a.*, al.position
        FROM albums a
        JOIN album_lists al ON a.id = al.album_id
        WHERE al.list_id = ?
        ORDER BY al.position
      ''', [listId]);
      return results;
    } catch (e, stack) {
      Logging.severe('Error getting albums in list', e, stack);
      return [];
    }
  }

  // alias method for backward compatibility
  Future<List<String>> getAlbumIdsForList(String listId) async {
    return getAlbumsInList(listId)
        .then((results) => results.map((map) => map['id'].toString()).toList());
  }

  // Settings methods
  Future<void> saveSetting(String key, String value) async {
    try {
      final db = await database;

      // Simple direct implementation without timestamps
      final List<Map<String, dynamic>> result = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      if (result.isNotEmpty) {
        // Update existing setting
        await db.update(
          'settings',
          {'value': value},
          where: 'key = ?',
          whereArgs: [key],
        );
      } else {
        // Insert new setting
        await db.insert(
          'settings',
          {'key': key, 'value': value},
        );
      }

      // Log for critical settings
      if (key == 'primaryColor' ||
          key == 'themeMode' ||
          key == 'useDarkButtonText') {
        Logging.severe('Setting saved successfully: $key = $value');
      }
    } catch (e, stack) {
      Logging.severe('Error saving setting: $key = $value', e, stack);
      // Try one more time with a simplified approach
      try {
        final db = await database;
        // Delete any existing value first
        await db.delete(
          'settings',
          where: 'key = ?',
          whereArgs: [key],
        );
        // Then insert fresh
        await db.insert(
          'settings',
          {'key': key, 'value': value},
        );
        Logging.severe('Setting saved using fallback method: $key = $value');
      } catch (e2, stack2) {
        Logging.severe(
            'Fatal error saving setting with fallback method', e2, stack2);
      }
    }
  }

  Future<String?> getSetting(String key) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> result = await db.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
      );
      if (result.isNotEmpty) {
        // For color settings, log the actual value to verify
        if (key == 'primaryColor') {
          Logging.severe(
              'DatabaseHelper: Retrieved primaryColor = ${result.first['value']}');
        }
        return result.first['value'] as String?;
      }
      return null;
    } catch (e, stack) {
      Logging.severe('Error getting setting: $key', e, stack);
      return null;
    }
  }

  // Helper method to save a custom list - enhanced version that replaces the simpler version above
  Future<void> saveCustomList(
      String listId, String name, String description, List<String> albumIds,
      {DateTime? createdAt, DateTime? updatedAt}) async {
    final db = await database;
    await db.transaction((txn) async {
      // Use txn for all DB operations inside this transaction!
      // Check table schema to handle both naming conventions
      final columns = await txn.rawQuery('PRAGMA table_info(custom_lists)');
      final columnNames = columns.map((c) => c['name'].toString()).toList();
      // Determine whether to use snake_case or camelCase field names
      final Map<String, dynamic> data = {
        'id': listId,
        'name': name,
        'description': description,
      };
      // Add timestamp fields in the right format based on schema
      if (columnNames.contains('created_at')) {
        data['created_at'] = (createdAt ?? DateTime.now()).toIso8601String();
        data['updated_at'] = (updatedAt ?? DateTime.now()).toIso8601String();
      } else {
        data['createdAt'] = (createdAt ?? DateTime.now()).toIso8601String();
        data['updatedAt'] = (updatedAt ?? DateTime.now()).toIso8601String();
      }
      await txn.insert(
        'custom_lists',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Then, delete any existing album relationships for this list
      await txn.delete(
        'album_lists',
        where: 'list_id = ?',
        whereArgs: [listId],
      );
      // Finally, insert all the album relationships with their positions
      for (int i = 0; i < albumIds.length; i++) {
        await txn.insert(
          'album_lists',
          {
            'list_id': listId,
            'album_id': albumIds[i],
            'position': i,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    Logging.severe('Saved custom list: $name with ${albumIds.length} albums');
  }

  // Improved getAllCustomLists method with proper transaction handling
  Future<List<Map<String, dynamic>>> getAllCustomLists() async {
    try {
      final db = await database;

      // Check table schema to handle both naming conventions
      final columns = await db.rawQuery('PRAGMA table_info(custom_lists)');
      final columnNames = columns.map((c) => c['name'].toString()).toList();
      final useSnakeCase = columnNames.contains('created_at');

      // Get all lists within a transaction to prevent locking
      final lists = await db.transaction((txn) async {
        return await txn.query('custom_lists');
      });

      // Process results outside of transaction to reduce lock time
      List<Map<String, dynamic>> result = [];
      for (var list in lists) {
        final listId = list['id'] as String;
        final Map<String, dynamic> resultList = Map.from(list);
        // Normalize field names to camelCase for consistency
        if (useSnakeCase) {
          if (list.containsKey('created_at')) {
            resultList['createdAt'] = list['created_at'];
          }
          if (list.containsKey('updated_at')) {
            resultList['updatedAt'] = list['updated_at'];
          }
        }
        // Get album IDs for this list in a separate transaction
        final albumResults = await db.transaction((txn) async {
          return await txn.query(
            'album_lists',
            columns: ['album_id'],
            where: 'list_id = ?',
            whereArgs: [listId],
            orderBy: 'position ASC',
          );
        });
        final albumIds =
            albumResults.map((row) => row['album_id'] as String).toList();
        resultList['albumIds'] = albumIds;
        result.add(resultList);
      }
      return result;
    } catch (e, stack) {
      Logging.severe(
          'Error getting custom lists, attempting to fix locks', e, stack);
      await fixDatabaseLocks();
      // Retry once after fixing locks
      final db = await database;
      final lists = await db.query('custom_lists');
      // Simplified return on retry to reduce complexity
      return lists;
    }
  }

  // Helper method to delete a custom list - enhanced version that uses transaction
  Future<void> deleteCustomList(String listId) async {
    final db = await database;
    await db.transaction((txn) async {
      // Delete the list
      await txn.delete(
        'custom_lists',
        where: 'id = ?',
        whereArgs: [listId],
      );
      // Delete all album relationships for this list
      await txn.delete(
        'album_lists',
        where: 'list_id = ?',
        whereArgs: [listId],
      );
    });
    Logging.severe('Deleted custom list: $listId');
  }

  // Add a new method to fix database locking issues
  Future<void> fixDatabaseLocks() async {
    try {
      Logging.severe('Attempting to fix database locks');

      // Close the current database connection
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
      // Wait a moment to ensure connection is closed
      await Future.delayed(const Duration(milliseconds: 500));
      // Get the database path
      final dbPath = await getDatabasePath();
      final dbFile = File(dbPath);
      // Check if database exists
      if (await dbFile.exists()) {
        // Check for lock files
        final journalFile = File('$dbPath-journal');
        final walFile = File('$dbPath-wal');
        final shmFile = File('$dbPath-shm');
        // Delete lock files if they exist
        if (await journalFile.exists()) {
          Logging.severe('Removing journal file');
          await journalFile.delete();
        }
        if (await walFile.exists()) {
          Logging.severe('Removing WAL file');
          await walFile.delete();
        }
        if (await shmFile.exists()) {
          Logging.severe('Removing SHM file');
          await shmFile.delete();
        }
      }
      // Reopen the database
      _database = await _initDb();
      Logging.severe('Database locks fixed and connection reopened');
    } catch (e, stack) {
      Logging.severe('Error fixing database locks', e, stack);
    }
  }

  // Add this method to fetch tracks for an album by albumId
  Future<List<Map<String, dynamic>>> getTracksForAlbum(String albumId) async {
    final db = await database;
    final results = await db.query(
      'tracks',
      where: 'album_id = ?',
      whereArgs: [albumId],
      orderBy: 'position ASC',
    );
    Logging.severe(
        'Retrieved ${results.length} tracks from database for album $albumId');
    if (results.isEmpty) return [];

    // Get ratings for this album
    final ratings = await getRatingsForAlbum(albumId);
    // Build a map of trackId -> rating
    final Map<String, double> ratingById = {
      for (var r in ratings)
        if (r['track_id'] != null && r['rating'] != null)
          r['track_id'].toString(): (r['rating'] as num).toDouble()
    };
    // Also build a map of position -> rating (for fallback)
    final Map<int, double> ratingByPosition = {};
    for (var r in ratings) {
      final tid = r['track_id']?.toString();
      final pos = int.tryParse(tid ?? '');
      if (pos != null && r['rating'] != null) {
        ratingByPosition[pos] = (r['rating'] as num).toDouble();
      }
    }

    List<Map<String, dynamic>> tracks = [];
    for (var result in results) {
      final trackId = result['id']?.toString();
      final trackNumber = result['position'] is int
          ? result['position'] as int
          : int.tryParse(result['position']?.toString() ?? '') ?? 0;
      // Try to get rating by ID, fallback to position, then fallback to trailing number in ID
      double rating = 0.0;
      if (ratingById.containsKey(trackId)) {
        rating = ratingById[trackId]!;
      } else if (ratingByPosition.containsKey(trackNumber)) {
        rating = ratingByPosition[trackNumber]!;
      } else {
        // Fallback: If trackId ends with a number, try to match rating by that number
        final match = RegExp(r'(\d+)$').firstMatch(trackId ?? '');
        if (match != null) {
          final trailingNum = int.tryParse(match.group(1)!);
          if (trailingNum != null &&
              ratingByPosition.containsKey(trailingNum)) {
            rating = ratingByPosition[trailingNum]!;
          }
        }
      }

      Map<String, dynamic> track = {
        'trackId': trackId,
        'trackName': result['name'],
        'trackNumber': trackNumber,
        'trackTimeMillis': result['duration_ms'],
        'rating': rating,
      };

      // Add extra data if available
      String? dataJson = result['data'] as String?;
      if (dataJson != null && dataJson.isNotEmpty) {
        try {
          final extraData = jsonDecode(dataJson);
          if (extraData is Map<String, dynamic>) {
            extraData.forEach((key, value) {
              if (value != null && !track.containsKey(key)) {
                track[key] = value;
              }
            });
          }
        } catch (e) {
          Logging.severe('Error parsing track data JSON: $e');
        }
      }
      tracks.add(track);
    }
    return tracks;
  }

  // Add a method to insert tracks for an album
  Future<void> insertTracks(
      String albumId, List<Map<String, dynamic>> tracks) async {
    final db = await database;

    await db.transaction((txn) async {
      for (var track in tracks) {
        // --- FIX: Ensure trackName and trackTimeMillis are mapped from possible Bandcamp keys ---
        String trackId = track['trackId']?.toString() ?? '';
        if (trackId.isEmpty) continue;
        // Try to get name from multiple possible keys
        String trackName = track['trackName'] ??
            track['name'] ??
            track['title'] ??
            'Unknown Track';
        // Try to get position from multiple possible keys
        int position = track['trackNumber'] ??
            track['position'] ??
            tracks.indexOf(track) + 1;

        // Try to get duration from multiple possible keys
        int durationMs = track['trackTimeMillis'] ??
            track['duration_ms'] ??
            track['durationMs'] ??
            track['duration'] ??
            0;
        await txn.insert(
          'tracks',
          {
            'id': trackId,
            'album_id': albumId,
            'name': trackName,
            'position': position,
            'duration_ms': durationMs,
            'data': jsonEncode(track),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    Logging.severe('Inserted ${tracks.length} tracks for album $albumId');
  }

  // Create tracks from rating IDs when no actual track data exists
  Future<List<Map<String, dynamic>>> createTracksFromRatings(
      String albumId) async {
    try {
      Logging.severe('Creating tracks from ratings for album $albumId');
      final db = await database;
      // Get all ratings for this album
      final ratings = await getRatingsForAlbum(albumId);
      if (ratings.isEmpty) return [];
      List<Map<String, dynamic>> tracks = [];
      // Create a track for each rating
      for (int i = 0; i < ratings.length; i++) {
        final rating = ratings[i];
        final trackId = rating['track_id'].toString();

        // Try to get track name from tracks table first
        final existingTracks = await db.query(
          'tracks',
          where: 'id = ?',
          whereArgs: [trackId],
        );
        String trackName = 'Track ${i + 1}';
        if (existingTracks.isNotEmpty) {
          trackName = existingTracks.first['name'].toString();
        }

        tracks.add({
          'trackId': trackId,
          'trackName': trackName,
          'trackNumber': i + 1,
          'trackTimeMillis': 0,
          'rating': rating['rating'],
        });
      }
      Logging.severe(
          'Created ${tracks.length} tracks from ratings for album $albumId');
      return tracks;
    } catch (e, stack) {
      Logging.severe('Error creating tracks from ratings', e, stack);
      return [];
    }
  }

  /// Utility: Update tracks for an album by scraping/parsing Bandcamp again using the album URL.
  /// This is for fixing old Bandcamp albums that were saved without track data.
  ///
  /// This implementation will use BandcampService if available.
  Future<bool> refreshBandcampAlbumTracks(
      String albumId, String albumUrl) async {
    // Only proceed for Bandcamp URLs
    if (!albumUrl.contains('bandcamp.com')) {
      Logging.severe(
          'refreshBandcampAlbumTracks: Not a Bandcamp URL: $albumUrl');
      return false;
    }
    Logging.severe(
        'Refreshing Bandcamp tracks for album $albumId from $albumUrl');
    try {
      // Try to use BandcampService if implemented
      // Import BandcampService at the top: import '../platforms/bandcamp_service.dart';
      // and PlatformServiceFactory: import '../platforms/platform_service_factory.dart';
      final platformFactory = PlatformServiceFactory();
      final bandcampService = platformFactory.getService('bandcamp');
      // Try to fetch album details using BandcampService
      final albumDetails = await bandcampService.fetchAlbumDetails(albumUrl);
      if (albumDetails != null &&
          albumDetails['tracks'] is List &&
          (albumDetails['tracks'] as List).isNotEmpty) {
        // Save tracks to DB
        await insertTracks(
            albumId, List<Map<String, dynamic>>.from(albumDetails['tracks']));
        Logging.severe('Refreshed Bandcamp tracks for $albumId');
        return true;
      } else {
        Logging.severe('BandcampService did not return valid track data.');
        return false;
      }
    } catch (e, stack) {
      Logging.severe('BandcampService not implemented or failed', e, stack);
      Logging.severe(
          'Bandcamp refresh not implemented. See BandcampService for details.');
      return false;
    }
  }

  /// Remove duplicate tracks for an album, keeping only the one with the longest duration for each normalized track name.
  Future<int> removeDuplicateTracksForAlbum(String albumId) async {
    final db = await database;
    int removed = 0;

    // Get all tracks for this album
    final tracks = await db.query(
      'tracks',
      where: 'album_id = ?',
      whereArgs: [albumId],
    );
    // Group by normalized name, keep the one with the longest duration
    final Map<String, Map<String, dynamic>> bestTracks = {};
    for (final track in tracks) {
      final name = (track['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final normalized = name.toLowerCase();
      final duration = track['duration_ms'] ?? 0;
      if (!bestTracks.containsKey(normalized) ||
          (bestTracks[normalized]?['duration_ms'] ?? 0) < duration) {
        bestTracks[normalized] = track;
      }
    }
    // Build a set of (id, album_id) to keep
    final Set<String> keepKeys =
        bestTracks.values.map((t) => '${t['id']}|${t['album_id']}').toSet();
    // Delete all tracks for this album not in keepKeys
    for (final track in tracks) {
      final key = '${track['id']}|${track['album_id']}';
      if (!keepKeys.contains(key)) {
        await db.delete(
          'tracks',
          where: 'id = ? AND album_id = ?',
          whereArgs: [track['id'], track['album_id']],
        );
        removed++;
      }
    }
    Logging.severe('Removed $removed duplicate tracks for album $albumId');
    return removed;
  }

  // Add these new methods:

  // Get all settings from the database
  Future<List<Map<String, dynamic>>> getAllSettings() async {
    final db = await database;
    return await db.query('settings');
  }

  // Clear all settings from the database
  Future<void> clearSettings() async {
    final db = await database;
    await db.delete('settings');
    Logging.severe('Cleared all settings from database');
  }
}
