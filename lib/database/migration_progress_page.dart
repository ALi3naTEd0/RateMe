import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../logging.dart';
import '../theme_service.dart'; // Change this import from theme.dart to theme_service.dart
import 'migration_utility.dart';
import 'database_helper.dart';

/// @deprecated This class is only used for one-time migration and will be removed in a future update
class MigrationStats {
  int albums = 0;
  int tracks = 0;
  int ratings = 0;
  int lists = 0;
  int listAlbums = 0;
}

/// @deprecated This page is only used for one-time migration and will be removed in a future update
class MigrationProgressPage extends StatefulWidget {
  const MigrationProgressPage({super.key});

  @override
  State<MigrationProgressPage> createState() => _MigrationProgressPageState();
}

class _MigrationProgressPageState extends State<MigrationProgressPage> {
  bool isMigrating = true;
  bool migrationSuccess = false;
  String status = 'Starting migration...';
  double progress = 0.0;
  MigrationStats stats = MigrationStats();
  bool showStats = false;

  @override
  void initState() {
    super.initState();
    _startMigration();
  }

  Future<void> _startMigration() async {
    try {
      // Check if migration is needed
      final isNeeded = !await MigrationUtility.isMigrationCompleted();

      if (!isNeeded) {
        setState(() {
          status = 'Migration already completed';
          progress = 1.0;
          migrationSuccess = true;
          isMigrating = false;
        });

        // Auto-continue after a short delay
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
        return;
      }

      // Count albums, ratings and lists before migration to show progress
      await _countExistingData();

      // Show preparing migration
      setState(() {
        status = 'Preparing migration...';
        progress = 0.1;
      });

      await Future.delayed(const Duration(milliseconds: 300));

      // Migrate albums
      setState(() {
        status = 'Migrating albums...';
        progress = 0.2;
      });

      await Future.delayed(const Duration(milliseconds: 300));

      // Migrate ratings
      setState(() {
        status = 'Migrating ratings...';
        progress = 0.4;
      });

      await Future.delayed(const Duration(milliseconds: 300));

      // Migrate custom lists
      setState(() {
        status = 'Migrating custom lists...';
        progress = 0.6;
      });

      await Future.delayed(const Duration(milliseconds: 300));

      // Migrate settings
      setState(() {
        status = 'Migrating settings...';
        progress = 0.8;
      });

      // Perform the actual migration
      final success = await MigrationUtility.migrateToSQLite();

      // Get migration results
      await _getMigrationResults();

      setState(() {
        status =
            success ? 'Migration completed successfully' : 'Migration failed';
        progress = 1.0;
        migrationSuccess = success;
        isMigrating = false;
        showStats = true;
      });

      // Auto-continue after a short delay if successful
      if (success) {
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e, stack) {
      Logging.severe('Error during migration', e, stack);
      setState(() {
        status = 'Migration failed: $e';
        isMigrating = false;
        migrationSuccess = false;
      });
    }
  }

  Future<void> _countExistingData() async {
    try {
      // Get the SharedPreferences data counts
      final prefs = await SharedPreferences.getInstance();
      final albums = prefs.getStringList('saved_albums') ?? [];
      stats.albums = albums.length;

      // Count ratings
      int ratingCount = 0;
      final allKeys = prefs.getKeys();
      final ratingKeys =
          allKeys.where((key) => key.startsWith('saved_ratings_')).toList();
      for (String key in ratingKeys) {
        final List<String> ratingsJson = prefs.getStringList(key) ?? [];
        ratingCount += ratingsJson.length;
      }
      stats.ratings = ratingCount;

      // Count lists
      final lists = prefs.getStringList('custom_lists') ?? [];
      stats.lists = lists.length;

      setState(() {});
    } catch (e) {
      Logging.severe('Error counting existing data: $e');
    }
  }

  Future<void> _getMigrationResults() async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Get album count
      final albumResults =
          await db.rawQuery('SELECT COUNT(*) as count FROM albums');
      stats.albums = Sqflite.firstIntValue(albumResults) ?? 0;

      // Get ratings count
      final ratingResults =
          await db.rawQuery('SELECT COUNT(*) as count FROM ratings');
      stats.ratings = Sqflite.firstIntValue(ratingResults) ?? 0;

      // Get lists count
      final listResults =
          await db.rawQuery('SELECT COUNT(*) as count FROM custom_lists');
      stats.lists = Sqflite.firstIntValue(listResults) ?? 0;

      // Get list-album relationships count
      final listAlbumResults =
          await db.rawQuery('SELECT COUNT(*) as count FROM album_lists');
      stats.listAlbums = Sqflite.firstIntValue(listAlbumResults) ?? 0;

      setState(() {});
    } catch (e) {
      Logging.severe('Error getting migration results: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Migration'),
        automaticallyImplyLeading: !isMigrating,
      ),
      body: Center(
        child: ConstrainedBox(
          // Use the ThemeService's standardized width constraint (85% of screen width)
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width *
                ThemeService.contentMaxWidthFactor,
          ),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.storage, size: 64),
                const SizedBox(height: 24),
                Text(
                  'Upgrading to SQLite Database',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Please do not close the app during this process.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                LinearProgressIndicator(
                  value: isMigrating ? null : progress,
                  minHeight: 8,
                ),
                const SizedBox(height: 16),
                Text(
                  status,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                if (showStats) ...[
                  const SizedBox(height: 24),
                  _buildStatsCard(),
                ],
                const SizedBox(height: 32),
                if (!isMigrating)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(migrationSuccess);
                    },
                    child: Text(migrationSuccess ? 'Continue' : 'Close'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Migration Results',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildStatRow(Icons.album, 'Albums', stats.albums),
            _buildStatRow(Icons.audiotrack, 'Ratings', stats.ratings),
            _buildStatRow(Icons.list, 'Lists', stats.lists),
            _buildStatRow(
                Icons.playlist_add_check, 'Albums in lists', stats.listAlbums),
          ],
        ),
      ),
    );
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
}
