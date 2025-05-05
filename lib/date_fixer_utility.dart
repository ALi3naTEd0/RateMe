import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'database/database_helper.dart';
import 'logging.dart';
import 'platforms/platform_service_factory.dart';

/// Utility to fix missing or incorrect album release dates in the database
class DateFixerUtility {
  /// Fix missing or placeholder release dates for all albums or specific platforms
  static Future<FixerResults> fixDates({
    bool onlyDeezer = true,
    bool onlyMissingDates = true,
    Function(String message, double progress)? progressCallback,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final results = FixerResults();

    try {
      // Step 1: Get albums with missing or placeholder dates
      progressCallback?.call('Finding albums that need date fixes...', 0.1);

      final List<Map<String, dynamic>> albums;

      if (onlyDeezer) {
        // Only get Deezer albums
        albums = await db.query(
          'albums',
          where: 'platform = ?',
          whereArgs: ['deezer'],
        );
        Logging.severe('Found ${albums.length} Deezer albums to check');
      } else {
        // Get all albums
        albums = await db.query('albums');
        Logging.severe('Found ${albums.length} total albums to check');
      }

      if (albums.isEmpty) {
        progressCallback?.call('No albums found to process', 1.0);
        return results;
      }

      // Step 2: Process each album
      int totalAlbums = albums.length;
      int processedCount = 0;

      for (final album in albums) {
        try {
          final albumId = album['id'];
          final albumName = album['name'];

          // Calculate progress
          final progress = 0.1 + (0.9 * (processedCount / totalAlbums));
          progressCallback?.call(
              'Processing ($processedCount/$totalAlbums): $albumName',
              progress);

          // Check if release date needs fixing
          final needsFix = _needsDateFix(album);
          if (onlyMissingDates && !needsFix) {
            Logging.severe('Album $albumId has valid date, skipping');
            processedCount++;
            results.skipped++;
            continue;
          }

          // Check platform
          final platform =
              album['platform']?.toString().toLowerCase() ?? 'unknown';
          if (platform == 'deezer') {
            results.attempted++;
            final success = await _fixDeezerDate(album);
            if (success) results.fixed++;
          } else if (!onlyDeezer) {
            results.attempted++;
            final success = await _fixGenericDate(album);
            if (success) results.fixed++;
          } else {
            results.skipped++;
          }

          processedCount++;
        } catch (e, stack) {
          Logging.severe('Error processing album', e, stack);
          results.failed++;
        }
      }

      progressCallback?.call(
          'Finished processing ${results.fixed} albums', 1.0);
      return results;
    } catch (e, stack) {
      Logging.severe('Error in date fixer', e, stack);
      progressCallback?.call('Error: $e', 1.0);
      return results;
    }
  }

  /// Run the date fixer with a UI dialog showing progress
  static Future<FixerResults> runWithDialog(
    BuildContext context, {
    bool onlyDeezer = true,
    bool onlyMissingDates = true,
  }) async {
    final results = await showDialog<FixerResults>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _DateFixerDialog(
          onlyDeezer: onlyDeezer,
          onlyMissingDates: onlyMissingDates,
        );
      },
    );

