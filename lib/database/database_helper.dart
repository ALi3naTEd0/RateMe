import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // Add this import
import 'package:path_provider/path_provider.dart';
import '../logging.dart';
import '../album_model.dart';

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

      // Check for other essential tables and create them if needed
      // ... similar checks for other tables
    } catch (e, stack) {
      Logging.severe('Error ensuring database tables exist', e, stack);
    }
  }

  // Get the database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  // Initialize the database
  Future<Database> _initDb() async {
    try {
      Logging.severe('Initializing database at ${await getDatabasePath()}');
      Database db = await openDatabase(
        await getDatabasePath(),
        version: 1,
        onCreate: (db, version) async {
          await _createDb(db, version);
        },
        onOpen: (db) async {
          // Check if indices exist and create them if not
          await _ensureIndices(db);
        },
      );

      return db;
    } catch (e, stack) {
      Logging.severe('Error initializing database', e, stack);
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

    // Add indices for common lookups
    await _createIndices(db);
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
        'artworkUrl': album.artworkUrl,
        'url': album.url,
        'platform': album.platform,
        'releaseDate': album.releaseDate.toIso8601String(),
        'data': album.metadata.toString(),
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

  Future<List<Map<String, dynamic>>> getAllAlbums() async {
    final db = await database;
    return await db.query('albums');
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

  Future<List<Map<String, dynamic>>> getAllCustomLists() async {
    try {
      final db = await database;
      final lists = await db.query('custom_lists');

      // Map field names to expected format
      return lists.map((list) {
        final Map<String, dynamic> result = Map.from(list);

        // Handle both snake_case and camelCase field formats
        if (list.containsKey('created_at')) {
          result['createdAt'] = list['created_at'];
        }

        if (list.containsKey('updated_at')) {
          result['updatedAt'] = list['updated_at'];
        }

        return result;
      }).toList();
    } catch (e, stack) {
      Logging.severe('Error getting all custom lists', e, stack);
      return [];
    }
  }

  Future<void> deleteCustomList(String listId) async {
    final db = await database;
    await db.delete(
      'custom_lists',
      where: 'id = ?',
      whereArgs: [listId],
    );

    // Also delete all album-list relationships
    await db.delete(
      'album_lists',
      where: 'list_id = ?',
      whereArgs: [listId],
    );
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
    final db = await database;
    await db.insert(
      'settings',
      {
        'key': key,
        'value': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );

    if (result.isEmpty) return null;
    return result.first['value'].toString();
  }
}
