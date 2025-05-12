import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rateme/database/database_helper.dart';
import 'package:rateme/database/cleanup_utility.dart';
import 'package:rateme/database/json_fixer.dart';
import 'package:rateme/core/services/logging.dart';
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
      // 1. Run the database JSON fixer
      result.writeln('Fixing invalid JSON in albums...');
      await JsonFixer.fixAlbumDataFields();

      // 2. Fix .0 issues in IDs
      result.writeln('Fixing .0 issues in IDs...');
      await JsonFixer.ultimateFixIdsEverywhere();

      // 3. Run platform matches cleanup
      result.writeln('Cleaning up platform matches...');
      final removedMatches = await CleanupUtility.cleanupPlatformMatches();
      result.writeln('- Removed $removedMatches duplicate platform matches');

      // 4. Run track ID cleanup
      result.writeln('Cleaning up track IDs...');
      final removedTracks =
          await CleanupUtility.removeNumericIdTracksIfStringIdExists();
      result.writeln('- Removed $removedTracks numeric-ID tracks');

      // 5. Fix Bandcamp tracks
      result.writeln('Fixing Bandcamp track IDs...');
      await CleanupUtility.fixBandcampTrackIds();

      // 6. Fix .0 issues in all database tables
      result.writeln('Fixing .0 issues in all database tables...');
      await CleanupUtility.fixDotZeroIssues();

      // 7. Vacuum database
      result.writeln('Vacuuming database...');
      await DatabaseHelper.instance.vacuumDatabase();

      // 8. Upgrade album formats to new format
      result.writeln('Upgrading album formats to new format...');
      final migratedAlbums = await _migrateAlbumFormats();
      result.writeln('- Migrated $migratedAlbums albums to new format');

      result.writeln('\nCleanup completed successfully!');
    } catch (e, stack) {
      result.writeln('Error during cleanup: $e');
      result.writeln(stack);
    }

    return result.toString();
  }

  /// Migrate all albums from legacy format to new format
  /// Returns the number of albums migrated
  static Future<int> _migrateAlbumFormats() async {
    final db = await DatabaseHelper.instance.database;
    final albums = await db.query('albums');
    int migrated = 0;

    for (final album in albums) {
      final albumId = album['id'].toString();
      final data = album['data'] as String?;

      if (data == null || data.isEmpty) continue;

      try {
        final json = jsonDecode(data);

        // Skip if already in new format
        if (json.containsKey('format_version') && json['format_version'] == 2) {
          continue;
        }

        // Convert to new format
        final newFormatJson = _convertToNewFormat(json, album);

        // Save back to database
        await db.update(
          'albums',
          {'data': jsonEncode(newFormatJson)},
          where: 'id = ?',
          whereArgs: [albumId],
        );

        migrated++;
      } catch (e) {
        Logging.severe('Error migrating album $albumId to new format: $e');
      }
    }

    return migrated;
  }

  /// Migrate all albums from legacy format to new format
  /// Returns the number of albums migrated
  static Future<int> migrateAlbumFormats() async {
    final db = await DatabaseHelper.instance.database;
    final albums = await db.query('albums');
    int migrated = 0;

    for (final album in albums) {
      final albumId = album['id'].toString();
      final data = album['data'] as String?;

      if (data == null || data.isEmpty) continue;

      try {
        final json = jsonDecode(data);

        // Skip if already in new format
        if (json.containsKey('format_version') && json['format_version'] == 2) {
          continue;
        }

        // Convert to new format
        final newFormatJson = _convertToNewFormat(json, album);

        // Save back to database
        await db.update(
          'albums',
          {'data': jsonEncode(newFormatJson)},
          where: 'id = ?',
          whereArgs: [albumId],
        );

        migrated++;

        if (migrated % 10 == 0) {
          Logging.severe('Migrated $migrated albums to new format...');
        }
      } catch (e) {
        Logging.severe('Error migrating album $albumId to new format: $e');
      }
    }

    Logging.severe(
        'Album format migration complete: $migrated albums migrated');
    return migrated;
  }

  /// Convert legacy format album data to new format
  static Map<String, dynamic> _convertToNewFormat(
      Map<String, dynamic> legacyJson, Map<String, dynamic> albumRow) {
    // Create a new format JSON
    final newFormat = <String, dynamic>{
      // Set the format version to indicate this is new format
      'format_version': 2,
      // Creation timestamp
      'created_at': DateTime.now().toIso8601String(),
      // Last updated timestamp
      'updated_at': DateTime.now().toIso8601String(),
    };

    // Copy essential fields from legacy format
    _copyIfExists(legacyJson, newFormat, 'id');
    _copyIfExists(legacyJson, newFormat, 'collectionId');
    _copyIfExists(legacyJson, newFormat, 'name');
    _copyIfExists(legacyJson, newFormat, 'collectionName');
    _copyIfExists(legacyJson, newFormat, 'artist');
    _copyIfExists(legacyJson, newFormat, 'artistName');
    _copyIfExists(legacyJson, newFormat, 'artworkUrl');
    _copyIfExists(legacyJson, newFormat, 'artworkUrl100');
    _copyIfExists(legacyJson, newFormat, 'releaseDate');
    _copyIfExists(legacyJson, newFormat, 'url');
    _copyIfExists(legacyJson, newFormat, 'platform');

    // Add metadata section for any additional fields in legacy format
    final metadata = <String, dynamic>{};
    legacyJson.forEach((key, value) {
      if (!newFormat.containsKey(key) && key != 'tracks') {
        metadata[key] = value;
      }
    });

    if (metadata.isNotEmpty) {
      newFormat['metadata'] = metadata;
    }

    // Copy tracks with minimal required fields
    if (legacyJson.containsKey('tracks') && legacyJson['tracks'] is List) {
      final legacyTracks = legacyJson['tracks'] as List;
      final newTracks = <Map<String, dynamic>>[];

      for (final track in legacyTracks) {
        if (track is Map) {
          final newTrack = <String, dynamic>{};

          // Copy essential track fields
          _copyIfExists(track, newTrack, 'trackId');
          _copyIfExists(track, newTrack, 'trackName');
          _copyIfExists(track, newTrack, 'trackNumber');
          _copyIfExists(track, newTrack, 'trackTimeMillis');

          // Add track metadata section
          final trackMetadata = <String, dynamic>{};
          track.forEach((key, value) {
            if (!newTrack.containsKey(key)) {
              trackMetadata[key] = value;
            }
          });

          if (trackMetadata.isNotEmpty) {
            newTrack['metadata'] = trackMetadata;
          }

          newTracks.add(newTrack);
        }
      }

      if (newTracks.isNotEmpty) {
        newFormat['tracks'] = newTracks;
      }
    }

    return newFormat;
  }

  /// Helper to copy a field from source to target if it exists
  static void _copyIfExists(Map source, Map target, String key) {
    if (source.containsKey(key) && source[key] != null) {
      target[key] = source[key];
    }
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