    return results ?? FixerResults();
  }

  /// Check if an album needs a date fix
  static bool _needsDateFix(Map<String, dynamic> album) {
    // Check direct fields first
    String? releaseDateStr = album['release_date']?.toString();
    if (releaseDateStr == null || releaseDateStr.isEmpty) {
      releaseDateStr = album['releaseDate']?.toString();
    }

    // If no direct field, check data JSON
    if ((releaseDateStr == null || releaseDateStr.isEmpty) &&
        album['data'] != null &&
        album['data'] is String) {
      try {
        final dataJson = jsonDecode(album['data'] as String);
        if (dataJson is Map<String, dynamic>) {
          releaseDateStr = dataJson['releaseDate']?.toString() ??
              dataJson['release_date']?.toString();
        }
      } catch (e) {
        // Ignore JSON errors
      }
    }

    // If still no date, it needs fixing
    if (releaseDateStr == null || releaseDateStr.isEmpty) {
      return true;
    }

    // Check for placeholder date (Jan 1, 2000)
    try {
      final date = DateTime.parse(releaseDateStr);
      if (date.year == 2000 && date.month == 1 && date.day == 1) {
        return true;
      }
    } catch (e) {
      // If we can't parse it, it's likely invalid
      return true;
    }

    return false;
  }

  /// Fix date for Deezer album using DeezerMiddleware
  static Future<bool> _fixDeezerDate(Map<String, dynamic> album) async {
    try {
      final albumId = album['id'];
      final albumName = album['name'];

      Logging.severe('Fixing Deezer date for album $albumId: $albumName');

      // Extract the Deezer ID from the URL or use the album ID
      String? deezerId;
      final url = album['url']?.toString() ?? '';

      if (url.contains('deezer.com/album/')) {
        // Extract ID from URL
        final regex = RegExp(r'album/(\d+)');
        final match = regex.firstMatch(url);
        if (match != null && match.groupCount >= 1) {
          deezerId = match.group(1);
        }
      }

      // Fall back to album ID if URL extraction failed
      deezerId ??= albumId.toString();

      // Create a URI for the Deezer API
      final apiUrl = Uri.parse('https://api.deezer.com/album/$deezerId');

      // Make a direct HTTP request instead of using the private method
      final response = await http.get(apiUrl);

      if (response.statusCode != 200) {
        Logging.severe(
            'Failed to fetch Deezer album data: ${response.statusCode}');
        return false;
      }

      // Parse the response
      final data = jsonDecode(response.body);

      // Extract the release date
      if (data['release_date'] == null) {
        Logging.severe('No release date found in Deezer API response');
        return false;
      }

      final releaseDateStr = data['release_date'].toString();

      // Format the date in ISO format
      String formattedDate;
      try {
        final date = DateTime.parse(releaseDateStr);
        formattedDate = date.toIso8601String();
      } catch (e) {
        formattedDate = releaseDateStr;
      }

      Logging.severe('Got release date for album $albumId: $formattedDate');

      // Update the album in the database
      return _updateDateInDatabase(album, formattedDate);
    } catch (e, stack) {
      Logging.severe('Error fixing Deezer date', e, stack);
      return false;
    }
  }

  /// Fix date for non-Deezer album using platform-specific services
  static Future<bool> _fixGenericDate(Map<String, dynamic> album) async {
    try {
      final albumId = album['id'];
      final albumName = album['name'];
      final platform = album['platform']?.toString().toLowerCase() ?? 'unknown';
      final url = album['url']?.toString() ?? '';

      Logging.severe('Fixing date for $platform album $albumId: $albumName');

      if (url.isEmpty) {
        Logging.severe('No URL available for album $albumId');
        return false;
      }

      // Use platform service factory to get the right service
      final factory = PlatformServiceFactory();
      if (!factory.isPlatformSupported(platform)) {
        Logging.severe('Platform $platform not supported for date fixing');
        return false;
      }

      final service = factory.getService(platform);
      final details = await service.fetchAlbumDetails(url);

      if (details == null) {
        Logging.severe('Failed to fetch details for $platform album $albumId');
        return false;
      }

      // Extract the release date
      String? releaseDateStr = details['releaseDate']?.toString();
      if (releaseDateStr == null || releaseDateStr.isEmpty) {
        Logging.severe('No release date found in fetched details');
        return false;
      }

      // Format the date in ISO format
      String formattedDate;
      try {
        final date = DateTime.parse(releaseDateStr);
        formattedDate = date.toIso8601String();
      } catch (e) {
        formattedDate = releaseDateStr;
      }

      Logging.severe('Got date for album $albumId: $formattedDate');

      // Update the album in the database
      return _updateDateInDatabase(album, formattedDate);
    } catch (e, stack) {
      Logging.severe('Error fixing generic date', e, stack);
      return false;
    }
  }

  /// Update both the release_date column and data JSON with the new date
  static Future<bool> _updateDateInDatabase(
      Map<String, dynamic> album, String formattedDate) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final albumId = album['id'];

      // 1. Update the release_date column directly
      await db.update(
        'albums',
        {'release_date': formattedDate},
        where: 'id = ?',
        whereArgs: [albumId],
      );

      // 2. Update the data JSON to include the date
      if (album['data'] != null && album['data'] is String) {
        try {
          Map<String, dynamic> dataJson;
          try {
            dataJson = Map<String, dynamic>.from(jsonDecode(album['data']));
          } catch (e) {
            // If parsing fails, create a new data object
            dataJson = {};
          }

          // Update the dates in both formats
          dataJson['releaseDate'] = formattedDate;
          dataJson['release_date'] = formattedDate;

          // Save the updated JSON back to the database
          await db.update(
            'albums',
            {'data': jsonEncode(dataJson)},
            where: 'id = ?',
            whereArgs: [albumId],
          );
        } catch (e) {
          Logging.severe('Error updating data JSON', e);
          // Continue anyway since we've updated the column
        }
      }

      // 3. Verify the update was successful
      final updated = await db.query(
        'albums',
        columns: ['release_date'],
        where: 'id = ?',
        whereArgs: [albumId],
      );

      if (updated.isNotEmpty &&
          updated[0]['release_date']?.toString() == formattedDate) {
        Logging.severe('Successfully updated date for album $albumId');
        return true;
      } else {
        Logging.severe('Failed to verify date update for album $albumId');
        return false;
      }
    } catch (e, stack) {
      Logging.severe('Error updating date in database', e, stack);
      return false;
    }
  }
}

