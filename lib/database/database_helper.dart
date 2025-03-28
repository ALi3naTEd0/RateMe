import 'dart:async';
import 'dart:convert'; // Add this import
import 'dart:math'; // Add this import for the min function
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // Add this import
import '../album_model.dart';
import '../logging.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static DatabaseHelper get instance => _instance;

  static Database? _db;

  // Database version - increment this when schema changes
  static const int _version = 1;
  static const String _databaseName = 'rateme.db';

  // Table names
  static const String tableAlbums = 'albums';
  static const String tableRatings = 'ratings';
  static const String tableCustomLists = 'custom_lists';
  static const String tableAlbumLists = 'album_lists';
  static const String tableSettings = 'settings';
  static const String tableAlbumOrder = 'album_order';

  DatabaseHelper._internal();

  // Initialize the database factory
  static Future<void> initialize() async {
    // Initialize FFI for desktop platforms
    sqfliteFfiInit();
    // Set the database factory to use FFI
    databaseFactory = databaseFactoryFfi;
    Logging.severe('SQLite database factory initialized');
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    Logging.severe('Initializing database');
    final String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _version,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    Logging.severe('Creating database tables');

    // Albums table
    await db.execute('''
      CREATE TABLE $tableAlbums(
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        platform TEXT NOT NULL,
        name TEXT NOT NULL,
        artist TEXT NOT NULL,
        artwork_url TEXT NOT NULL,
        release_date TEXT NOT NULL,
        url TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Ratings table
    await db.execute('''
      CREATE TABLE $tableRatings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        album_id TEXT NOT NULL,
        track_id TEXT NOT NULL,
        rating REAL NOT NULL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (album_id) REFERENCES $tableAlbums (id) ON DELETE CASCADE,
        UNIQUE(album_id, track_id)
      )
    ''');

    // Custom lists table
    await db.execute('''
      CREATE TABLE $tableCustomLists(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Album-List junction table (many-to-many)
    await db.execute('''
      CREATE TABLE $tableAlbumLists(
        album_id TEXT NOT NULL,
        list_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (album_id, list_id),
        FOREIGN KEY (album_id) REFERENCES $tableAlbums (id) ON DELETE CASCADE,
        FOREIGN KEY (list_id) REFERENCES $tableCustomLists (id) ON DELETE CASCADE
      )
    ''');

    // Settings table
    await db.execute('''
      CREATE TABLE $tableSettings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Album order table
    await db.execute('''
      CREATE TABLE $tableAlbumOrder(
        position INTEGER PRIMARY KEY,
        album_id TEXT NOT NULL,
        FOREIGN KEY (album_id) REFERENCES $tableAlbums (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _upgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    Logging.severe(
        'Upgrading database from version $oldVersion to $newVersion');

    // Handle future schema migrations here
    if (oldVersion < 2) {
      // Migrations for version 2
    }
  }

  // ALBUM METHODS

  Future<int> insertAlbum(Album album) async {
    final db = await database;

    // Convert album to Map
    final Map<String, dynamic> row = {
      'id': album.id.toString(),
      'data': album.toJson().toString(),
      'platform': album.platform,
      'name': album.name,
      'artist': album.artist,
      'artwork_url': album.artworkUrl,
      'release_date': album.releaseDate.toIso8601String(),
      'url': album.url,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    // Use INSERT OR REPLACE to handle duplicates
    return await db.insert(
      tableAlbums,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Album?> getAlbum(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableAlbums,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) {
      return null;
    }

    try {
      final albumData = maps.first['data'];
      // Handle string data properly
      if (albumData is String) {
        try {
          // Try to parse the data as JSON
          final parsedData = jsonDecode(albumData);
          return Album.fromJson(parsedData);
        } catch (e) {
          Logging.severe('Error parsing album data JSON: $e');
          // Try to use the raw row data as fallback
          return Album(
            id: maps.first['id'],
            name: maps.first['name'],
            artist: maps.first['artist'],
            artworkUrl: maps.first['artwork_url'],
            url: maps.first['url'],
            platform: maps.first['platform'],
            releaseDate: DateTime.parse(maps.first['release_date']),
          );
        }
      } else if (albumData is Map<String, dynamic>) {
        return Album.fromJson(albumData);
      } else {
        throw Exception('Unexpected data type: ${albumData.runtimeType}');
      }
    } catch (e) {
      Logging.severe('Error parsing album data: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getAllAlbums() async {
    final db = await database;
    // Change to fetch the complete record data from the albums table
    final results = await db.query(tableAlbums);
    Logging.severe('getAllAlbums: Raw query returned ${results.length} albums');

    // Parse the data field to extract full album information
    List<Map<String, dynamic>> albums = [];
    for (var row in results) {
      try {
        // Add direct access to artwork URL
        Map<String, dynamic> completeAlbum = {
          'id': row['id'],
          'name': row['name'],
          'artist': row['artist'],
          'artworkUrl': row['artwork_url'],
          'artworkUrl100': row['artwork_url'], // Add alias for compatibility
          'platform': row['platform'],
          'url': row['url'],
          'releaseDate': row['release_date'],
        };

        // Also parse the JSON data for full details
        if (row['data'] is String) {
          try {
            final albumData = jsonDecode(row['data'] as String);
            // Log the parsed data for the first album
            if (albums.isEmpty) {
              Logging.severe(
                  'First album JSON data parsed: ${albumData.keys.join(', ')}');
            }
            completeAlbum.addAll(albumData);
          } catch (e) {
            Logging.severe(
                'Error parsing JSON data for album ${row['id']}: $e');
            // Try to log the problematic data - Fix the nullable value issue and min function
            final dataString = row['data'] as String?;
            if (dataString != null) {
              Logging.severe(
                  'Problematic data: ${dataString.substring(0, min(50, dataString.length))}...');
            } else {
              Logging.severe('Problematic data is null');
            }
          }
        } else {
          Logging.severe(
              'Album ${row['id']} has data of type: ${row['data']?.runtimeType ?? 'null'}');
        }

        // Ensure essential fields are included
        if (!completeAlbum.containsKey('artworkUrl') &&
            completeAlbum.containsKey('artworkUrl100')) {
          completeAlbum['artworkUrl'] = completeAlbum['artworkUrl100'];
        } else if (!completeAlbum.containsKey('artworkUrl100') &&
            completeAlbum.containsKey('artworkUrl')) {
          completeAlbum['artworkUrl100'] = completeAlbum['artworkUrl'];
        }

        albums.add(completeAlbum);
      } catch (e, stack) {
        Logging.severe('Error parsing album ${row['id']}', e, stack);
      }
    }

    Logging.severe('getAllAlbums: Returning ${albums.length} processed albums');
    return albums;
  }

  Future<int> deleteAlbum(String id) async {
    final db = await database;
    return await db.delete(
      tableAlbums,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // RATINGS METHODS

  Future<void> saveRating(String albumId, String trackId, double rating) async {
    final db = await database;

    final Map<String, dynamic> row = {
      'album_id': albumId,
      'track_id': trackId,
      'rating': rating,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await db.insert(
      tableRatings,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getRatingsForAlbum(String albumId) async {
    final db = await database;
    return await db.query(
      tableRatings,
      where: 'album_id = ?',
      whereArgs: [albumId],
    );
  }

  // CUSTOM LISTS METHODS

  Future<int> insertCustomList(Map<String, dynamic> list) async {
    final db = await database;

    final now = DateTime.now().toIso8601String();
    final Map<String, dynamic> row = {
      'id': list['id'],
      'name': list['name'],
      'description': list['description'] ?? '',
      'created_at': list['createdAt'] ?? now,
      'updated_at': now,
    };

    return await db.insert(
      tableCustomLists,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllCustomLists() async {
    final db = await database;
    return await db.query(tableCustomLists);
  }

  Future<int> deleteCustomList(String id) async {
    final db = await database;
    return await db.delete(
      tableCustomLists,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ALBUM-LIST RELATIONSHIP METHODS

  Future<void> addAlbumToList(
      String albumId, String listId, int position) async {
    final db = await database;

    final Map<String, dynamic> row = {
      'album_id': albumId,
      'list_id': listId,
      'position': position,
    };

    await db.insert(
      tableAlbumLists,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>> getAlbumIdsForList(String listId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableAlbumLists,
      columns: ['album_id'],
      where: 'list_id = ?',
      whereArgs: [listId],
      orderBy: 'position ASC',
    );

    return List<String>.from(maps.map((m) => m['album_id']));
  }

  Future<int> removeAlbumFromList(String albumId, String listId) async {
    final db = await database;
    return await db.delete(
      tableAlbumLists,
      where: 'album_id = ? AND list_id = ?',
      whereArgs: [albumId, listId],
    );
  }

  // SETTINGS METHODS

  Future<void> saveSetting(String key, String value) async {
    final db = await database;

    final Map<String, dynamic> row = {
      'key': key,
      'value': value,
    };

    await db.insert(
      tableSettings,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableSettings,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );

    if (maps.isEmpty) {
      return null;
    }

    return maps.first['value'];
  }

  // ALBUM ORDER METHODS

  Future<void> saveAlbumOrder(List<String> albumIds) async {
    final db = await database;

    // First delete existing order
    await db.delete(tableAlbumOrder);

    // Then insert new order
    Batch batch = db.batch();
    for (int i = 0; i < albumIds.length; i++) {
      batch.insert(tableAlbumOrder, {
        'position': i,
        'album_id': albumIds[i],
      });
    }

    await batch.commit(noResult: true);
  }

  Future<List<String>> getAlbumOrder() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableAlbumOrder,
      columns: ['album_id'],
      orderBy: 'position ASC',
    );

    return List<String>.from(maps.map((m) => m['album_id']));
  }
}
