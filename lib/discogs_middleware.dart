import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'logging.dart';
import 'api_keys.dart';
import 'details_page.dart';
import 'dart:math' as math;

/// Middleware for Discogs albums that handles fetching accurate release dates
/// and track information before displaying the album details
class DiscogsMiddleware {
  /// Show a loading screen while fetching accurate album data,
  /// then navigate to the details page when complete
  static Future<void> showDetailPageWithPreload(
      BuildContext context, Map<String, dynamic> album,
      {Map<int, double>? initialRatings}) async {
    // Store mounted state before async operations
    final navigatorState = Navigator.of(context);

    // First show a loading dialog with shorter timeout
    showDialog(
      context: context,
      barrierDismissible: true, // Allow user to dismiss if taking too long
      builder: (ctx) => _buildLoadingDialog(ctx, album),
    );

    Logging.severe(
        'Starting Discogs album enhancement for: ${album['collectionName'] ?? album['name']}');

    try {
      // Fetch enhanced data
      final enhancedAlbum = await _enhanceDiscogsAlbum(album);

      // Close loading dialog - using stored navigator state instead of context
      navigatorState.pop();

      // Show the details page with enhanced data - check if still mounted
      if (context.mounted) {
        navigatorState.push(
          MaterialPageRoute(
            builder: (context) => DetailsPage(
              album: enhancedAlbum,
              initialRatings: initialRatings,
            ),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog on error - using stored navigator state instead of context
      navigatorState.pop();

      // Show details page with original data - check if still mounted
      if (context.mounted) {
        navigatorState.push(
          MaterialPageRoute(
            builder: (context) => DetailsPage(
              album: album,
              initialRatings: initialRatings,
            ),
          ),
        );
      }
    }
  }

  /// Loading dialog UI
  static Widget _buildLoadingDialog(
      BuildContext context, Map<String, dynamic> album) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text(
              'Fetching album details...',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              album['collectionName'] ?? album['name'] ?? 'Unknown Album',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              album['artistName'] ?? album['artist'] ?? 'Unknown Artist',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  /// Enhances a Discogs album with accurate information
  static Future<Map<String, dynamic>> _enhanceDiscogsAlbum(
      Map<String, dynamic> album) async {
    try {
      final result = Map<String, dynamic>.from(album);

      // Extract the ID and type from the URL
      final url = album['url'].toString();
      final RegExp regExp = RegExp(r'/(master|release)/(\d+)');
      final match = regExp.firstMatch(url);

      if (match == null || match.groupCount < 2) {
        Logging.severe('Could not extract ID from Discogs URL: $url');
        return result;
      }

      final type = match.group(1) ?? album['type'] ?? 'release';
      final id = match.group(2) ?? album['collectionId']?.toString();

      if (id == null) {
        Logging.severe('No ID found for Discogs album');
        return result;
      }

      Logging.severe('Enhancing Discogs $type (ID: $id)');

      // Get credentials
      final credentials = await _getDiscogsCredentials();
      if (credentials == null) {
        Logging.severe('Discogs API credentials not available');
        return result;
      }

      // Get primary album data
      final apiUrl =
          'https://api.discogs.com/${type}s/$id?key=${credentials['key']}&secret=${credentials['secret']}';

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'User-Agent': 'RateMe/1.0'},
      );

      if (response.statusCode != 200) {
        Logging.severe('Discogs API error: ${response.statusCode}');
        return result;
      }

      final data = jsonDecode(response.body);

      // 1. Update artist name
      if (data['artists'] != null &&
          data['artists'] is List &&
          data['artists'].isNotEmpty) {
        final artistNames = (data['artists'] as List)
            .where((a) => a['name'] != null)
            .map((a) => a['name'].toString())
            .toList();

        if (artistNames.isNotEmpty) {
          result['artist'] = artistNames.join(', ');
          result['artistName'] = artistNames.join(', ');
        }
      } else if (data['artists_sort'] != null) {
        result['artist'] = data['artists_sort'];
        result['artistName'] = data['artists_sort'];
      }

      // 2. Update album title
      if (data['title'] != null && data['title'].toString().isNotEmpty) {
        result['name'] = data['title'];
        result['collectionName'] = data['title'];
      }

      // 3. Update artwork URL
      if (data['images'] != null &&
          data['images'] is List &&
          data['images'].isNotEmpty) {
        final primaryImage = (data['images'] as List).firstWhere(
          (img) => img['type'] == 'primary',
          orElse: () => (data['images'] as List).first,
        );

        if (primaryImage['uri'] != null) {
          result['artworkUrl100'] = primaryImage['uri'];
          result['artworkUrl'] = primaryImage['uri'];
        }
      }

      // 4. Update release date with direct approach - IMPROVED DATE EXTRACTION
      String? bestReleaseDate;
      int bestDateQuality = 0;

      // If main record has a date, evaluate its quality
      if (data['released'] != null &&
          data['released'].toString().trim().isNotEmpty) {
        final releasedStr = data['released'].toString().trim();
        bestReleaseDate =
            _processDiscogsDate(releasedStr, data['year']?.toString());

        // Rate the quality of this date
        if (releasedStr.length >= 10 && releasedStr.contains('-')) {
          bestDateQuality = 3; // Full YYYY-MM-DD format is best
        } else if (releasedStr.length >= 7 && releasedStr.contains('-')) {
          bestDateQuality = 2; // YYYY-MM format is good
        } else if (RegExp(r'^\d{4}$').hasMatch(releasedStr)) {
          bestDateQuality = 1; // Year only is basic
        }

        Logging.severe(
            'Main record release date: $bestReleaseDate (quality: $bestDateQuality)');
      }
      // If we only have year, use that as fallback
      else if (data['year'] != null && bestDateQuality == 0) {
        bestReleaseDate = '${data['year']}-01-01';
        bestDateQuality = 1;
        Logging.severe(
            'Using year from main record: $bestReleaseDate (quality: $bestDateQuality)');
      }

      // Set initial releaseDate in result
      if (bestReleaseDate != null) {
        result['releaseDate'] = bestReleaseDate;
      }

      // 5. Process tracks and potentially find better release dates
      Map<String, dynamic>? releaseDateInfo;
      try {
        releaseDateInfo = await _processTrackInformation(result, data, type, id,
            credentials['key']!, credentials['secret']!);
      } catch (e, stack) {
        // Better error handling - log the error but continue with what we have
        Logging.severe(
            'Error finding better release date - continuing with basic date',
            e,
            stack);
      }

      // Update release date if we found a better one during track processing
      if (releaseDateInfo != null &&
          releaseDateInfo['quality'] > bestDateQuality) {
        result['releaseDate'] = releaseDateInfo['date'];
        Logging.severe(
            'Updated to better release date from version: ${result['releaseDate']} (quality: ${releaseDateInfo['quality']})');
      }

      // Log the final release date being used
      Logging.severe('Final release date for album: ${result['releaseDate']}');

      return result;
    } catch (e, stack) {
      Logging.severe('Error enhancing Discogs album', e, stack);
      return album; // Return original album on error
    }
  }

  /// Process tracks from the main record and try to find ones with durations if needed
  /// Returns improved release date information if found
  static Future<Map<String, dynamic>?> _processTrackInformation(
    Map<String, dynamic> album,
    Map<String, dynamic> data,
    String type,
    String id,
    String consumerKey,
    String consumerSecret,
  ) async {
    try {
      List<Map<String, dynamic>> tracks = [];
      // Best date info found from versions: {date: string, quality: int}
      Map<String, dynamic>? bestDateInfo;

      // First try the main record's tracklist
      if (data['tracklist'] != null && data['tracklist'] is List) {
        tracks = _extractTrackList(
            data['tracklist'], id, album['artistName'] ?? 'Unknown Artist');
      }

      // Check if we have durations
      final hasGoodTracks = _tracksHaveDurations(tracks);
      if (hasGoodTracks) {
        Logging.severe('Main record has good track durations');
      } else {
        Logging.severe(
            'Main record lacks track durations, will search for better versions');
      }

      // For masters, first try to get the most recent version with a proper date
      if (type == 'master') {
        try {
          final versionsDataInfo = await _findBestVersionWithDate(
              data['versions_url'], consumerKey, consumerSecret);

          if (versionsDataInfo != null) {
            // Update date information
            bestDateInfo = versionsDataInfo['dateInfo'];
            Logging.severe(
                'Found better date from versions: ${bestDateInfo?['date']} (quality: ${bestDateInfo?['quality']})');

            // Update tracks if the version has good track durations
            final versionTracks = versionsDataInfo['tracks'];
            final versionDurationPercentage =
                versionsDataInfo['trackDurationPercentage'] as double? ?? 0.0;

            if (versionTracks != null &&
                (!hasGoodTracks ||
                    versionDurationPercentage >
                        _calculateTrackDurationPercentage(tracks))) {
              Logging.severe(
                  'Found better tracks in version with ID: ${versionsDataInfo['id']} '
                  '(Duration coverage: ${(versionDurationPercentage * 100).toStringAsFixed(1)}%)');
              tracks = versionTracks;
            }
          }
        } catch (e, stack) {
          // Better error handling - log the error but continue with what we have
          Logging.severe(
              'Error while finding best version date - continuing with available data',
              e,
              stack);
        }
      }

      // If we still don't have good tracks, use previous approach as fallback
      if (!_tracksHaveDurations(tracks)) {
        Logging.severe(
            'Still need better track durations, checking alternatives');

        // If this is a release, check its master
        if (type == 'release' && data['master_id'] != null) {
          final masterId = data['master_id'].toString();
          Logging.severe('Checking master release: $masterId');

          final masterUrl = Uri.parse(
              'https://api.discogs.com/masters/$masterId?key=$consumerKey&secret=$consumerSecret');

          final masterResponse =
              await http.get(masterUrl, headers: {'User-Agent': 'RateMe/1.0'});

          if (masterResponse.statusCode == 200) {
            final masterData = jsonDecode(masterResponse.body);

            // Check if master has a better date
            if (masterData['released'] != null) {
              final masterDateInfo = _evaluateDate(
                  masterData['released'].toString(),
                  masterData['year']?.toString());
              if (bestDateInfo == null ||
                  masterDateInfo['quality'] > bestDateInfo['quality']) {
                bestDateInfo = masterDateInfo;
              }
            }

            if (masterData['tracklist'] != null) {
              final masterTracks = _extractTrackList(masterData['tracklist'],
                  masterId, album['artistName'] ?? 'Unknown Artist');

              if (_tracksHaveDurations(masterTracks)) {
                Logging.severe('Found better tracks in master record');
                tracks = masterTracks;
              }
            }
          }
        }
        // If this is a master and we didn't find a good version yet, check its first version
        else if (type == 'master' &&
            data['versions_url'] != null &&
            bestDateInfo == null) {
          final versionsUrl = Uri.parse(
              '${data['versions_url']}?per_page=1&key=$consumerKey&secret=$consumerSecret');

          final versionsResponse = await http
              .get(versionsUrl, headers: {'User-Agent': 'RateMe/1.0'});

          if (versionsResponse.statusCode == 200) {
            final versionsData = jsonDecode(versionsResponse.body);

            if (versionsData['versions'] != null &&
                versionsData['versions'] is List &&
                versionsData['versions'].isNotEmpty) {
              final version = versionsData['versions'][0];
              if (version['id'] != null) {
                final versionId = version['id'].toString();
                Logging.severe('Checking first version: $versionId');

                final versionUrl = Uri.parse(
                    'https://api.discogs.com/releases/$versionId?key=$consumerKey&secret=$consumerSecret');

                final versionResponse = await http
                    .get(versionUrl, headers: {'User-Agent': 'RateMe/1.0'});

                if (versionResponse.statusCode == 200) {
                  final versionData = jsonDecode(versionResponse.body);

                  // Check for better date in this version
                  if (versionData['released'] != null) {
                    final versionDateInfo = _evaluateDate(
                        versionData['released'].toString(),
                        versionData['year']?.toString());

                    if (bestDateInfo == null ||
                        versionDateInfo['quality'] > bestDateInfo['quality']) {
                      bestDateInfo = versionDateInfo;
                    }
                  }

                  if (versionData['tracklist'] != null) {
                    final versionTracks = _extractTrackList(
                        versionData['tracklist'],
                        versionId,
                        album['artistName'] ?? 'Unknown Artist');

                    if (_tracksHaveDurations(versionTracks)) {
                      Logging.severe('Found better tracks in version record');
                      tracks = versionTracks;
                    }
                  }
                }
              }
            }
          }
        }
      }

      // Add tracks to the album
      album['tracks'] = tracks;

      // Log the final track quality
      final finalDurationPercentage = _calculateTrackDurationPercentage(tracks);
      Logging.severe(
          'Final tracks have ${(finalDurationPercentage * 100).toStringAsFixed(1)}% duration coverage '
          '(${tracks.length} tracks total)');

      // Return date information if we found a better one
      return bestDateInfo;
    } catch (e, stack) {
      Logging.severe('Error processing track information', e, stack);
      return null;
    }
  }

  /// Find the best version with accurate date information
  static Future<Map<String, dynamic>?> _findBestVersionWithDate(
      String? versionsUrl, String consumerKey, String consumerSecret) async {
    if (versionsUrl == null) return null;

    try {
      Logging.severe(
          'Checking versions for accurate release dates at: $versionsUrl');

      // Reduce number of versions to check for faster loading (from 10 to 6)
      final url = Uri.parse(
          '$versionsUrl?per_page=6&key=$consumerKey&secret=$consumerSecret');
      final response =
          await http.get(url, headers: {'User-Agent': 'RateMe/1.0'});

      if (response.statusCode != 200) {
        Logging.severe('Failed to fetch versions: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data['versions'] is! List ||
          data['versions'] == null ||
          (data['versions'] as List).isEmpty) {
        Logging.severe('No versions found in response');
        return null;
      }

      // Log how many versions we found
      Logging.severe(
          'Found ${(data['versions'] as List).length} versions to check for dates');

      // Look for versions with complete dates
      Map<String, dynamic>? bestDateInfo;
      String? bestVersionId;
      Map<String, dynamic>? versionData;
      List<Map<String, dynamic>>?
          bestTrackList; // Add variable to store the best tracks
      double bestTrackDurationPercentage =
          0.0; // Track % of tracks with durations

      // Track all version dates for debugging
      List<Map<String, dynamic>> allVersionDates = [];

      // IMPROVED APPROACH: For each version, fetch the complete release data to get accurate dates
      // Set a limit to prevent too many API calls
      final maxVersionsToCheck = math.min(4, (data['versions'] as List).length);
      Logging.severe(
          'Will fetch full details for up to $maxVersionsToCheck versions');

      int versionsChecked = 0;
      for (final version in data['versions']) {
        try {
          if (version['id'] != null) {
            final versionId = version['id'].toString();
            String country = version['country']?.toString() ?? 'Unknown';

            // Fix the format handling to properly handle both string and list formats
            String format = 'Unknown';
            if (version['format'] != null) {
              if (version['format'] is List) {
                format = (version['format'] as List)
                    .map((f) => f.toString())
                    .join(', ');
              } else if (version['format'] is String) {
                format = version['format'].toString();
              } else {
                format = version['format'].toString();
              }
            }

            Logging.severe(
                'Fetching complete data for version $versionId ($country, $format)');

            // Get the complete release data to access accurate date information
            final versionUrl = Uri.parse(
                'https://api.discogs.com/releases/$versionId?key=$consumerKey&secret=$consumerSecret');

            final versionResponse = await http
                .get(versionUrl, headers: {'User-Agent': 'RateMe/1.0'});

            if (versionResponse.statusCode != 200) {
              Logging.severe(
                  'Failed to fetch version $versionId: ${versionResponse.statusCode}');
              continue;
            }

            // Parse the full version data
            final fullVersionData = jsonDecode(versionResponse.body);

            // Extract the release date from the full data
            final releasedStr =
                fullVersionData['released']?.toString().trim() ?? '';
            Logging.severe(
                'Full version $versionId release date: "$releasedStr"');

            // Evaluate the date quality
            final dateInfo =
                _evaluateDate(releasedStr, fullVersionData['year']?.toString());

            // Process tracks to check for durations
            List<Map<String, dynamic>>? versionTracks;
            double trackDurationPercentage = 0.0;
            if (fullVersionData['tracklist'] != null) {
              final artistName = fullVersionData['artists'] != null &&
                      fullVersionData['artists'] is List &&
                      fullVersionData['artists'].isNotEmpty
                  ? fullVersionData['artists'][0]['name'].toString()
                  : 'Unknown Artist';

              versionTracks = _extractTrackList(
                  fullVersionData['tracklist'], versionId, artistName);

              // Calculate percentage of tracks with durations
              trackDurationPercentage =
                  _calculateTrackDurationPercentage(versionTracks);
              Logging.severe(
                  'Version $versionId track duration coverage: ${(trackDurationPercentage * 100).toStringAsFixed(1)}% of ${versionTracks.length} tracks');
            }

            // Add to our tracking list
            allVersionDates.add({
              'id': versionId,
              'date': dateInfo['date'],
              'quality': dateInfo['quality'],
              'original': dateInfo['original'],
              'country': country,
              'format': format,
              'durationPercentage': trackDurationPercentage,
              'trackCount': versionTracks?.length ?? 0
            });

            // Decide whether this is the best version based on date quality AND track durations
            bool isBetter = false;

            // If no best version yet, use this one
            if (bestDateInfo == null) {
              isBetter = true;
            }
            // If this version has a better date quality, prefer it
            else if (dateInfo['quality'] > bestDateInfo['quality']) {
              isBetter = true;
            }
            // If equal date quality but better track durations, prefer this one
            else if (dateInfo['quality'] == bestDateInfo['quality'] &&
                trackDurationPercentage > bestTrackDurationPercentage) {
              isBetter = true;
              Logging.severe(
                  'Same date quality but better track durations found in version $versionId');
            }

            if (isBetter) {
              bestDateInfo = dateInfo;
              bestVersionId = versionId;
              versionData = fullVersionData;
              bestTrackList = versionTracks;
              bestTrackDurationPercentage = trackDurationPercentage;

              Logging.severe(
                  'Found better version $versionId with date quality ${dateInfo['quality']} and track duration coverage ${(trackDurationPercentage * 100).toStringAsFixed(1)}%');

              // If excellent date quality AND good track durations, we can stop
              if (dateInfo['quality'] >= 3 && trackDurationPercentage > 0.7) {
                Logging.severe(
                    'Found excellent version with full date and good track durations - stopping search');
                break;
              }
            }

            // Increment counter and check if we reached the limit
            versionsChecked++;
            if (versionsChecked >= maxVersionsToCheck) {
              Logging.severe(
                  'Reached maximum versions limit ($maxVersionsToCheck) - stopping search');
              break;
            }
          }
        } catch (e, stack) {
          // Catch errors for individual versions so we can continue checking others
          Logging.severe(
              'Error processing version: ${version['id']}', e, stack);
          continue;
        }
      }

      // Log summary of all versions we checked
      Logging.severe('Version date and track summary:');
      for (var versionDate in allVersionDates) {
        Logging.severe(
            '  Version ${versionDate['id']}: ${versionDate['original']} → ${versionDate['date']} '
            '(Quality: ${versionDate['quality']}, Tracks: ${versionDate['trackCount']}, '
            'Durations: ${(versionDate['durationPercentage'] * 100).toStringAsFixed(1)}%, '
            '${versionDate['country']}, ${versionDate['format']})');
      }

      // Return the best date info, version data AND tracks
      if (bestDateInfo != null) {
        return {
          'dateInfo': bestDateInfo,
          'id': bestVersionId,
          'data': versionData,
          'tracks': bestTrackList,
          'trackDurationPercentage': bestTrackDurationPercentage
        };
      }

      return null;
    } catch (e, stack) {
      Logging.severe('Error finding best version with date', e, stack);
      return null;
    }
  }

  /// Process a date string from Discogs and return a proper ISO format date
  static String _processDiscogsDate(String rawDate, String? yearStr) {
    Logging.severe(
        'Processing Discogs date: "$rawDate" (year fallback: $yearStr)');

    if (rawDate.isEmpty) {
      if (yearStr != null && RegExp(r'^\d{4}$').hasMatch(yearStr)) {
        Logging.severe(
            '  → Empty date string, using year fallback: $yearStr-01-01');
        return '$yearStr-01-01';
      }
      Logging.severe('  → Empty date string, using default date');
      return '2000-01-01';
    }

    // Full date already in YYYY-MM-DD format
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate)) {
      Logging.severe('  → Full ISO format detected (YYYY-MM-DD)');
      return rawDate;
    }
    // YYYY-MM format
    else if (RegExp(r'^\d{4}-\d{2}$').hasMatch(rawDate)) {
      final result = '$rawDate-01';
      Logging.severe(
          '  → Year-Month format detected (YYYY-MM), adding default day: $result');
      return result;
    }
    // Just year
    else if (RegExp(r'^\d{4}$').hasMatch(rawDate)) {
      final result = '$rawDate-01-01';
      Logging.severe(
          '  → Year-only format detected (YYYY), adding default month and day: $result');
      return result;
    }
    // Date in format like "July 2017" or "Jul 2017"
    else if (RegExp(r'[A-Za-z]+\s+\d{4}').hasMatch(rawDate)) {
      try {
        final match = RegExp(r'([A-Za-z]+)\s+(\d{4})').firstMatch(rawDate);
        if (match != null && match.groupCount >= 2) {
          final monthName = match.group(1)!;
          final year = match.group(2)!;

          // Try to map month name to number, handling various formats
          final String monthStr = _monthNameToNumber(monthName);
          final result = '$year-$monthStr-01';

          Logging.severe('  → Month Year format detected, parsed as: $result');
          return result;
        }
      } catch (e) {
        Logging.severe('  → Error parsing month name format: $e');
      }
    }
    // Some other format with year like "2017?"
    else if (RegExp(r'\d{4}').hasMatch(rawDate)) {
      final match = RegExp(r'(\d{4})').firstMatch(rawDate);
      if (match != null) {
        final result = '${match.group(1)}-01-01';
        Logging.severe(
            '  → Extracted year from complex string, using default month and day: $result');
        return result;
      }
    }

    // If we have a year as fallback
    if (yearStr != null && RegExp(r'^\d{4}$').hasMatch(yearStr)) {
      final result = '$yearStr-01-01';
      Logging.severe(
          '  → Using fallback year with default month and day: $result');
      return result;
    }

    // Last resort
    Logging.severe(
        '  → No usable date found, using default placeholder date: 2000-01-01');
    return '2000-01-01';
  }

  /// Evaluate the quality of a date string (higher is better)
  static Map<String, dynamic> _evaluateDate(String rawDate, String? yearStr) {
    String processedDate = _processDiscogsDate(rawDate, yearStr);
    int quality = 0;

    // Full YYYY-MM-DD format is best
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate)) {
      quality = 3;
      Logging.severe('Date quality for "$rawDate": 3 (Full ISO date)');
    }
    // YYYY-MM format is good
    else if (RegExp(r'^\d{4}-\d{2}$').hasMatch(rawDate)) {
      quality = 2;
      Logging.severe('Date quality for "$rawDate": 2 (Year + Month)');
    }
    // Just year is basic
    else if (RegExp(r'^\d{4}$').hasMatch(rawDate)) {
      quality = 1;
      Logging.severe('Date quality for "$rawDate": 1 (Year only)');
    } else {
      Logging.severe(
          'Date quality for "$rawDate": 0 (Could not determine proper format)');
    }