/// Dialog to show progress of the date fixing operation
class _DateFixerDialog extends StatefulWidget {
  final bool onlyDeezer;
  final bool onlyMissingDates;

  const _DateFixerDialog({
    required this.onlyDeezer,
    required this.onlyMissingDates,
  });

  @override
  State<_DateFixerDialog> createState() => _DateFixerDialogState();
}

class _DateFixerDialogState extends State<_DateFixerDialog> {
  String _message = 'Starting date fixer...';
  double _progress = 0.0;
  FixerResults? _results;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _startFixer();
  }

  Future<void> _startFixer() async {
    final results = await DateFixerUtility.fixDates(
      onlyDeezer: widget.onlyDeezer,
      onlyMissingDates: widget.onlyMissingDates,
      progressCallback: (message, progress) {
        if (mounted) {
          setState(() {
            _message = message;
            _progress = progress;
            if (progress >= 0.99) _isComplete = true;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _results = results;
        _isComplete = true;
        _message =
            'Fixed ${results.fixed} albums (${results.attempted} attempted)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isComplete ? 'Date Fix Complete' : 'Fixing Album Dates'),
      content: SizedBox(
        width: 300,
        height: 150,
        child: Column(
          mainAxisSize: MainAxisSize.min, // Make sure this is min
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(_message),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 16),
            if (_results != null)
              // Wrap this in a Flexible or Expanded widget to prevent overflow
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min, // Make sure this is min
                    children: [
                      Text(
                          'Albums processed: ${_results!.attempted + _results!.skipped}'),
                      Text('Albums fixed: ${_results!.fixed}'),
                      Text('Albums failed: ${_results!.failed}'),
                      Text('Albums skipped: ${_results!.skipped}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isComplete ? () => Navigator.of(context).pop(_results) : null,
          child: Text(_isComplete ? 'Close' : 'Working...'),
        ),
      ],
    );
  }
}

/// Results of the date fixing operation
class FixerResults {
  int attempted = 0; // Number of albums we tried to fix
  int fixed = 0; // Successfully fixed
  int failed = 0; // Failed to fix
  int skipped = 0; // Skipped (already had dates)

  @override
  String toString() {
    return 'FixerResults: $fixed fixed, $failed failed, $skipped skipped (of $attempted attempted)';
  }
}
