import 'package:flutter/material.dart';
import '../../core/models/album_model.dart';
import '../../database/database_helper.dart';
import '../../core/services/logging.dart';
import '../../platforms/platform_service_factory.dart';
import '../../core/services/theme_service.dart';
import 'package:sqflite/sqflite.dart';

/// A utility class to clean and refresh platform matches in the database
class PlatformMatchCleaner {
  final _platformFactory = PlatformServiceFactory();

  /// Clean all platform matches in the database
  Future<int> cleanAllPlatformMatches({bool dryRun = true}) async {
    final db = await DatabaseHelper.instance.database;
    int updatedCount = 0;

    // Get all unique albums that have platform matches
    final results = await db.rawQuery('''
      SELECT DISTINCT album_id 
      FROM platform_matches 
      ORDER BY album_id
    ''');

    final albumIds = results.map((row) => row['album_id'] as String).toList();
    Logging.severe(
        'Found ${albumIds.length} albums with platform matches to verify');

    // For each album, get all its platform matches
    for (final albumId in albumIds) {
      try {
        final albumMatches = await db.query(
          'platform_matches',
          where: 'album_id = ?',
          whereArgs: [albumId],
        );

        if (albumMatches.isEmpty) continue;

        // Get the album details to check matches
        final albumDetails = await _getAlbumDetailsFromId(albumId);
        if (albumDetails == null) {
          Logging.severe('Cannot find album with ID: $albumId - skipping');
          continue;
        }

        Logging.severe(
            'Checking platform matches for album: ${albumDetails.name} by ${albumDetails.artist}');

        // Clean artist name if it has Discogs numbering
        final String cleanedArtist =
            albumDetails.artist.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '');

        // Check each platform match
        for (final match in albumMatches) {
          final platform = match['platform'] as String;
          final url = match['url'] as String?;

          if (url == null || url.isEmpty) continue;

          // Skip the album's own platform as source of truth
          if (platform == albumDetails.platform) continue;

          // Verify the match quality
          if (_platformFactory.isPlatformSupported(platform)) {
            final service = _platformFactory.getService(platform);

            try {
              // Fetch album details to verify match
              final details = await service.fetchAlbumDetails(url);

              if (details != null) {
                final matchArtist = details['artistName'] ?? '';
                final matchAlbum = details['collectionName'] ?? '';

                // Clean the match artist name too
                final cleanedMatchArtist =
                    matchArtist.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '');

                // Calculate similarity
                final artistScore = _calculateStringSimilarity(
                    _normalizeForComparison(cleanedArtist),
                    _normalizeForComparison(cleanedMatchArtist));

                final albumScore = _calculateStringSimilarity(
                    _normalizeForComparison(albumDetails.name),
                    _normalizeForComparison(matchAlbum));

                final combinedScore = (artistScore * 0.6) + (albumScore * 0.4);

                Logging.severe(
                    'Platform $platform match quality: artist=$artistScore, album=$albumScore, combined=$combinedScore');

                // If poor match, try to find a better one
                if (combinedScore < 0.5) {
                  Logging.severe(
                      'Poor match detected for $platform. Will search for better match.');

                  if (!dryRun) {
                    // Remove the bad match
                    await db.delete(
                      'platform_matches',
                      where: 'album_id = ? AND platform = ?',
                      whereArgs: [albumId, platform],
                    );

                    // Try to find a better match
                    final newUrl = await service.findAlbumUrl(
                        cleanedArtist, albumDetails.name);
                    if (newUrl != null) {
                      // Save the new match
                      await db.insert(
                        'platform_matches',
                        {
                          'album_id': albumId,
                          'platform': platform,
                          'url': newUrl,
                          'verified': 1,
                          'timestamp': DateTime.now().toIso8601String(),
                        },
                        conflictAlgorithm: ConflictAlgorithm.replace,
                      );
                      updatedCount++;
                      Logging.severe(
                          'Updated platform match for $platform: $newUrl');
                    }
                  } else {
                    Logging.severe(
                        'DRY RUN: Would update platform match for $platform');
                    updatedCount++;
                  }
                } else {
                  Logging.severe(
                      'Match quality is acceptable, keeping current URL');
                }
              }
            } catch (e) {
              Logging.severe(
                  'Error verifying match for platform $platform: $e');
            }
          }
        }
      } catch (e) {
        Logging.severe('Error processing album ID $albumId: $e');
      }
    }

    Logging.severe(
        'Platform match cleaning completed. Updated $updatedCount matches.');
    return updatedCount;
  }

  /// Get album details from album ID
  Future<Album?> _getAlbumDetailsFromId(String albumId) async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Get the album from database
      final results = await db.query(
        'albums',
        where: 'id = ?',
        whereArgs: [albumId],
      );

      if (results.isEmpty) return null;

      // Create album object
      return Album.fromJson(results.first);
    } catch (e) {
      Logging.severe('Error getting album details: $e');
      return null;
    }
  }

  /// Calculate string similarity (copy from platform_service_base.dart)
  double _calculateStringSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;

    final service = _platformFactory.getService('spotify');
    return service.calculateStringSimilarity(s1, s2);
  }

  /// Normalize for comparison (copy from platform_service_base.dart)
  String _normalizeForComparison(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove special chars
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }
}

/// A widget to run and display platform match cleaning
class PlatformMatchCleanerWidget extends StatefulWidget {
  const PlatformMatchCleanerWidget({super.key});

  @override
  State<PlatformMatchCleanerWidget> createState() =>
      _PlatformMatchCleanerWidgetState();
}

class _PlatformMatchCleanerWidgetState
    extends State<PlatformMatchCleanerWidget> {
  bool _isCleaning = false;
  int _cleanedCount = 0;
  bool _dryRun = true;
  String _status = 'Ready to clean platform matches';

  @override
  Widget build(BuildContext context) {
    final pageWidth =
        MediaQuery.of(context).size.width * ThemeService.contentMaxWidthFactor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Match Cleaner'),
        leadingWidth: (MediaQuery.of(context).size.width - pageWidth) / 2 + 48,
        leading: Padding(
          padding: EdgeInsets.only(
              left: (MediaQuery.of(context).size.width - pageWidth) / 2),
          child: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: Center(
        child: SizedBox(
          width: pageWidth,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  'Clean and refresh platform matches',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Dry Run (preview only)'),
                  subtitle:
                      const Text('Check for issues without making changes'),
                  value: _dryRun,
                  onChanged: _isCleaning
                      ? null
                      : (value) {
                          setState(() {
                            _dryRun = value;
                          });
                        },
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isCleaning ? null : _cleanMatches,
                  child: Text(_dryRun ? 'Run Analysis' : 'Clean All Matches'),
                ),
                const SizedBox(height: 24),
                _isCleaning
                    ? const CircularProgressIndicator()
                    : Text(
                        _status,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                if (_cleanedCount > 0) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Found $_cleanedCount matches that need updating',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cleanMatches() async {
    setState(() {
      _isCleaning = true;
      _status = 'Cleaning platform matches...';
    });

    try {
      final cleaner = PlatformMatchCleaner();
      final count = await cleaner.cleanAllPlatformMatches(dryRun: _dryRun);

      setState(() {
        _cleanedCount = count;
        _status = _dryRun
            ? 'Analysis complete! $_cleanedCount matches need updating.'
            : 'Cleaning complete! Updated $_cleanedCount matches.';
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      setState(() {
        _isCleaning = false;
      });
    }
  }
}