    return {'date': processedDate, 'quality': quality, 'original': rawDate};
  }

  /// Helper method to convert month name to number
  static String _monthNameToNumber(String monthName) {
    final normalized = monthName.toLowerCase().trim();

    // Full month names mapping
    final Map<String, String> fullMonths = {
      'january': '01',
      'february': '02',
      'march': '03',
      'april': '04',
      'may': '05',
      'june': '06',
      'july': '07',
      'august': '08',
      'september': '09',
      'october': '10',
      'november': '11',
      'december': '12',
    };

    // 3-letter abbreviations mapping
    final Map<String, String> shortMonths = {
      'jan': '01',
      'feb': '02',
      'mar': '03',
      'apr': '04',
      'may': '05',
      'jun': '06',
      'jul': '07',
      'aug': '08',
      'sep': '09',
      'oct': '10',
      'nov': '11',
      'dec': '12',
    };

    // First check for exact matches
    if (fullMonths.containsKey(normalized)) {
      return fullMonths[normalized]!;
    }

    if (shortMonths.containsKey(normalized)) {
      return shortMonths[normalized]!;
    }

    // Then check for partial matches (starts with)
    for (final entry in fullMonths.entries) {
      if (normalized.startsWith(entry.key.substring(0, 3))) {
        return entry.value;
      }
    }

    // Default to January if no match found
    Logging.severe(
        '  → Could not map month name "$monthName" to number, using 01');
    return '01';
  }

  /// Extract tracks from a Discogs tracklist
  static List<Map<String, dynamic>> _extractTrackList(
      List<dynamic> tracklist, String releaseId, String defaultArtistName) {
    final tracks = <Map<String, dynamic>>[];
    int trackIndex = 0;

    for (var track in tracklist) {
      // Skip headings, indexes, etc.
      if (track['type_'] == 'heading' || track['type_'] == 'index') {
        continue;
      }

      trackIndex++;

      // Create a unique track ID
      int trackId = int.parse(releaseId) * 1000 + trackIndex;

      // Extract track artist if available, or use album artist
      String trackArtist = defaultArtistName;
      if (track['artists'] != null &&
          track['artists'] is List &&
          track['artists'].isNotEmpty) {
        trackArtist = (track['artists'] as List)
            .where((a) => a['name'] != null)
            .map((a) => a['name'].toString())
            .join(', ');
      }

      // Parse duration - only if it exists
      int durationMs = 0;
      if (track['duration'] != null &&
          track['duration'].toString().trim().isNotEmpty) {
        durationMs = _parseTrackDuration(track['duration']);
      }

      tracks.add({
        'trackId': trackId,
        'trackName': track['title'] ?? 'Track $trackIndex',
        'trackNumber': trackIndex,
        'trackTimeMillis': durationMs,
        'artistName': trackArtist,
      });
    }

    return tracks;
  }

  /// Check if a list of tracks has meaningful duration information
  static bool _tracksHaveDurations(List<Map<String, dynamic>> tracks) {
    if (tracks.isEmpty) return false;

    int tracksWithDurations = 0;
    for (var track in tracks) {
      if (track['trackTimeMillis'] != null && track['trackTimeMillis'] > 0) {
        tracksWithDurations++;
      }
    }

    return tracksWithDurations / tracks.length >
        0.3; // At least 30% of tracks should have durations
  }

  /// Helper method to parse track durations from various formats
  static int _parseTrackDuration(dynamic duration) {
    if (duration == null || duration.toString().trim().isEmpty) {
      return 0;
    }
    final durationStr = duration.toString().trim();

    try {
      // Handle MM:SS format (e.g., "3:45")
      if (durationStr.contains(':')) {
        final parts = durationStr.split(':');
        // Handle HH:MM:SS format
        if (parts.length == 3) {
          final hours = int.tryParse(parts[0].trim()) ?? 0;
          final minutes = int.tryParse(parts[1].trim()) ?? 0;
          final seconds = int.tryParse(parts[2].trim()) ?? 0;
          return ((hours * 3600) + (minutes * 60) + seconds) * 1000;
        }
        // Handle MM:SS format
        else if (parts.length == 2) {
          final minutes = int.tryParse(parts[0].trim()) ?? 0;
          final seconds = int.tryParse(parts[1].trim()) ?? 0;
          return (minutes * 60 + seconds) * 1000;
        }
      }

      // Try to parse as seconds directly
      final secondsValue = double.tryParse(durationStr);
      if (secondsValue != null) {
        return (secondsValue * 1000).round();
      }
    } catch (e) {
      Logging.severe('Error parsing track duration: $e');
    }

    // If parsing fails, return 0
    return 0;
  }

  /// Calculate the percentage of tracks with durations
  static double _calculateTrackDurationPercentage(
      List<Map<String, dynamic>> tracks) {
    if (tracks.isEmpty) return 0.0;

    int tracksWithDurations = 0;
    for (var track in tracks) {
      if (track['trackTimeMillis'] != null && track['trackTimeMillis'] > 0) {
        tracksWithDurations++;
      }
    }

    return tracksWithDurations / tracks.length;
  }

  /// Gets Discogs API credentials
  static Future<Map<String, String>?> _getDiscogsCredentials() async {
    try {
      final consumerKey = await ApiKeys.discogsConsumerKey;
      final consumerSecret = await ApiKeys.discogsConsumerSecret;

      if (consumerKey != null &&
          consumerSecret != null &&
          consumerKey.isNotEmpty &&
          consumerSecret.isNotEmpty) {
        return {'key': consumerKey, 'secret': consumerSecret};
      }

      return null;
    } catch (e) {
      Logging.severe('Error getting Discogs credentials: $e');
      return null;
    }
  }
}
