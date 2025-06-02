import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rateme/database/database_helper.dart';
import 'package:rateme/database/cleanup_utility.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Add this import for Clipboard

/// Utility class for generating debug reports and performing diagnostics
class DebugUtil {
  // Create a global key for the snackbar
  static final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Get the scaffold messenger key
  static GlobalKey<ScaffoldMessengerState> get scaffoldMessengerKey =>
      _scaffoldMessengerKey;

  /// Generate a simple diagnostic report
  static Future<String> generateReport() async {
    // Get current time
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-ddTHH:mm:ss.SSSSSS');
    final timestamp = formatter.format(now);

    final StringBuffer report = StringBuffer();
    report.writeln('=== RateMe Debug Report ===');
    report.writeln('Generated at: $timestamp');
    report.writeln('');

    // Database helper
    final db = DatabaseHelper.instance;

    // Album data
    try {
      final albums = await db.getAllAlbums();
      report.writeln('Found ${albums.length} saved albums.');

      final order = await db.getAlbumOrder();
      report.writeln('Found ${order.length} albums in order list.');

      // Check album formats
      int validNewFormat = 0;
      int validLegacyFormat = 0;
      int invalidFormat = 0;

      for (final album in albums) {
        final data = album['data'] as String?;
        if (data == null || data.isEmpty) {
          invalidFormat++;
          continue;
        }

        try {
          final json = jsonDecode(data);
          // Check if this is new format (contains specific new format keys)
          if (json.containsKey('format_version') &&
              json['format_version'] == 2) {
            validNewFormat++;
          } else {
            // This is still in legacy format (just stored in SQLite)
            validLegacyFormat++;
          }
        } catch (e) {
          invalidFormat++;
        }
      }

      report.writeln('Valid new format albums: $validNewFormat');
      report.writeln('Valid legacy format albums: $validLegacyFormat');
      report.writeln('Invalid format albums: $invalidFormat');

      String migrationStatus = '';
      if (validNewFormat == albums.length) {
        migrationStatus = 'Complete (all albums use new format)';
      } else if (validLegacyFormat == albums.length) {
        migrationStatus = 'Pending (all albums use legacy format)';
      } else if (validNewFormat > 0) {
        migrationStatus =
            'In progress ($validNewFormat/${albums.length} albums migrated)';
      } else {
        migrationStatus = 'Unknown';
      }

      report.writeln('Model migration status: $migrationStatus');
      report.writeln('');

      // Custom lists
      final lists = await db.getAllCustomLists();
      report.writeln('Found ${lists.length} custom lists.');

      // Ratings
      final ratingsQuery = await db.database.then((d) => d.query('ratings'));
      final ratedAlbums =
          ratingsQuery.map((r) => r['album_id'].toString()).toSet();
      report.writeln(
          'Found ${ratingsQuery.length} ratings for ${ratedAlbums.length} albums.');
      report.writeln('');

      // Platform matches
      final platformMatches =
          await db.database.then((d) => d.query('platform_matches'));
      report.writeln('Found ${platformMatches.length} platform matches.');

      // Check for iTunes/Apple Music duplicates
      final albumsWithDuplicates = <String>[];
      for (final albumId in ratedAlbums) {
        final matches =
            platformMatches.where((m) => m['album_id'] == albumId).toList();
        bool hasiTunes = false;
        bool hasAppleMusic = false;

        for (final match in matches) {
          final platform = match['platform'].toString();
          if (platform == 'itunes') hasiTunes = true;
          if (platform == 'apple_music') hasAppleMusic = true;
        }

        if (hasiTunes && hasAppleMusic) {
          albumsWithDuplicates.add(albumId);
        }
      }

      report.writeln(
          'Albums with iTunes/Apple Music duplicates: ${albumsWithDuplicates.length}');
      report.writeln('');

      // Database stats
      report.writeln('Database statistics:');
      final dbSize = await db.getDatabaseSize();
      report.writeln(
          'Database size: ${(dbSize / 1024 / 1024).toStringAsFixed(2)} MB');

      final integrityCheckResult = await db.checkDatabaseIntegrity();
      report.writeln(
          'Database integrity check: ${integrityCheckResult ? "PASSED" : "FAILED"}');
      report.writeln('');
    } catch (e, stack) {
      report.writeln('Error gathering data: $e');
      report.writeln(stack);
    }

    // System information
    report.writeln('System information:');
    report.writeln(
        'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    report.writeln('Dart version: ${Platform.version}');

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      report.writeln(
          'App version: ${packageInfo.version} (build ${packageInfo.buildNumber})');
    } catch (e) {
      report.writeln('App version: Unknown');
    }

    return report.toString();
  }

  /// Perform a complete database cleanup
  static Future<String> performDatabaseCleanup() async {
    final StringBuffer result = StringBuffer();
    result.writeln('=== RateMe Database Cleanup Report ===');

    try {
      // 1. Run platform matches cleanup
      result.writeln('Cleaning up platform matches...');
      final removedMatches = await CleanupUtility.cleanupPlatformMatches();
      result.writeln('- Removed $removedMatches duplicate platform matches');

      // 2. Run track ID cleanup
      result.writeln('Cleaning up track IDs...');
      final removedTracks =
          await CleanupUtility.removeNumericIdTracksIfStringIdExists();
      result.writeln('- Removed $removedTracks numeric-ID tracks');

      // 3. Fix Bandcamp tracks
      result.writeln('Fixing Bandcamp track IDs...');
      await CleanupUtility.fixBandcampTrackIds();

      // 4. Fix .0 issues in all database tables
      result.writeln('Fixing .0 issues in all database tables...');
      await CleanupUtility.fixDotZeroIssues();

      // 5. Vacuum database
      result.writeln('Vacuuming database...');
      await DatabaseHelper.instance.vacuumDatabase();

      result.writeln('\nCleanup completed successfully!');
    } catch (e, stack) {
      result.writeln('Error during cleanup: $e');
      result.writeln(stack);
    }

    return result.toString();
  }

  /// Show a debug report in a dialog
  static void showDebugReport(BuildContext context) async {
    final reportFuture = generateReport();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Debug Report'),
        content: FutureBuilder<String>(
          future: reportFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return SingleChildScrollView(
              child: SelectableText(
                snapshot.data ?? 'Error generating debug report',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              // Instead of capturing context and creating a local function,
              // use a non-async handler that stores the context in a local variable
              final currentContext = dialogContext;

              // Then use the Future's .then() approach which doesn't create an async gap
              reportFuture.then((report) {
                if (currentContext.mounted) {
                  Clipboard.setData(ClipboardData(text: report));
                  ScaffoldMessenger.of(currentContext).showSnackBar(
                    const SnackBar(
                        content: Text('Debug report copied to clipboard')),
                  );
                }
              });
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }
}
