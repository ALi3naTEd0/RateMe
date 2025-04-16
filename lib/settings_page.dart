import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_svg/svg.dart';
import 'package:rateme/global_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'user_data.dart';
import 'logging.dart';
import 'debug_util.dart';
import 'database/database_helper.dart';
import 'database/migration_utility.dart'; // Add this import for MigrationUtility
import 'widgets/skeleton_loading.dart'; // Add this import at the top with other imports
import 'search_service.dart'; // Add this import for SearchPlatform enum

class SettingsPage extends StatefulWidget {
  final ThemeMode currentTheme;
  final Function(ThemeMode) onThemeChanged;
  final Color currentPrimaryColor;
  final Function(Color) onPrimaryColorChanged;

  const SettingsPage({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.currentPrimaryColor,
    required this.onPrimaryColorChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  late Color pickerColor;
  late Color textColor;
  final defaultColor = const Color(0xFF864AF9);
  final defaultTextColor = Colors.white;
  bool useDarkText = false;
  bool isLoading = true;
  SearchPlatform defaultSearchPlatform = SearchPlatform.itunes;

  // Add refresh indicator key
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  // Add default search platform selection
  SearchPlatform _defaultSearchPlatform = SearchPlatform.itunes;

  // Add these GlobalKeys at the top of your _SettingsPageState class
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  // Add this field to store the current platform
  SearchPlatform _currentPlatform = SearchPlatform.itunes;

  @override
  void initState() {
    super.initState();
    pickerColor = widget.currentPrimaryColor;
    textColor = defaultTextColor;
    _loadSettings();
    _checkDatabaseSize();
    _loadPreferences();
    // Load saved platform preference
    _loadPlatformPreference();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        useDarkText = prefs.getBool('useDarkButtonText') ?? false;
        isLoading = false;

        // Load default search platform preference
        final platformIndex = prefs.getInt('defaultSearchPlatform') ?? 0;
        if (platformIndex < SearchPlatform.values.length) {
          defaultSearchPlatform = SearchPlatform.values[platformIndex];
        }
      });
    }
  }

  Future<void> _loadPreferences() async {
    try {
      // Get database instance
      final db = DatabaseHelper.instance;

      // Load dark button text preference
      final darkButtonTextSetting = await db.getSetting('useDarkButtonText');
      // Fix: Change from final to var since we're reassigning it
      var useDarkText = darkButtonTextSetting == 'true';

      // Load default search platform
      final platformIndexSetting =
          await db.getSetting('default_search_platform');
      int platformIndex = 0;
      if (platformIndexSetting != null) {
        platformIndex = int.tryParse(platformIndexSetting) ?? 0;
      }

      if (platformIndex < SearchPlatform.values.length) {
        _defaultSearchPlatform = SearchPlatform.values[platformIndex];
      }

      if (mounted) {
        setState(() {
          useDarkText = useDarkText;
        });
      }
    } catch (e) {
      Logging.severe('Error loading settings preferences', e);
    }
  }

  Future<void> _checkDatabaseSize() async {
    if (mounted) {
      setState(() {});
    }
  }

  void _showSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showAdvancedColorPicker() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Color Picker',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ColorPicker(
                    pickerColor: pickerColor,
                    onColorChanged: (color) {
                      setState(() {
                        pickerColor = color;
                        textColor = color.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white;
                      });
                      widget.onPrimaryColorChanged(color);
                    },
                    portraitOnly: true,
                    colorPickerWidth: 300,
                    enableAlpha: false,
                    hexInputBar: true,
                    displayThumbColor: true,
                  ),
                  TextButton(
                    onPressed: () => navigator.pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showClearDatabaseDialog() async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final result = await navigator.push<bool>(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Clear Database',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text('This will delete:'),
                  const SizedBox(height: 8),
                  const Text('• All saved albums'),
                  const Text('• All ratings'),
                  const Text('• All custom lists'),
                  const Text('• All settings'),
                  const SizedBox(height: 16),
                  const Text(
                    'This action cannot be undone!',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => navigator.pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () => navigator.pop(true),
                        child: const Text('Clear Everything'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true) {
      try {
        final db = await DatabaseHelper.instance.database;
        await db.transaction((txn) async {
          await txn.delete('albums');
          await txn.delete('ratings');
          await txn.delete('custom_lists');
          await txn.delete('album_lists');
          await txn.delete('album_order');
        });

        navigatorKey.currentState?.popUntil((route) => route.isFirst);
        _showSnackBar('Database cleared successfully');
      } catch (e) {
        Logging.severe('Error clearing database', e);
        _showSnackBar('Error clearing database: $e');
      }
    }
  }

  Future<void> _showRepairDialog() async {
    _showProgressDialog('Repairing Data...',
        'Please wait while your data is being repaired...');

    try {
      bool repairResult = false;
      int removedRatings = 0;

      final db = await DatabaseHelper.instance.database;

      final List<Map<String, dynamic>> orphanedRatings = await db.rawQuery('''
        SELECT ratings.* FROM ratings 
        LEFT JOIN albums ON ratings.album_id = albums.id
        WHERE albums.id IS NULL
      ''');

      if (orphanedRatings.isNotEmpty) {
        for (var rating in orphanedRatings) {
          await db.delete(
            'ratings',
            where: 'id = ?',
            whereArgs: [rating['id']],
          );
        }
        removedRatings = orphanedRatings.length;
        repairResult = true;
      }

      navigatorKey.currentState?.pop(); // Dismiss progress
      _showSnackBar(
        '${repairResult ? "Albums repaired successfully!" : "No album repairs needed"}\n'
        'Removed $removedRatings orphaned ratings.',
      );
    } catch (e) {
      navigatorKey.currentState?.pop(); // Dismiss progress
      _showSnackBar('Error repairing data: $e');
    }
  }

  Future<void> _importBackupWithProgress() async {
    _showProgressDialog('Importing Backup', 'Reading backup file...');

    try {
      final result = await UserData.importData(
        progressCallback: (stage, progress) {
          if (mounted) {
            final navigator = navigatorKey.currentState;
            if (navigator == null) return;

            navigator.pop();
            _showProgressDialog(
              'Importing Backup',
              stage,
              progress: progress,
            );
          }
        },
      );

      navigatorKey.currentState?.pop();

      if (result && mounted) {
        _showImportSuccessDialog();
      } else if (!result && mounted) {
        _showSnackBar('Import failed or was cancelled');
      }
    } catch (e, stack) {
      Logging.severe('Error during backup import', e, stack);
      navigatorKey.currentState?.pop();
      _showSnackBar('Import failed: $e');
    }
  }

  void _showProgressDialog(String title, String message, {double? progress}) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  progress != null
                      ? LinearProgressIndicator(value: progress)
                      : const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _performForceMigration() async {
    _showProgressDialog('Migrating Data', 'Creating temporary backup...');

    try {
      Logging.severe('Starting force migration process');

      final prefs = await SharedPreferences.getInstance();
      final savedAlbums = prefs.getStringList('saved_albums') ?? [];

      if (savedAlbums.isEmpty) {
        Logging.severe(
            'No SharedPreferences data found, rebuilding SQLite database only');
        await _rebuildSQLiteDatabase();
      } else {
        Logging.severe(
            'Found ${savedAlbums.length} albums in SharedPreferences, migrating to SQLite');

        await MigrationUtility.resetMigrationStatus();

        final backupData = <String, dynamic>{};

        for (final key in prefs.getKeys()) {
          final value = prefs.get(key);
          if (value != null) {
            if (value is List<String>) {
              backupData[key] = value;
            } else {
              backupData[key] = value;
            }
          }
        }

        backupData['_backup_meta'] = {
          'version': 1,
          'timestamp': DateTime.now().toIso8601String(),
          'format': 'legacy'
        };

        navigatorKey.currentState?.pop();
        _showProgressDialog(
            'Rebuilding Database', 'Clearing existing database...');

        final db = await DatabaseHelper.instance.database;
        await db.transaction((txn) async {
          await txn.delete('albums');
          await txn.delete('ratings');
          await txn.delete('custom_lists');
          await txn.delete('album_lists');
          await txn.delete('album_order');
          await txn.delete('settings');
        });
        Logging.severe('Database cleared successfully');

        if (savedAlbums.isNotEmpty) {
          try {
            final firstAlbum = jsonDecode(savedAlbums.first);
            Logging.severe(
                'First album in migration: id=${firstAlbum['collectionId'] ?? firstAlbum['id']}, name=${firstAlbum['collectionName'] ?? firstAlbum['name']}');
          } catch (e) {
            Logging.severe('Error parsing first album for debug: $e');
          }
        }

        navigatorKey.currentState?.pop();
        _showProgressDialog(
            'Rebuilding Database', 'Importing data from SharedPreferences...');

        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
        final tempBackupPath =
            '${tempDir.path}/rateme_migration_$timestamp.json';
        final file = File(tempBackupPath);
        await file.writeAsString(jsonEncode(backupData));
        Logging.severe('Importing directly from file: $tempBackupPath');

        bool success = await MigrationUtility.migrateToSQLite();

        if (!success) {
          Logging.severe('Direct migration failed, trying file-based import');
          success = await UserData.importData(
              fromFile: tempBackupPath, skipFilePicker: true);
        }

        await file.delete();

        if (success) {
          Logging.severe(
              'Data imported successfully from SharedPreferences to SQLite');

          final db = await DatabaseHelper.instance.database;
          final count =
              await db.rawQuery('SELECT COUNT(*) as count FROM albums');
          final albumCount = Sqflite.firstIntValue(count) ?? 0;
          Logging.severe(
              'After migration: Album count in database = $albumCount');

          if (albumCount == 0) {
            Logging.severe(
                'WARNING: Migration reported success but no albums were imported');
          }
        } else {
          Logging.severe('Migration failed - import returned false');
        }
      }

      final stats = await _getMigrationStats();

      navigatorKey.currentState?.pop();
      _showForceMigrationSuccessDialog(stats);
    } catch (e, stack) {
      Logging.severe('Error during force migration', e, stack);
      navigatorKey.currentState?.pop();
      _showSnackBar('Migration failed: $e');
    }
  }

  Future<void> _rebuildSQLiteDatabase() async {
    try {
      final db = await DatabaseHelper.instance.database;

      final backupData = <String, dynamic>{};

      backupData['_backup_meta'] = {
        'version': 2,
        'timestamp': DateTime.now().toIso8601String(),
        'format': 'sqlite'
      };

      final albums = await DatabaseHelper.instance.getAllAlbums();
      backupData['albums'] = albums;
      Logging.severe('Exported ${albums.length} albums');

      final ratings = await db.query('ratings');
      backupData['ratings'] = ratings;
      Logging.severe('Exported ${ratings.length} ratings');

      final lists = await db.query('custom_lists');
      backupData['custom_lists'] = lists;
      Logging.severe('Exported ${lists.length} custom lists');

      final albumLists = await db.query('album_lists');
      backupData['album_lists'] = albumLists;
      Logging.severe('Exported ${albumLists.length} album-list relationships');

      final albumOrder = await db.query('album_order', orderBy: 'position ASC');
      backupData['album_order'] = albumOrder;
      Logging.severe('Exported album order information');

      final settings = await db.query('settings');
      backupData['settings'] = settings;
      Logging.severe('Exported ${settings.length} settings');

      navigatorKey.currentState?.pop();
      _showProgressDialog(
          'Rebuilding Database', 'Clearing existing database...');

      await db.transaction((txn) async {
        await txn.delete('albums');
        await txn.delete('ratings');
        await txn.delete('custom_lists');
        await txn.delete('album_lists');
        await txn.delete('album_order');
        await txn.delete('settings');
      });
      Logging.severe('Database cleared successfully');

      navigatorKey.currentState?.pop();
      _showProgressDialog(
          'Rebuilding Database', 'Importing data into SQLite...');

      await db.transaction((txn) async {
        if (backupData['albums'] != null) {
          for (final album in backupData['albums']) {
            await txn.insert('albums', album);
          }
        }

        if (backupData['ratings'] != null) {
          for (final rating in backupData['ratings']) {
            await txn.insert('ratings', rating);
          }
        }

        if (backupData['custom_lists'] != null) {
          for (final list in backupData['custom_lists']) {
            await txn.insert('custom_lists', list);
          }
        }

        if (backupData['album_lists'] != null) {
          for (final albumList in backupData['album_lists']) {
            await txn.insert('album_lists', albumList);
          }
        }

        if (backupData['album_order'] != null) {
          for (final order in backupData['album_order']) {
            await txn.insert('album_order', order);
          }
        }

        if (backupData['settings'] != null) {
          for (final setting in backupData['settings']) {
            await txn.insert('settings', setting);
          }
        }
      });

      Logging.severe('Data imported successfully into SQLite');
    } catch (e, stack) {
      Logging.severe('Error rebuilding SQLite database', e, stack);
      rethrow;
    }
  }

  Future<Map<String, int>> _getMigrationStats() async {
    final stats = {
      'albums': 0,
      'ratings': 0,
      'lists': 0,
      'listAlbums': 0,
    };

    try {
      final db = await DatabaseHelper.instance.database;

      final albumResults =
          await db.rawQuery('SELECT COUNT(*) as count FROM albums');
      stats['albums'] = Sqflite.firstIntValue(albumResults) ?? 0;

      final ratingResults =
          await db.rawQuery('SELECT COUNT(*) as count FROM ratings');
      stats['ratings'] = Sqflite.firstIntValue(ratingResults) ?? 0;

      final listResults =
          await db.rawQuery('SELECT COUNT(*) as count FROM custom_lists');
      stats['lists'] = Sqflite.firstIntValue(listResults) ?? 0;

      final listAlbumResults =
          await db.rawQuery('SELECT COUNT(*) as count FROM album_lists');
      stats['listAlbums'] = Sqflite.firstIntValue(listAlbumResults) ?? 0;
    } catch (e) {
      Logging.severe('Error getting migration stats: $e');
    }

    return stats;
  }

  void _showForceMigrationSuccessDialog(Map<String, int> stats) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => AlertDialog(
          title: const Text('Migration Successful'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your database has been successfully rebuilt!'),
              const SizedBox(height: 16),
              const Text('Database Contents:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildStatRow(Icons.album, 'Albums', stats['albums'] ?? 0),
              _buildStatRow(Icons.audiotrack, 'Ratings', stats['ratings'] ?? 0),
              _buildStatRow(Icons.list, 'Lists', stats['lists'] ?? 0),
              _buildStatRow(Icons.playlist_add_check, 'Albums in lists',
                  stats['listAlbums'] ?? 0),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  void _showImportSuccessDialog() async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    try {
      final db = await DatabaseHelper.instance.database;

      final albumResults =
          await db.rawQuery('SELECT COUNT(*) as count FROM albums');
      final albumCount = Sqflite.firstIntValue(albumResults) ?? 0;

      final ratingResults =
          await db.rawQuery('SELECT COUNT(*) as count FROM ratings');
      final ratingCount = Sqflite.firstIntValue(ratingResults) ?? 0;

      final listResults =
          await db.rawQuery('SELECT COUNT(*) as count FROM custom_lists');
      final listCount = Sqflite.firstIntValue(listResults) ?? 0;

      final listAlbumResults =
          await db.rawQuery('SELECT COUNT(*) as count FROM album_lists');
      final listAlbumCount = Sqflite.firstIntValue(listAlbumResults) ?? 0;

      navigator.push(
        PageRouteBuilder(
          barrierColor: Colors.black54,
          opaque: false,
          pageBuilder: (_, __, ___) => AlertDialog(
            title: const Text('Import Successful'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your data was imported successfully!'),
                const SizedBox(height: 16),
                const Text('Imported Data:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildStatRow(Icons.album, 'Albums', albumCount),
                _buildStatRow(Icons.audiotrack, 'Ratings', ratingCount),
                _buildStatRow(Icons.list, 'Lists', listCount),
                _buildStatRow(Icons.playlist_add_check, 'Albums in lists',
                    listAlbumCount),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => navigator.pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      Logging.severe('Error showing import stats: $e');
      _showSnackBar('Import completed successfully!');
    }
  }

  Widget _buildStatRow(IconData icon, String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Text(
            count.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String colorToHex(Color color) {
    int rgb = ((color.a * 255).round() << 24) | (color.toARGB32() & 0x00FFFFFF);
    String value = '#${rgb.toRadixString(16).padLeft(6, '0').substring(2)}';
    return value;
  }

  Future<void> _performDatabaseMaintenance() async {
    _showProgressDialog('Database Maintenance', 'Checking database size...');

    try {
      // Get database size before vacuum
      final sizeBefore = await UserData.getDatabaseSize();

      // Check database integrity
      final isIntegrityOk = await UserData.checkDatabaseIntegrity();
      if (!isIntegrityOk) {
        navigatorKey.currentState?.pop();
        _showSnackBar(
            'Database integrity check failed. Consider restoring from backup.');
        return;
      }

      navigatorKey.currentState?.pop();
      _showProgressDialog('Database Maintenance', 'Optimizing database...');

      // Perform vacuum
      final vacuumSuccess = await UserData.vacuumDatabase();

      if (!vacuumSuccess) {
        navigatorKey.currentState?.pop();
        _showSnackBar('Database optimization failed');
        return;
      }

      // Get database size after vacuum
      final sizeAfter = await UserData.getDatabaseSize();

      navigatorKey.currentState?.pop();

      // Show results
      final savedSpace = sizeBefore - sizeAfter;
      final percent = sizeBefore > 0 ? (savedSpace / sizeBefore * 100.0) : 0.0;

      _showMaintenanceResultDialog(
        sizeBefore: sizeBefore,
        sizeAfter: sizeAfter,
        savedSpace: savedSpace,
        percent: percent,
      );
    } catch (e, stack) {
      Logging.severe('Error during database maintenance', e, stack);
      navigatorKey.currentState?.pop();
      _showSnackBar('Error during database maintenance: $e');
    }
  }

  void _showMaintenanceResultDialog({
    required int sizeBefore,
    required int sizeAfter,
    required int savedSpace,
    required double percent,
  }) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    // Format sizes for display
    final beforeMB = (sizeBefore / 1024 / 1024).toStringAsFixed(2);
    final afterMB = (sizeAfter / 1024 / 1024).toStringAsFixed(2);
    final savedKB = (savedSpace / 1024).toStringAsFixed(2);

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => AlertDialog(
          title: const Text('Database Optimization Complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Previous size: $beforeMB MB'),
              Text('New size: $afterMB MB'),
              const SizedBox(height: 8),
              Text(
                savedSpace > 0
                    ? 'Space saved: $savedKB KB (${percent.toStringAsFixed(1)}%)'
                    : 'No space was saved. Your database is already optimized.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: savedSpace > 0 ? Colors.green : null,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'The database has been optimized for better performance.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  // Add refresh method
  Future<void> _refreshData() async {
    Logging.severe('Refreshing settings page');

    // Set loading state
    setState(() {
      isLoading = true;
    });

    // Reload settings
    await _loadSettings();
    await _checkDatabaseSize();
    await _loadPreferences();

    // Show feedback to user
    _showSnackBar('Settings refreshed');

    Logging.severe('Settings refresh complete');
  }

  // Save default search platform using the database
  Future<void> _saveDefaultSearchPlatform(SearchPlatform platform) async {
    try {
      final db = DatabaseHelper.instance;
      await db.saveSetting(
          'default_search_platform', platform.index.toString());

      Logging.severe(
          'Default search platform updated to ${platform.name} (index: ${platform.index})');

      setState(() {
        _defaultSearchPlatform = platform;
      });

      // Notify the app about the default platform change
      GlobalNotifications.defaultSearchPlatformChanged(platform);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Default search platform updated to ${platform.name}')),
        );
      }
    } catch (e) {
      Logging.severe('Error saving default search platform', e);
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error setting default platform: $e')),
      );
    }
  }

  // Add a method to load platform preference
  Future<void> _loadPlatformPreference() async {
    try {
      final db = DatabaseHelper.instance;
      final platformStr = await db.getSetting('default_search_platform');

      if (platformStr != null) {
        int platformIndex = int.tryParse(platformStr) ?? 0;
        if (platformIndex >= 0 &&
            platformIndex < SearchPlatform.values.length) {
          setState(() {
            _currentPlatform = SearchPlatform.values[platformIndex];
          });
        }
      }
      Logging.severe(
          'Loaded default search platform: ${_currentPlatform.name}');
    } catch (e) {
      Logging.severe('Error loading default search platform', e);
    }
  }

  // Helper method to get platform icon - completely rewritten - add bandcamp case
  IconData getPlatformIconForPlatform(SearchPlatform platform) {
    switch (platform) {
      case SearchPlatform.itunes:
        return Icons.album;
      case SearchPlatform.spotify:
        return Icons.album;
      case SearchPlatform.deezer:
        return Icons.album;
      case SearchPlatform.discogs:
        return Icons.album;
      case SearchPlatform.bandcamp:
        return Icons.album;
    }
  }

  // Add the missing _getPlatformIconPath method to _SettingsPageState
  String _getPlatformIconPath(SearchPlatform platform) {
    switch (platform) {
      case SearchPlatform.itunes:
        return 'lib/icons/apple_music.svg';
      case SearchPlatform.spotify:
        return 'lib/icons/spotify.svg';
      case SearchPlatform.deezer:
        return 'lib/icons/deezer.svg';
      case SearchPlatform.discogs:
        return 'lib/icons/discogs.svg';
      case SearchPlatform.bandcamp:
        return 'lib/icons/bandcamp.svg';
    }
  }

  // When displaying SearchPlatform.itunes in dropdowns or lists, make sure it shows as Apple Music
  String _getDisplayNameForPlatform(SearchPlatform platform) {
    switch (platform) {
      case SearchPlatform.itunes:
        return 'Apple Music'; // Changed from "iTunes" to "Apple Music"
      case SearchPlatform.spotify:
        return 'Spotify';
      case SearchPlatform.deezer:
        return 'Deezer';
      case SearchPlatform.discogs:
        return 'Discogs';
      case SearchPlatform.bandcamp:
        return 'Bandcamp';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageWidth = MediaQuery.of(context).size.width * 0.85;
    final horizontalPadding =
        (MediaQuery.of(context).size.width - pageWidth) / 2;

    // Log current theme mode for debugging
    Logging.severe(
        'Current theme mode in settings page: ${widget.currentTheme}');

    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: Theme.of(context),
      home: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          automaticallyImplyLeading: false,
          title: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                const Text('Settings'),
              ],
            ),
          ),
        ),
        body: Center(
          child: SizedBox(
            width: pageWidth,
            child: isLoading
                ? _buildSkeletonSettings()
                : RefreshIndicator(
                    key: _refreshIndicatorKey,
                    onRefresh: _refreshData,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        // Theme Section
                        Card(
                          margin: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Theme',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              RadioListTile<ThemeMode>(
                                title: const Text('System'),
                                value: ThemeMode.system,
                                groupValue: widget.currentTheme,
                                onChanged: (ThemeMode? mode) {
                                  if (mode != null) {
                                    widget.onThemeChanged(mode);
                                    setState(() {});
                                  }
                                },
                              ),
                              RadioListTile<ThemeMode>(
                                title: const Text('Light'),
                                value: ThemeMode.light,
                                groupValue: widget.currentTheme,
                                onChanged: (ThemeMode? mode) {
                                  if (mode != null) {
                                    widget.onThemeChanged(mode);
                                    setState(() {});
                                  }
                                },
                              ),
                              RadioListTile<ThemeMode>(
                                title: const Text('Dark'),
                                value: ThemeMode.dark,
                                groupValue: widget.currentTheme,
                                onChanged: (ThemeMode? mode) {
                                  if (mode != null) {
                                    widget.onThemeChanged(mode);
                                    setState(() {});
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                        // Color Section
                        Card(
                          margin: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'App Colors',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.restore),
                                      tooltip: 'Restore default colors',
                                      onPressed: () {
                                        setState(() {
                                          pickerColor = defaultColor;
                                          textColor = defaultTextColor;
                                        });
                                        widget.onPrimaryColorChanged(
                                            defaultColor);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              ListTile(
                                title: const Text('Primary Color'),
                                subtitle: Text(
                                  colorToHex(pickerColor)
                                      .toString()
                                      .toUpperCase(),
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                trailing: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: pickerColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.grey),
                                  ),
                                ),
                                onTap: () => _showAdvancedColorPicker(),
                              ),
                              ListTile(
                                title: const Text('Button Text Color'),
                                trailing: Switch(
                                  value: useDarkText,
                                  thumbIcon:
                                      WidgetStateProperty.resolveWith<Icon?>(
                                          (states) {
                                    return Icon(
                                      useDarkText
                                          ? Icons.format_color_text
                                          : Icons.format_color_reset,
                                      size: 16,
                                      color: useDarkText
                                          ? Colors.black
                                          : Colors.white,
                                    );
                                  }),
                                  inactiveTrackColor: HSLColor.fromColor(
                                          Theme.of(context).colorScheme.primary)
                                      .withAlpha(0.5)
                                      .toColor(),
                                  activeTrackColor:
                                      Theme.of(context).colorScheme.primary,
                                  activeColor:
                                      Colors.black, // When active, always black
                                  inactiveThumbColor: Colors
                                      .white, // When inactive, always white
                                  onChanged: (bool value) async {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool(
                                        'useDarkButtonText', value);
                                    setState(() {
                                      useDarkText = value;
                                    });
                                  },
                                ),
                                subtitle: Text(
                                    useDarkText ? 'Dark text' : 'Light text'),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Preview:'),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .scaffoldBackgroundColor,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Theme.of(context).dividerColor,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.palette,
                                              color: pickerColor),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Sample Text',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .textTheme
                                                  .bodyLarge
                                                  ?.color,
                                            ),
                                          ),
                                          const Spacer(),
                                          FilledButton(
                                            onPressed: () {},
                                            style: FilledButton.styleFrom(
                                              backgroundColor: pickerColor,
                                              foregroundColor: useDarkText
                                                  ? Colors.black
                                                  : Colors.white,
                                              textStyle: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            child: const Text('Button'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Search Preferences Section
                        Card(
                          margin: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Search Preferences',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Default search platform dropdown
                                Row(
                                  children: [
                                    const Text('Default Search Platform:'),
                                    const Spacer(),
                                    DropdownButton<SearchPlatform>(
                                      value: _defaultSearchPlatform,
                                      underline: Container(),
                                      onChanged: (SearchPlatform? platform) {
                                        if (platform != null) {
                                          _saveDefaultSearchPlatform(platform);
                                        }
                                      },
                                      items: [
                                        SearchPlatform.itunes,
                                        SearchPlatform.spotify,
                                        SearchPlatform.deezer,
                                        SearchPlatform.discogs,
                                      ].map((platform) {
                                        return DropdownMenuItem<SearchPlatform>(
                                          value: platform,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SvgPicture.asset(
                                                _getPlatformIconPath(platform),
                                                width: 30,
                                                height: 30,
                                                // Fix icon colors for both themes
                                                colorFilter: ColorFilter.mode(
                                                    Theme.of(context)
                                                                .brightness ==
                                                            Brightness.dark
                                                        ? Colors.white
                                                        : Colors.black,
                                                    BlendMode.srcIn),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(_getDisplayNameForPlatform(
                                                  platform)),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Data Management Section
                        Card(
                          margin: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Data Management',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ListTile(
                                leading: const Icon(Icons.file_download),
                                title: const Text('Import Backup'),
                                subtitle: const Text(
                                    'Restore data from a backup file'),
                                onTap: _importBackupWithProgress,
                              ),
                              ListTile(
                                leading: const Icon(Icons.file_upload),
                                title: const Text('Export Backup'),
                                subtitle: const Text(
                                    'Save all your data as a backup file'),
                                onTap: () async {
                                  final success = await UserData.exportData();
                                  if (success) {
                                    _showSnackBar(
                                        'Backup created successfully');
                                  } else {
                                    _showSnackBar('Failed to create backup');
                                  }
                                },
                              ),
                              const Divider(),
                              ListTile(
                                leading: const Icon(Icons.storage),
                                title: const Text('Migrate to SQLite Database'),
                                subtitle: const Text(
                                    'Convert legacy data to new database format for better performance'),
                                onTap: () => _performForceMigration(),
                              ),
                            ],
                          ),
                        ),

                        // Database Management Section
                        Card(
                          margin: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Database Maintenance',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ListTile(
                                leading: const Icon(Icons.cleaning_services),
                                title: const Text('Optimize Database'),
                                subtitle: const Text(
                                    'Clean and optimize the database for better performance'),
                                onTap: _performDatabaseMaintenance,
                              ),
                              FutureBuilder<int>(
                                future: UserData.getDatabaseSize(),
                                builder: (context, snapshot) {
                                  final size = snapshot.data ?? 0;
                                  final sizeText = size > 0
                                      ? '${(size / 1024 / 1024).toStringAsFixed(2)} MB'
                                      : 'Unknown';

                                  return Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      'Current database size: $sizeText',
                                      style: const TextStyle(
                                        fontStyle: FontStyle.italic,
                                        fontSize: 14,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        // Debug & Development Section
                        Card(
                          margin: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Debug & Development',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ListTile(
                                leading: const Icon(Icons.bug_report),
                                title: const Text('Show Debug Info'),
                                subtitle:
                                    const Text('View technical information'),
                                onTap: () => DebugUtil.showDebugReport(context),
                              ),
                              ListTile(
                                leading: const Icon(Icons.healing),
                                title: const Text('Repair Album Data'),
                                subtitle: const Text(
                                    'Fix problems with album display'),
                                onTap: () => _showRepairDialog(),
                              ),
                              ListTile(
                                leading: const Icon(Icons.delete_forever),
                                title: const Text('Clear Database'),
                                subtitle: const Text(
                                    'Delete all saved data (cannot be undone)'),
                                onTap: () => _showClearDatabaseDialog(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonSettings() {
    return ListView(
      children: [
        // Theme section skeleton
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoading(width: 80, height: 24),
                const SizedBox(height: 16),
                ...List.generate(
                  3,
                  (index) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: SkeletonLoading(height: 40),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Colors section skeleton
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoading(width: 120, height: 24),
                const SizedBox(height: 16),
                ...List.generate(
                  2,
                  (index) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SkeletonLoading(width: 120, height: 20),
                        SkeletonLoading(
                            width: 40, height: 40, borderRadius: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Data Management section skeleton
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoading(width: 150, height: 24),
                const SizedBox(height: 16),
                ...List.generate(
                  3,
                  (index) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: SkeletonLoading(height: 48),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Database Management section skeleton
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoading(width: 150, height: 24),
                const SizedBox(height: 16),
                ...List.generate(
                  2,
                  (index) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: SkeletonLoading(height: 48),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Debug & Development section skeleton
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoading(width: 150, height: 24),
                const SizedBox(height: 16),
                ...List.generate(
                  3,
                  (index) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: SkeletonLoading(height: 48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
