import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rateme/api_keys.dart';
import 'package:rateme/database/database_helper.dart';
import 'package:rateme/platforms/platform_service_factory.dart';
import 'package:sqflite/sqflite.dart';
import '../logging.dart';
import 'platform_service_base.dart';

class DiscogsService extends PlatformServiceBase {
  static const String _baseUrl = 'https://api.discogs.com';

  @override
  String get platformId => 'discogs';

  @override
  String get displayName => 'Discogs';

  // Add a new method to retrieve a release for a master URL
  Future<String?> getFirstReleaseFromMaster(String masterId) async {
    try {
      Logging.severe('Fetching first release for master ID: $masterId');

      final key = await ApiKeys.discogsConsumerKey;
      final secret = await ApiKeys.discogsConsumerSecret;

      if (key == null || secret == null) {
        Logging.severe('Discogs API credentials not configured');
        return null;
      }

      final versionsUrl = '$_baseUrl/masters/$masterId/versions';
      final versionsResponse =
          await http.get(Uri.parse('$versionsUrl?key=$key&secret=$secret'));

      if (versionsResponse.statusCode == 200) {
        final versionsData = jsonDecode(versionsResponse.body);
        if (versionsData['versions'] != null &&
            versionsData['versions'] is List &&
            versionsData['versions'].isNotEmpty) {
          // Get the first release version
          final firstReleaseId = versionsData['versions'][0]['id'].toString();
          final releaseUrl = 'https://www.discogs.com/release/$firstReleaseId';

          Logging.severe('Found release $firstReleaseId for master $masterId');
          return releaseUrl;
        }
      }

      return null;
    } catch (e, stack) {
      Logging.severe('Error getting release for master', e, stack);
      return null;
    }
  }

  // Fix the getMasterWithTrackDurations method to better handle durations and retry failed URLs
  Future<Map<String, dynamic>?> getMasterWithTrackDurations(
      String masterId) async {
    try {
      Logging.severe(
          '====== GETTING MASTER TRACK DURATIONS FOR $masterId ======');

      // First, check if we have a valid cached URL in the database
      final db = await getDatabaseInstance();
      final cachedRelease = await db.query(
        'master_release_map',
        where: 'master_id = ?',
        whereArgs: [masterId],
      );

      // If we have a cached release mapping, try it first unless it's known to be bad
      if (cachedRelease.isNotEmpty) {
        final cachedReleaseId = cachedRelease.first['release_id'] as String;
        Logging.severe(
            'CACHED RELEASE: Found ID $cachedReleaseId for master $masterId');

        // Get all recent 404 errors from a memory cache or temporary store
        final recent404s = _getRecent404s();

        // DEBUG: Show all cached 404s
        Logging.severe('DEBUG: Cached 404 URLs: ${recent404s.join(", ")}');

        // If this URL recently gave us a 404, don't try it again
        if (recent404s.contains('release-$cachedReleaseId')) {
          Logging.severe(
              'CACHED RELEASE SKIPPED: $cachedReleaseId is in 404 cache');

          // Delete the invalid mapping
          await _removeInvalidReleaseMapping(masterId, cachedReleaseId);
        } else {
          // Try the cached release URL
          final releaseUrl = 'https://www.discogs.com/release/$cachedReleaseId';

          try {
            // IMPORTANT: Use a direct API call instead of fetchAlbumDetails
            // to avoid potential infinite loops
            final apiUrl = '$_baseUrl/releases/$cachedReleaseId';
            final apiUrlWithAuth =
                '$apiUrl?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}';

            Logging.severe('TRYING CACHED RELEASE: Direct API call to $apiUrl');
            final response = await http.get(Uri.parse(apiUrlWithAuth));

            if (response.statusCode == 200) {
              Logging.severe('CACHED RELEASE SUCCESS: Got 200 response');
              // Process release details
              final releaseDetails = _processDiscogsResponse(
                  response.body, releaseUrl, 'release', cachedReleaseId);

              // Check if this release has track durations and names
              final hasDurations = _hasValidTrackDurations(releaseDetails);
              final hasNames = _hasValidTrackNames(releaseDetails);

              Logging.severe(
                  'CACHED RELEASE QUALITY: Has durations: $hasDurations, Has names: $hasNames');

              if (hasDurations && hasNames) {
                // Important: Make sure track IDs match the master ID for ratings to work!
                if (releaseDetails != null &&
                    releaseDetails['tracks'] is List) {
                  // Create new tracks with proper IDs that match the master format
                  final tracks =
                      List<Map<String, dynamic>>.from(releaseDetails['tracks']);

                  // Log first track for debugging
                  if (tracks.isNotEmpty) {
                    Logging.severe(
                        'FIRST TRACK DETAILS: ${jsonEncode(tracks.first)}');
                  }

                  final List<Map<String, dynamic>> masterTracks = [];

                  for (int i = 0; i < tracks.length; i++) {
                    final Map<String, dynamic> track =
                        Map<String, dynamic>.from(tracks[i]);
                    final position = track['trackNumber'] ?? (i + 1);
                    final String masterTrackId =
                        'master-$masterId${position.toString().padLeft(3, '0')}';

                    // Store both IDs for reference
                    track['originalTrackId'] = track['trackId'];
                    track['trackId'] = masterTrackId;

                    masterTracks.add(track);
                  }

                  // Replace tracks with master-formatted ones
                  releaseDetails['tracks'] = masterTracks;

                  // Update album ID fields
                  releaseDetails['id'] = 'master-$masterId';
                  releaseDetails['collectionId'] = 'master-$masterId';
                  releaseDetails['url'] =
                      'https://www.discogs.com/master/$masterId';
                }

                Logging.severe(
                    'USING CACHED RELEASE: $cachedReleaseId successful');
                return releaseDetails;
              } else {
                Logging.severe(
                    'CACHED RELEASE INVALID: Missing durations or names');

                // Remove this invalid mapping
                await db.delete(
                  'master_release_map',
                  where: 'master_id = ? AND release_id = ?',
                  whereArgs: [masterId, cachedReleaseId],
                );

                // Add to 404 list to avoid trying again in this session
                _addRecent404('release-$cachedReleaseId');
              }
            } else {
              Logging.severe(
                  'CACHED RELEASE ERROR: HTTP ${response.statusCode}');

              // Add to 404 list and delete from database
              _addRecent404('release-$cachedReleaseId');

              await db.delete(
                'master_release_map',
                where: 'master_id = ? AND release_id = ?',
                whereArgs: [masterId, cachedReleaseId],
              );

              Logging.severe(
                  'CACHED RELEASE: Removed invalid mapping from database due to HTTP error');
            }
          } catch (e) {
            Logging.severe('CACHED RELEASE ERROR: Exception $e');
            // Continue to try other releases
          }
        }
      }

      // Get all versions from the master
      final versionsUrl = '$_baseUrl/masters/$masterId/versions';
      Logging.severe('FETCHING MASTER VERSIONS: $versionsUrl');

      final versionsResponse = await http.get(Uri.parse(
          '$versionsUrl?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}'));

      if (versionsResponse.statusCode != 200) {
        Logging.severe(
            'MASTER VERSIONS ERROR: HTTP ${versionsResponse.statusCode}');

        // If all attempts failed, check for platform matches
        Logging.severe('TRYING ALTERNATE PLATFORMS as last resort...');
        return await _tryAlternatePlatform(
            'https://www.discogs.com/master/$masterId');
      }

      final versionsData = jsonDecode(versionsResponse.body);
      if (versionsData['versions'] == null ||
          versionsData['versions'] is! List ||
          versionsData['versions'].isEmpty) {
        Logging.severe(
            'MASTER VERSIONS: No versions found for master $masterId');

        // If no versions found, check for platform matches
        Logging.severe('TRYING ALTERNATE PLATFORMS as last resort...');
        return await _tryAlternatePlatform(
            'https://www.discogs.com/master/$masterId');
      }

      final List<dynamic> versions = versionsData['versions'];
      Logging.severe(
          'MASTER VERSIONS: Found ${versions.length} releases for master $masterId');

      // Score and sort versions by potential quality
      final List<Map<String, dynamic>> scoredVersions = [];
      for (var version in versions) {
        int score = 0;
        final format = version['format']?.toString().toLowerCase() ?? '';
        final country = version['country']?.toString() ?? '';

        // Prioritize formats more likely to have duration information
        if (format.contains('cd')) {
          score += 100; // CDs most likely to have durations
        } else if (format.contains('file') ||
            format.contains('digital') ||
            format.contains('mp3')) {
          score += 90; // Digital releases very likely to have durations
        } else if (format.contains('vinyl') || format.contains('lp')) {
          score += 50;
        }

        // Prioritize certain countries that tend to have better track info
        if (country.contains('US')) {
          score += 20; // US releases often have good metadata
        } else if (country.contains('UK') || country.contains('Jap')) {
          score += 15; // UK and Japan releases usually good too
        } else if (country.contains('Eur')) {
          score += 10;
        }

        // Format-specific boosts
        if (format.contains('remaster')) score += 15;
        if (format.contains('deluxe')) score += 10;

        scoredVersions.add({'version': version, 'score': score});
      }

      // Sort by score (highest first)
      scoredVersions.sort((a, b) => b['score'].compareTo(a['score']));

      // Take top 15 or however many are available (up from 12)
      final topVersions = scoredVersions.take(15).toList();

      Logging.severe(
          'Will try up to ${topVersions.length} alternate versions to find track durations:');
      for (int i = 0; i < topVersions.length; i++) {
        final version = topVersions[i]['version'];
        final score = topVersions[i]['score'];
        final id = version['id'].toString();
        final format = version['format']?.toString() ?? '';
        final country = version['country']?.toString() ?? '';
        Logging.severe(
            '  ${i + 1}. releases/$id - Score: $score - Format: $format, Country: $country');
      }

      // Now try each version, starting with the highest scored ones
      int attempts = 0;
      for (var scoredVersion in topVersions) {
        attempts++;
        final version = scoredVersion['version'];
        final releaseId = version['id'].toString();
        final format = version['format']?.toString() ?? '';

        Logging.severe(
            'TRYING RELEASE $attempts/${topVersions.length}: $releaseId (Format: $format)');

        // Check if this URL recently gave us a 404
        if (_getRecent404s().contains('release-$releaseId')) {
          Logging.severe('RELEASE SKIPPED: $releaseId is in 404 cache');
          continue;
        }

        try {
          // IMPORTANT: Use a direct API call here to ensure we get track details
          final apiUrl = '$_baseUrl/releases/$releaseId';
          final apiUrlWithAuth =
              '$apiUrl?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}';

          Logging.severe('FETCHING RELEASE API: $apiUrl');
          final response = await http.get(Uri.parse(apiUrlWithAuth));

          if (response.statusCode == 200) {
            Logging.severe(
                'RELEASE API SUCCESS: Got 200 response for $releaseId');

            // Process release details directly
            final releaseUrl = 'https://www.discogs.com/release/$releaseId';
            final releaseDetails = _processDiscogsResponse(
                response.body, releaseUrl, 'release', releaseId);

            // Check if this release has track durations and names
            final hasDurations = _hasValidTrackDurations(releaseDetails);
            final hasNames = _hasValidTrackNames(releaseDetails);
            final trackCount = releaseDetails?['tracks']?.length ?? 0;

            Logging.severe(
                'RELEASE QUALITY: $releaseId has $trackCount tracks with durations: $hasDurations, names: $hasNames');

            if (releaseDetails != null && trackCount > 0) {
              // Even if we don't have durations, if we have good names, save the mapping
              if (hasNames) {
                Logging.severe(
                    'SAVING VALID RELEASE: $releaseId for master $masterId');
                await saveValidRelease(masterId, releaseId);
              }

              // Important: Make sure track IDs match the master ID for ratings to work!
              if (releaseDetails['tracks'] is List) {
                final tracks =
                    List<Map<String, dynamic>>.from(releaseDetails['tracks']);

                // Log first track for debugging
                if (tracks.isNotEmpty) {
                  Logging.severe(
                      'FIRST TRACK DETAILS: ${jsonEncode(tracks.first)}');
                }

                final List<Map<String, dynamic>> masterTracks = [];

                for (int i = 0; i < tracks.length; i++) {
                  final Map<String, dynamic> track =
                      Map<String, dynamic>.from(tracks[i]);
                  final position = track['trackNumber'] ?? (i + 1);
                  final String masterTrackId =
                      'master-$masterId${position.toString().padLeft(3, '0')}';

                  // Store both IDs for reference
                  track['originalTrackId'] = track['trackId'];
                  track['trackId'] = masterTrackId;

                  masterTracks.add(track);
                }

                // Replace tracks with master-formatted ones
                releaseDetails['tracks'] = masterTracks;

                // Update album ID fields
                releaseDetails['id'] = 'master-$masterId';
                releaseDetails['collectionId'] = 'master-$masterId';
                releaseDetails['url'] =
                    'https://www.discogs.com/master/$masterId';
              }

              // Log what we found
              if (hasDurations && hasNames) {
                Logging.severe(
                    'FOUND PERFECT RELEASE: $releaseId with durations and names');
                return releaseDetails;
              } else if (hasNames) {
                // If we have valid track names but missing durations, try to enhance with durations from other sources
                Logging.severe(
                    'ENHANCING RELEASE: $releaseId has names but missing durations');

                // Call the enhance method to add durations from other sources
                await _enhanceTracksWithDurations(releaseDetails, masterId);

                // Check if the enhancement was successful
                int tracksWithDurations = 0;
                for (var track in releaseDetails['tracks']) {
                  if ((track['trackTimeMillis'] ?? 0) > 0) {
                    tracksWithDurations++;
                  }
                }

                if (tracksWithDurations > 0) {
                  Logging.severe(
                      'ENHANCEMENT SUCCESS: Added durations to $tracksWithDurations tracks');
                  return releaseDetails;
                } else {
                  Logging.severe(
                      'ENHANCEMENT FAILED: No durations added, but using release anyway');
                  return releaseDetails; // Return it anyway since it has good track names
                }
              }
            }

            Logging.severe(
                'RELEASE INADEQUATE: $releaseId is missing required data');
          } else {
            Logging.severe(
                'RELEASE API ERROR: HTTP ${response.statusCode} for $releaseId');
            _addRecent404('release-$releaseId');
          }
        } catch (e) {
          Logging.severe('RELEASE ERROR: Exception $e for $releaseId');
          // Track this as a problematic URL
          _addRecent404('release-$releaseId');
        }
      }

      // If we've tried all versions and none worked, check for platform matches from database
      // Check if we have any existing platform matches in the database
      final platformMatches = await db.query(
        'platform_matches',
        where: 'album_id = ?',
        whereArgs: [masterId],
      );

      if (platformMatches.isNotEmpty) {
        Logging.severe(
            'FOUND ${platformMatches.length} PLATFORM MATCHES IN DATABASE');

        // Try each platform match
        for (var match in platformMatches) {
          final platform = match['platform'] as String;
          final matchUrl = match['url'] as String?;

          if (platform != 'discogs' &&
              matchUrl != null &&
              matchUrl.isNotEmpty) {
            Logging.severe('TRYING PLATFORM MATCH: $platform at $matchUrl');

            try {
              final platformFactory = PlatformServiceFactory();
              if (platformFactory.isPlatformSupported(platform)) {
                final service = platformFactory.getService(platform);
                final albumDetails = await service.fetchAlbumDetails(matchUrl);

                if (albumDetails != null && albumDetails['tracks'] is List) {
                  final tracks = albumDetails['tracks'] as List;
                  if (tracks.isNotEmpty) {
                    // Check if tracks have durations
                    bool hasDurations = false;
                    for (var track in tracks) {
                      if ((track['trackTimeMillis'] ?? 0) > 0) {
                        hasDurations = true;
                        break;
                      }
                    }

                    if (hasDurations) {
                      Logging.severe(
                          'PLATFORM MATCH SUCCESS: $platform has tracks with durations');

                      // Fix up the IDs to match Discogs format
                      albumDetails['id'] = 'master-$masterId';
                      albumDetails['collectionId'] = 'master-$masterId';
                      albumDetails['url'] =
                          'https://www.discogs.com/master/$masterId';
                      albumDetails['platform'] =
                          'discogs'; // Keep original platform

                      // Store these tracks in database for future use
                      await storeTrackNames(
                          'master-$masterId',
                          List<Map<String, dynamic>>.from(
                              albumDetails['tracks']));

                      return albumDetails;
                    }
                  }
                }
              }
            } catch (e) {
              Logging.severe(
                  'PLATFORM MATCH ERROR: Exception $e for $platform');
            }
          }
        }
      }

      // As a last resort, try to find new platform matches
      Logging.severe('TRYING ALTERNATE PLATFORMS as last resort...');
      return await _tryAlternatePlatform(
          'https://www.discogs.com/master/$masterId');
    } catch (e, stack) {
      Logging.severe('ERROR IN getMasterWithTrackDurations', e, stack);
      return null;
    }
  }

  // Add a helper method to check if track names are valid
  bool _hasValidTrackNames(Map<String, dynamic>? releaseDetails) {
    if (releaseDetails == null ||
        releaseDetails['tracks'] == null ||
        releaseDetails['tracks'] is! List ||
        releaseDetails['tracks'].isEmpty) {
      return false;
    }

    // Check if tracks have real names (not just "Track X")
    List<dynamic> tracks = releaseDetails['tracks'];
    int tracksWithRealNames = 0;

    for (var track in tracks) {
      String trackName = track['trackName'] ?? '';
      // A track name is considered "real" if it's not empty and doesn't match the pattern "Track X"
      if (trackName.isNotEmpty && !RegExp(r'^Track \d+$').hasMatch(trackName)) {
        tracksWithRealNames++;
      }
    }

    // Consider valid if at least 50% of tracks have real names
    double percentage =
        tracks.isEmpty ? 0 : tracksWithRealNames / tracks.length;
    Logging.severe(
        'Release has ${(percentage * 100).toStringAsFixed(0)}% tracks with real names');

    return percentage >= 0.5;
  }

  // Update the _hasValidTrackDurations method to be more lenient
  bool _hasValidTrackDurations(Map<String, dynamic>? releaseDetails) {
    if (releaseDetails == null ||
        releaseDetails['tracks'] == null ||
        releaseDetails['tracks'] is! List ||
        releaseDetails['tracks'].isEmpty) {
      return false;
    }

    // Check if at least 30% of tracks have durations (lowered from 50%)
    // This allows us to use releases with at least some duration information
    List<dynamic> tracks = releaseDetails['tracks'];
    int tracksWithDurations = 0;

    for (var track in tracks) {
      if ((track['trackTimeMillis'] ?? 0) > 0) {
        tracksWithDurations++;
      }
    }

    double percentage =
        tracks.isEmpty ? 0 : tracksWithDurations / tracks.length;
    Logging.severe(
        'Release has ${(percentage * 100).toStringAsFixed(0)}% tracks with durations');

    // Return true if at least 30% of tracks have durations (was 50% before)
    return percentage >= 0.3;
  }

  @override
  Future<String?> findAlbumUrl(String artist, String albumName) async {
    try {
      Logging.severe('Searching for Discogs URL: "$albumName" by "$artist"');

      // Get API keys
      final key = await ApiKeys.discogsConsumerKey;
      final secret = await ApiKeys.discogsConsumerSecret;

      if (key == null || secret == null) {
        Logging.severe('Discogs API credentials not configured');
        return null;
      }

      // Normalize names for better matching
      final normalizedArtist = normalizeForComparison(artist);
      final normalizedAlbum = normalizeForComparison(albumName);

      // FIX: Use the actual string values of the keys instead of the Future objects
      final query = Uri.encodeComponent('$artist $albumName');
      final url = Uri.parse(
          '$_baseUrl/database/search?q=$query&type=release,master&per_page=20'
          '&key=$key'
          '&secret=$secret');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List<dynamic>? ?? [];

        Logging.severe('Discogs: Found ${results.length} results');

        // Try to find the best match
        for (var result in results) {
          // Extract info
          final String resultTitle = result['title'] ?? '';

          // Discogs combines artist and title in the title field, so we need to parse it
          String resultArtist = '';
          String resultAlbum = '';

          // Title is usually in format "Artist - Album"
          if (resultTitle.contains(' - ')) {
            final parts = resultTitle.split(' - ');
            resultArtist = parts[0];
            resultAlbum =
                parts.sublist(1).join(' - '); // Handle album titles with dashes
          } else {
            // If there's no dash, just use the full title as the album name
            resultArtist = resultTitle;
            resultAlbum = resultTitle;
          }

          // Normalize for comparison
          final normalizedResultArtist = normalizeForComparison(resultArtist);
          final normalizedResultAlbum = normalizeForComparison(resultAlbum);

          // Calculate similarity scores
          final artistScore = calculateStringSimilarity(
              normalizedArtist, normalizedResultArtist);
          final albumScore =
              calculateStringSimilarity(normalizedAlbum, normalizedResultAlbum);
          final combinedScore = (artistScore * 0.6) + (albumScore * 0.4);

          // Check if this is a good match
          if (combinedScore > 0.6 || (artistScore > 0.7 && albumScore > 0.5)) {
            // Extract release ID or master ID
            String? id = result['id']?.toString();
            String? type = result['type'];

            // Construct URL
            if (id != null && type != null) {
              String discogsUrl;
              if (type == 'release') {
                discogsUrl = 'https://www.discogs.com/release/$id';
              } else if (type == 'master') {
                discogsUrl = 'https://www.discogs.com/master/$id';
              } else {
                continue; // Skip unknown types
              }

              Logging.severe(
                  'Discogs: Best match found: $discogsUrl (score: ${combinedScore.toStringAsFixed(2)})');
              return discogsUrl;
            }
          }
        }
      }

      Logging.severe('No matching release found on Discogs');
      return null;
    } catch (e, stack) {
      Logging.severe('Error searching Discogs', e, stack);
      return null;
    }
  }

  @override
  Future<bool> verifyAlbumExists(String artist, String albumName) async {
    try {
      // Get API keys
      final key = await ApiKeys.discogsConsumerKey;
      final secret = await ApiKeys.discogsConsumerSecret;

      if (key == null || secret == null) {
        Logging.severe('Discogs API credentials not configured');
        return false;
      }

      // FIX: Use the actual string values of the keys instead of the Future objects
      // Similar implementation to findAlbumUrl, but just return true/false
      final normalizedArtist = normalizeForComparison(artist);
      final normalizedAlbum = normalizeForComparison(albumName);

      final query = Uri.encodeComponent('$artist $albumName');
      final url = Uri.parse(
          '$_baseUrl/database/search?q=$query&type=release&per_page=10'
          '&key=$key'
          '&secret=$secret');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List;

        for (var result in results) {
          final String resultTitle = result['title'] ?? '';

          // Parse artist and album from title
          String resultArtist = '';
          String resultAlbum = '';

          if (resultTitle.contains(' - ')) {
            final parts = resultTitle.split(' - ');
            resultArtist = parts[0];
            resultAlbum = parts.sublist(1).join(' - ');
          } else {
            resultArtist = resultTitle;
            resultAlbum = resultTitle;
          }

          final artistScore = calculateStringSimilarity(
              normalizeForComparison(resultArtist), normalizedArtist);
          final albumScore = calculateStringSimilarity(
              normalizeForComparison(resultAlbum), normalizedAlbum);

          if (artistScore > 0.7 || albumScore > 0.7) {
            return true;
          }
        }
      }
      return false;
    } catch (e, stack) {
      Logging.severe('Error verifying Discogs album', e, stack);
      return false;
    }
  }

  // Modify the fetchAlbumDetails method to better handle cached release 404 errors
  @override
  Future<Map<String, dynamic>?> fetchAlbumDetails(String url) async {
    try {
      // Reduce verbosity by only logging the URL itself, not the entire fetching message
      Logging.severe('Fetching Discogs details: $url');

      // Extract the release or master ID from the URL
      String? id;
      String type = 'release'; // Default to release

      if (url.contains('/release/')) {
        final regExp = RegExp(r'/release/(\d+)');
        final match = regExp.firstMatch(url);
        id = match?.group(1);

        // Make sure we have a standardized format for this URL (for platform matching)
        final standardizedUrl = 'https://www.discogs.com/release/$id';
        if (url != standardizedUrl) {
          Logging.severe('Normalizing URL from $url to $standardizedUrl');
        }
        url = standardizedUrl;

        // Check if this is a cached release URL that resulted from a master lookup
        try {
          final db = await getDatabaseInstance();

          // First check if the master_release_map table exists
          final tableCheck = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='master_release_map'");

          // Check for schema (whether it has release_id column)
          if (tableCheck.isNotEmpty) {
            final schemaCheck =
                await db.rawQuery('PRAGMA table_info(master_release_map)');
            final columnNames =
                schemaCheck.map((c) => c['name'].toString()).toList();

            if (columnNames.contains('release_id')) {
              final masterMapping = await db.query(
                'master_release_map',
                where: 'release_id = ?',
                whereArgs: [id],
              );

              // If this is a release that comes from a master mapping, and it failed,
              // we should remove the mapping and redirect to the master URL
              if (masterMapping.isNotEmpty) {
                final masterId = masterMapping.first['master_id'] as String;
                Logging.severe(
                    'NOTE: Release $id is mapped from master $masterId');

                // Keep track of cached release that might fail
                final cachedReleaseId = id;
                final masterUrl = 'https://www.discogs.com/master/$masterId';

                // Try the direct API call to check if the release exists
                final apiUrl = '$_baseUrl/releases/$id';
                final apiUrlWithAuth =
                    '$apiUrl?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}';

                final checkResponse = await http.get(Uri.parse(apiUrlWithAuth));

                // If the release doesn't exist (404), redirect to the master URL
                if (checkResponse.statusCode == 404) {
                  Logging.severe(
                      'CACHED RELEASE FAILED WITH 404 - removing mapping and redirecting to master URL');

                  // Remove the invalid mapping
                  await _removeInvalidReleaseMapping(
                      masterId, cachedReleaseId!);

                  // Return to the master URL instead
                  Logging.severe('REDIRECTING to master URL: $masterUrl');
                  return await fetchAlbumDetails(masterUrl);
                }
              }
            }
          }
        } catch (e) {
          // Just log the error and continue; this is non-critical
          Logging.severe('Error checking master mapping: $e');
        }
      } else if (url.contains('/master/')) {
        final regExp = RegExp(r'/master/(\d+)');
        final match = regExp.firstMatch(url);
        id = match?.group(1);
        type = 'master';

        // Make sure we have a standardized format for this URL (for platform matching)
        final standardizedUrl = 'https://www.discogs.com/master/$id';
        if (url != standardizedUrl) {
          Logging.severe('Normalizing URL from $url to $standardizedUrl');
        }
        url = standardizedUrl;
      }

      // The albumId we'll use for database queries
      final albumId = type == 'master' ? 'master-$id' : 'release-$id';

      // Check if we already have tracks with durations in the database
      final tracksFromDb = await _getTracksFromDatabase(albumId);
      bool hasDurations = false;

      if (tracksFromDb.isNotEmpty) {
        Logging.severe(
            'DATABASE: Found ${tracksFromDb.length} tracks for album $albumId');

        // Check if these tracks have durations
        for (var track in tracksFromDb) {
          if ((track['trackTimeMillis'] ?? 0) > 0) {
            hasDurations = true;
            break;
          }
        }

        if (hasDurations) {
          Logging.severe('DATABASE: Found tracks with durations, using them');

          // Create a minimal album object with the tracks from DB
          return {
            'id': albumId,
            'collectionId': albumId,
            'name': 'Unknown Album', // Will be replaced by app logic if needed
            'collectionName': 'Unknown Album',
            'artist': 'Unknown Artist',
            'artistName': 'Unknown Artist',
            'artworkUrl': '',
            'artworkUrl100': '',
            'url': url,
            'platform': 'discogs',
            'tracks': tracksFromDb,
          };
        } else {
          Logging.severe(
              'DATABASE: Tracks found but missing durations, will fetch from API');
        }
      } else {
        Logging.severe('DATABASE: No tracks found for album $albumId');
      }

      // For master URLs, always try to get a valid release with durations first
      if (type == 'master') {
        Logging.severe(
            'MASTER URL DETECTED: Will try multiple releases to find valid track durations');

        // Use our specialized method to find a release with durations
        final masterWithDurations = await getMasterWithTrackDurations(id!);
        if (masterWithDurations != null) {
          // Use the data from our specialized master lookup
          masterWithDurations['url'] = url; // Preserve original URL

          // Check if any track has duration
          bool anyDurations = false;
          if (masterWithDurations['tracks'] is List) {
            for (var track in masterWithDurations['tracks']) {
              if ((track['trackTimeMillis'] ?? 0) > 0) {
                anyDurations = true;
                break;
              }
            }
          }

          Logging.severe(
              'MASTER LOOKUP SUCCESS: Found data with durations: $anyDurations');
          return masterWithDurations;
        } else {
          Logging.severe(
              'MASTER LOOKUP FAILED: No release found with valid data');
        }
      }

      // Direct API lookup for non-master URLs or if master handling failed
      String apiUrl = '$_baseUrl/$type/$id';

      // Get API keys
      final key = await ApiKeys.discogsConsumerKey;
      final secret = await ApiKeys.discogsConsumerSecret;

      if (key == null || secret == null) {
        Logging.severe('Discogs API credentials not configured');
        return null;
      }

      apiUrl += '?key=$key&secret=$secret';

      Logging.severe('DIRECT API CALL: $apiUrl');
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        Logging.severe('DIRECT API SUCCESS: Got 200 response');

        // For successful responses, process them
        final details = _processDiscogsResponse(response.body, url, type, id!);

        // Check for valid durations
        bool hasDurations = false;
        if (details != null && details['tracks'] is List) {
          for (var track in details['tracks']) {
            if ((track['trackTimeMillis'] ?? 0) > 0) {
              hasDurations = true;
              break;
            }
          }
        }

        Logging.severe('DIRECT API RESPONSE: Has durations: $hasDurations');

        return details;
      } else {
        Logging.severe('DIRECT API ERROR: HTTP ${response.statusCode}');

        // If API call fails, create tracks from ratings as a last resort
        if (tracksFromDb.isNotEmpty) {
          Logging.severe(
              'FALLBACK: Creating album with tracks from ratings data');
          return _createAlbumWithTracksFromRatings(albumId, url);
        }
      }

      // Try all alternative platforms as a last resort
      Logging.severe('TRYING ALTERNATE PLATFORMS as final fallback');
      return await _tryAlternatePlatform(url);
    } catch (e, stack) {
      Logging.severe('ERROR IN fetchAlbumDetails', e, stack);
      return null;
    }
  }

  // Add new method to enhance tracks with durations from other platforms
  Future<void> _enhanceTracksWithDurations(
      Map<String, dynamic> albumData, String masterId) async {
    try {
      if (!albumData.containsKey('tracks') || albumData['tracks'] is! List) {
        Logging.severe('Cannot enhance tracks: invalid album data');
        return;
      }

      final List<Map<String, dynamic>> tracks =
          List<Map<String, dynamic>>.from(albumData['tracks']);
      if (tracks.isEmpty) {
        Logging.severe('Cannot enhance tracks: no tracks in album');
        return;
      }

      final String artistName =
          albumData['artist'] ?? albumData['artistName'] ?? '';
      final String albumName =
          albumData['name'] ?? albumData['collectionName'] ?? '';

      if (artistName.isEmpty || albumName.isEmpty) {
        Logging.severe('Cannot enhance tracks: missing artist or album name');
        return;
      }

      Logging.severe(
          'Looking for track durations for "$albumName" by "$artistName"');

      // Look up this album on other platforms to find track durations
      final platformFactory = PlatformServiceFactory();

      // First try Spotify
      if (platformFactory.isPlatformSupported('spotify')) {
        final spotifyService = platformFactory.getService('spotify');
        final spotifyUrl =
            await spotifyService.findAlbumUrl(artistName, albumName);

        if (spotifyUrl != null) {
          Logging.severe('Found Spotify match, fetching track details');
          final spotifyDetails =
              await spotifyService.fetchAlbumDetails(spotifyUrl);

          if (spotifyDetails != null && spotifyDetails['tracks'] is List) {
            final spotifyTracks =
                List<Map<String, dynamic>>.from(spotifyDetails['tracks']);

            if (spotifyTracks.isNotEmpty) {
              Logging.severe(
                  'Found ${spotifyTracks.length} tracks from Spotify, attempting to match with our ${tracks.length} tracks');
              _mergeTrackDurations(tracks, spotifyTracks);
            }
          }
        }
      }

      // Then try Apple Music
      if (platformFactory.isPlatformSupported('apple_music')) {
        final appleService = platformFactory.getService('apple_music');
        final appleUrl = await appleService.findAlbumUrl(artistName, albumName);

        if (appleUrl != null) {
          Logging.severe('Found Apple Music match, fetching track details');
          final appleDetails = await appleService.fetchAlbumDetails(appleUrl);

          if (appleDetails != null && appleDetails['tracks'] is List) {
            final appleTracks =
                List<Map<String, dynamic>>.from(appleDetails['tracks']);

            if (appleTracks.isNotEmpty) {
              Logging.severe(
                  'Found ${appleTracks.length} tracks from Apple Music, attempting to match with our ${tracks.length} tracks');
              _mergeTrackDurations(tracks, appleTracks);
            }
          }
        }
      }

      // Last, try Deezer
      if (platformFactory.isPlatformSupported('deezer')) {
        final deezerService = platformFactory.getService('deezer');
        final deezerUrl =
            await deezerService.findAlbumUrl(artistName, albumName);

        if (deezerUrl != null) {
          Logging.severe('Found Deezer match, fetching track details');
          final deezerDetails =
              await deezerService.fetchAlbumDetails(deezerUrl);

          if (deezerDetails != null && deezerDetails['tracks'] is List) {
            final deezerTracks =
                List<Map<String, dynamic>>.from(deezerDetails['tracks']);

            if (deezerTracks.isNotEmpty) {
              Logging.severe(
                  'Found ${deezerTracks.length} tracks from Deezer, attempting to match with our ${tracks.length} tracks');
              _mergeTrackDurations(tracks, deezerTracks);
            }
          }
        }
      }

      // Update the album data with enhanced track durations
      albumData['tracks'] = tracks;

      // Store the updated tracks in the database
      await storeTrackNames('master-$masterId', tracks);

      // Check how many tracks now have durations
      int tracksWithDurations = 0;
      for (var track in tracks) {
        if ((track['trackTimeMillis'] ?? 0) > 0) {
          tracksWithDurations++;
        }
      }

      Logging.severe(
          'After enhancement, $tracksWithDurations/${tracks.length} tracks have durations');
    } catch (e) {
      Logging.severe('Error enhancing tracks with durations: $e');
    }
  }

  // Add helper method to merge durations from source tracks into target tracks
  void _mergeTrackDurations(List<Map<String, dynamic>> targetTracks,
      List<Map<String, dynamic>> sourceTracks) {
    try {
      // First try exact count match - straight position matching is most reliable when track counts match
      if (targetTracks.length == sourceTracks.length) {
        Logging.severe(
            'Track counts match, using position-based duration mapping');

        for (int i = 0; i < targetTracks.length; i++) {
          if ((targetTracks[i]['trackTimeMillis'] ?? 0) <= 0 &&
              (sourceTracks[i]['trackTimeMillis'] ?? 0) > 0) {
            targetTracks[i]['trackTimeMillis'] =
                sourceTracks[i]['trackTimeMillis'];
            Logging.severe(
                'Copied duration for track ${i + 1}: ${targetTracks[i]['trackName']} = ${sourceTracks[i]['trackTimeMillis']}ms');
          }
        }
        return;
      }

      // If track counts don't match, try name-based matching
      Logging.severe(
          'Track counts don\'t match (${targetTracks.length} vs ${sourceTracks.length}), using name-based matching');

      for (int i = 0; i < targetTracks.length; i++) {
        final targetTrack = targetTracks[i];
        final targetName =
            targetTrack['trackName']?.toString().toLowerCase() ?? '';

        if (targetName.isEmpty || (targetTrack['trackTimeMillis'] ?? 0) > 0) {
          continue; // Skip tracks with no name or that already have durations
        }

        double bestMatch = 0;
        Map<String, dynamic>? bestMatchTrack;

        // Find best matching track by name
        for (var sourceTrack in sourceTracks) {
          final sourceName =
              sourceTrack['trackName']?.toString().toLowerCase() ?? '';
          if (sourceName.isEmpty) continue;

          final similarity = calculateStringSimilarity(targetName, sourceName);
          if (similarity > bestMatch && similarity > 0.6) {
            bestMatch = similarity;
            bestMatchTrack = sourceTrack;
          }
        }

        // Apply duration from best match
        if (bestMatchTrack != null &&
            (bestMatchTrack['trackTimeMillis'] ?? 0) > 0) {
          targetTrack['trackTimeMillis'] = bestMatchTrack['trackTimeMillis'];
          Logging.severe(
              'Matched "${targetTrack['trackName']}" with "${bestMatchTrack['trackName']}" (similarity: ${bestMatch.toStringAsFixed(2)}), duration: ${bestMatchTrack['trackTimeMillis']}ms');
        }
      }
    } catch (e) {
      Logging.severe('Error merging track durations: $e');
    }
  }

  /// Parse Discogs duration string to milliseconds
  int _parseDuration(String duration) {
    try {
      // Format is usually "mm:ss" but can also be "h:mm:ss"
      final parts = duration.split(':');

      if (parts.length == 2) {
        // mm:ss format
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        return (minutes * 60 + seconds) * 1000;
      } else if (parts.length == 3) {
        // h:mm:ss format
        final hours = int.tryParse(parts[0]) ?? 0;
        final minutes = int.tryParse(parts[1]) ?? 0;
        final seconds = int.tryParse(parts[2]) ?? 0;
        return (hours * 3600 + minutes * 60 + seconds) * 1000;
      }

      return 0;
    } catch (e) {
      Logging.severe('Error parsing Discogs duration: $e');
      return 0;
    }
  }

  // Fix: Ensure track names are properly extracted
  Map<String, dynamic>? _processDiscogsResponse(
      String responseBody, String url, String type, String id) {
    final albumData = jsonDecode(responseBody);

    // Parse artist name
    String artistName = 'Unknown Artist';
    if (albumData['artists'] != null &&
        albumData['artists'] is List &&
        albumData['artists'].isNotEmpty) {
      artistName = albumData['artists']
          .map((a) => a['name'])
          .join(', ')
          .replaceAll(' *', '')
          .replaceAll('*', '');
    } else if (albumData['artist'] != null) {
      artistName = albumData['artist'];
    }

    // Get artwork URL
    String artworkUrl = '';
    if (albumData['images'] != null &&
        albumData['images'] is List &&
        albumData['images'].isNotEmpty) {
      // Look for primary image
      var primaryImage = albumData['images'].firstWhere(
          (img) => img['type'] == 'primary',
          orElse: () => albumData['images'][0]);

      if (primaryImage != null && primaryImage['uri'] != null) {
        artworkUrl = primaryImage['uri'];
      }
    }

    // Parse tracks with proper track names
    List<Map<String, dynamic>> tracks = [];
    if (albumData['tracklist'] != null && albumData['tracklist'] is List) {
      int position = 1;
      for (var trackData in albumData['tracklist']) {
        // Skip non-track items
        if (trackData['type_'] == 'track' || trackData['type_'] == null) {
          // Use actual track title if available, not placeholder
          String trackName = trackData['title'] ?? '';

          // Log each track name for debugging
          Logging.severe('Processing track $position: "$trackName"');

          // Only use "Track X" if the title is empty
          if (trackName.trim().isEmpty) {
            trackName = 'Track $position';
          }

          // Parse duration
          int durationMs = 0;
          if (trackData['duration'] != null &&
              trackData['duration'].toString().isNotEmpty) {
            durationMs = _parseDuration(trackData['duration'].toString());
          }

          // Create a standard track ID format: albumId + position (zero-padded)
          String releaseId = type == 'release' ? id : 'master-$id';
          String positionStr = position.toString().padLeft(3, '0');
          String trackId = '$releaseId$positionStr';

          tracks.add({
            'trackId': trackId,
            'trackName': trackName,
            'trackNumber': position,
            'trackTimeMillis': durationMs,
            'extraInfo': trackData[
                'extraartists'], // Include extra info like featuring artists
          });

          position++;
        }
      }
    }

    // Log the total number of tracks found
    Logging.severe('Extracted ${tracks.length} tracks from Discogs response');

    // Log the first track for debugging
    if (tracks.isNotEmpty) {
      Logging.severe('First track: ${jsonEncode(tracks.first)}');
    } else {
      Logging.severe('No tracks found in Discogs response');
    }

    // Ensure we have a proper ID
    final albumId = type == 'master' ? 'master-$id' : 'release-$id';

    // Create standardized album object
    final result = {
      'id': albumId,
      'collectionId': albumId,
      'name': albumData['title'] ?? 'Unknown Album',
      'collectionName': albumData['title'] ?? 'Unknown Album',
      'artist': artistName,
      'artistName': artistName,
      'artworkUrl': artworkUrl,
      'artworkUrl100': artworkUrl,
      'releaseDate': albumData['released'] ??
          albumData['year'] ??
          DateTime.now().year.toString(),
      'url': url,
      'platform': 'discogs',
      'tracks': tracks,
    };

    // Store the track names in the database for future reference
    storeTrackNames(albumId, tracks);

    return result;
  }

  // Add a new method to store track names in the database after fetching them
  Future<void> storeTrackNames(
      String albumId, List<Map<String, dynamic>> tracks) async {
    try {
      final db = await getDatabaseInstance();

      // First check if the tracks table exists
      final tableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='tracks'");

      // Create the table if it doesn't exist
      if (tableCheck.isEmpty) {
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
      }

      // Store each track with album ID association
      for (final track in tracks) {
        String trackId = track['trackId']?.toString() ?? '';
        String trackName = track['trackName'] ?? 'Unknown Track';
        int position = track['trackNumber'] ?? 0;
        int durationMs = track['trackTimeMillis'] ?? 0;

        Logging.severe('Storing track to database: $trackId, name: $trackName');

        // Store the track in the database
        await db.insert(
          'tracks',
          {
            'id': trackId,
            'album_id': albumId,
            'name': trackName,
            'position': position,
            'duration_ms': durationMs,
            'data': jsonEncode(track)
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      Logging.severe(
          'Successfully stored ${tracks.length} tracks for album $albumId');
    } catch (e, stack) {
      Logging.severe('Error storing track names', e, stack);
    }
  }

  // Add a method to retrieve tracks from database
  Future<List<Map<String, dynamic>>> _getTracksFromDatabase(
      String albumId) async {
    try {
      final db = await getDatabaseInstance();

      // Check if the tracks table exists
      final tableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='tracks'");

      if (tableCheck.isEmpty) {
        return [];
      }

      // Query for tracks with this album ID
      final results = await db.query('tracks',
          where: 'album_id = ?', whereArgs: [albumId], orderBy: 'position ASC');

      if (results.isEmpty) {
        return [];
      }

      // Format the tracks into the expected structure
      List<Map<String, dynamic>> tracks = [];
      for (final track in results) {
        final trackData = {
          'trackId': track['id'],
          'trackName': track['name'],
          'trackNumber': track['position'],
          'trackTimeMillis': track['duration_ms'],
        };

        // Add extra data if available
        if (track['data'] != null) {
          try {
            final extraData = jsonDecode(track['data'] as String);
            if (extraData is Map<String, dynamic>) {
              trackData.addAll(extraData);
            }
          } catch (e) {
            // Ignore parsing errors
          }
        }

        tracks.add(trackData);
      }

      Logging.severe(
          'Retrieved ${tracks.length} tracks from database for album $albumId');

      if (tracks.isNotEmpty) {
        Logging.severe('First track from DB: ${jsonEncode(tracks.first)}');
      }

      return tracks;
    } catch (e, stack) {
      Logging.severe('Error retrieving tracks from database', e, stack);
      return [];
    }
  }

  // Add this utility method to save successful release mappings
  Future<void> saveValidRelease(String masterId, String releaseId) async {
    try {
      final db = await getDatabaseInstance();
      await db.insert(
        'master_release_map',
        {
          'master_id': masterId,
          'release_id': releaseId,
          'timestamp': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      Logging.severe(
          'Saved valid release mapping: master $masterId -> release $releaseId');
    } catch (e) {
      Logging.severe('Error saving release mapping: $e');
    }
  }

  // Simple cache of recent 404 URLs to avoid retrying them
  final List<String> _recent404Cache = [];

  void _addRecent404(String url) {
    // Keep cache size manageable
    if (_recent404Cache.length > 100) {
      _recent404Cache.removeAt(0);
    }
    if (!_recent404Cache.contains(url)) {
      _recent404Cache.add(url);
      Logging.severe('Added URL to 404 cache: $url');
    }
  }

  List<String> _getRecent404s() {
    return _recent404Cache;
  }

  // Add this method to access the database
  Future<Database> getDatabaseInstance() async {
    final db = await DatabaseHelper.instance.database;
    return db;
  }

  // Add method to try getting data from alternate platforms
  Future<Map<String, dynamic>?> _tryAlternatePlatform(String url) async {
    try {
      Logging.severe('====== TRYING ALTERNATE PLATFORMS FOR URL: $url ======');

      // Extract the master or release ID
      String? id;
      String type = '';

      if (url.contains('/master/')) {
        final regExp = RegExp(r'/master/(\d+)');
        final match = regExp.firstMatch(url);
        id = match?.group(1);
        type = 'master';
      } else if (url.contains('/release/')) {
        final regExp = RegExp(r'/release/(\d+)');
        final match = regExp.firstMatch(url);
        id = match?.group(1);
        type = 'release';
      }

      if (id == null) {
        Logging.severe(
            'ERROR: Could not extract ID from URL for alternate platform lookup');
        return null;
      }

      Logging.severe('EXTRACTED: $type ID $id');

      // Try to get album info from the database
      final db = await getDatabaseInstance();
      final results = await db.query(
        'platform_matches',
        where: 'album_id = ?',
        whereArgs: [id],
      );

      // Check if we have any matches for other platforms
      if (results.isNotEmpty) {
        Logging.severe(
            'DATABASE: Found ${results.length} platform matches for album ID $id');

        // Try each platform in a specific order (Apple Music first)
        final orderedPlatforms = ['apple_music', 'spotify', 'deezer'];
        final platformMatches = <String, String>{};

        // Build map of platform -> URL
        for (var match in results) {
          final platform = match['platform'] as String;
          final matchUrl = match['url'] as String?;
          if (platform != 'discogs' &&
              matchUrl != null &&
              matchUrl.isNotEmpty) {
            platformMatches[platform] = matchUrl;
          }
        }

        // Try platforms in preferred order
        for (final platform in orderedPlatforms) {
          if (platformMatches.containsKey(platform)) {
            final matchUrl = platformMatches[platform]!;
            Logging.severe('TRYING PREFERRED PLATFORM: $platform at $matchUrl');

            try {
              final platformFactory = PlatformServiceFactory();
              if (platformFactory.isPlatformSupported(platform)) {
                final service = platformFactory.getService(platform);
                final albumDetails = await service.fetchAlbumDetails(matchUrl);

                if (albumDetails != null) {
                  Logging.severe(
                      'SUCCESS: Got details from preferred platform $platform');

                  // Add the rest of the existing code here...
                  // ...

                  return albumDetails;
                }
              }
            } catch (e) {
              Logging.severe('ERROR accessing $platform: $e');
            }
          }
        }

        // If preferred platforms failed, try any remaining platforms
        for (var match in results) {
          final platform = match['platform'] as String;
          final matchUrl = match['url'] as String?;

          // Skip platforms we already tried and discogs itself
          if (!orderedPlatforms.contains(platform) &&
              platform != 'discogs' &&
              matchUrl != null &&
              matchUrl.isNotEmpty) {
            Logging.severe('TRYING FALLBACK PLATFORM: $platform at $matchUrl');

            // ...rest of existing code...
          }
        }
      } else {
        Logging.severe('DATABASE: No platform matches found for album ID $id');
      }

      // If no platform match in our database, try finding one via the album info
      if (type == 'master') {
        try {
          // Get API keys
          final key = await ApiKeys.discogsConsumerKey;
          final secret = await ApiKeys.discogsConsumerSecret;

          if (key == null || secret == null) {
            Logging.severe('Discogs API credentials not configured');
            return null;
          }

          // Try to get basic album details to search other platforms
          final masterUrl = '$_baseUrl/masters/$id';
          Logging.severe('FETCHING MASTER INFO: $masterUrl');

          final response =
              await http.get(Uri.parse('$masterUrl?key=$key&secret=$secret'));

          if (response.statusCode == 200) {
            final masterData = jsonDecode(response.body);
            String? artistName;

            if (masterData['artists'] != null &&
                masterData['artists'] is List &&
                masterData['artists'].isNotEmpty) {
              artistName = masterData['artists'].first['name'];
            }

            final albumName = masterData['title'];

            if (artistName != null &&
                artistName.isNotEmpty &&
                albumName != null &&
                albumName.isNotEmpty) {
              Logging.severe('FOUND ALBUM INFO: "$albumName" by "$artistName"');
              Logging.severe('SEARCHING OTHER PLATFORMS for this album...');

              final platformFactory = PlatformServiceFactory();

              // Try each platform in order of preference
              final platforms = ['apple_music', 'spotify', 'deezer'];

              for (final platform in platforms) {
                if (platformFactory.isPlatformSupported(platform)) {
                  Logging.severe(
                      'SEARCHING $platform for "$albumName" by "$artistName"');
                  final service = platformFactory.getService(platform);
                  final platformUrl =
                      await service.findAlbumUrl(artistName, albumName);

                  if (platformUrl != null) {
                    Logging.severe('$platform MATCH FOUND: $platformUrl');
                    final platformDetails =
                        await service.fetchAlbumDetails(platformUrl);

                    if (platformDetails != null) {
                      // Count tracks with durations
                      int tracksWithDurations = 0;
                      if (platformDetails['tracks'] is List) {
                        for (var track in platformDetails['tracks']) {
                          if ((track['trackTimeMillis'] ?? 0) > 0) {
                            tracksWithDurations++;
                          }
                        }
                      }

                      Logging.severe(
                          '$platform DATA: Has $tracksWithDurations tracks with durations');

                      if (tracksWithDurations > 0) {
                        Logging.severe(
                            '$platform SUCCESS: Found tracks with durations');

                        // Save this platform match for future use
                        await db.insert(
                          'platform_matches',
                          {
                            'album_id': id,
                            'platform': platform,
                            'url': platformUrl,
                            'verified': 1,
                            'timestamp': DateTime.now().toIso8601String(),
                          },
                          conflictAlgorithm: ConflictAlgorithm.replace,
                        );

                        // Fix the ID and URL to match Discogs
                        platformDetails['id'] = 'master-$id';
                        platformDetails['collectionId'] = 'master-$id';
                        platformDetails['url'] = url;
                        platformDetails['platform'] =
                            'discogs'; // Keep it as Discogs

                        // Store these tracks in our database for future use
                        if (platformDetails['tracks'] is List) {
                          await storeTrackNames(
                              platformDetails['id'].toString(),
                              List<Map<String, dynamic>>.from(
                                  platformDetails['tracks']));
                        }

                        return platformDetails;
                      }
                    }
                  } else {
                    Logging.severe(
                        '$platform: No match found for "$albumName" by "$artistName"');
                  }
                }
              }
            }
          } else {
            Logging.severe('MASTER API ERROR: HTTP ${response.statusCode}');
          }
        } catch (e) {
          Logging.severe('ERROR searching other platforms: $e');
        }
      }

      Logging.severe('NO ALTERNATE PLATFORM FOUND with valid data');
      return null;
    } catch (e, stack) {
      Logging.severe('ERROR in _tryAlternatePlatform', e, stack);
      return null;
    }
  }

  // Add a new method to try a specific release ID for a master
  Future<Map<String, dynamic>?> getSpecificRelease(String releaseId) async {
    try {
      final releaseUrl = 'https://www.discogs.com/release/$releaseId';
      Logging.severe('Trying specific release ID: $releaseId');

      final apiUrl = '$_baseUrl/releases/$releaseId';
      final apiUrlWithAuth =
          '$apiUrl?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}';

      final response = await http.get(Uri.parse(apiUrlWithAuth));

      if (response.statusCode == 200) {
        return _processDiscogsResponse(
            response.body, releaseUrl, 'release', releaseId);
      } else {
        Logging.severe(
            'API error fetching specific release $releaseId: ${response.statusCode}');
        return null;
      }
    } catch (e, stack) {
      Logging.severe('Error fetching specific release', e, stack);
      return null;
    }
  }

  // Add a new method to create album with tracks from ratings when we have track names but no durations
  Future<Map<String, dynamic>> _createAlbumWithTracksFromRatings(
      String albumId, String url) async {
    Logging.severe('Creating tracks from ratings');

    try {
      // Get the album name and artist from the URL
      String artistName = 'Unknown Artist';
      String albumName = 'Unknown Album';

      // Try to extract from database first
      final db = await getDatabaseInstance();
      final albumData = await db.query(
        'albums',
        where: 'id = ?',
        whereArgs: [albumId],
      );

      if (albumData.isNotEmpty) {
        artistName = albumData.first['artist'] as String? ?? artistName;
        albumName = albumData.first['name'] as String? ?? albumName;
      }

      Logging.severe(
          'Creating tracks for album: $albumName by $artistName (ID: $albumId)');

      // Get the ratings
      final ratingsData = await db.query(
        'ratings',
        where: 'album_id = ?',
        whereArgs: [albumId],
      );

      // Create a map of track ID to rating
      final Map<String, double> ratingsMap = {};
      for (var rating in ratingsData) {
        final trackId = rating['track_id'] as String?;
        final ratingValue = rating['rating'] as double?;

        if (trackId != null && ratingValue != null) {
          ratingsMap[trackId] = ratingValue;
        }
      }

      Logging.severe('Available ratings: $ratingsMap');

      // Get track info from database
      final trackData = await db.query(
        'tracks',
        where: 'album_id = ?',
        whereArgs: [albumId],
      );

      List<Map<String, dynamic>> tracks = [];

      if (trackData.isNotEmpty) {
        Logging.severe(
            'Retrieved ${trackData.length} tracks from database for album $albumId');

        // Print track info for debugging
        for (var track in trackData) {
          Logging.severe(
              'Track from DB: ID=${track['id']}, Name=${track['name']}, Position=${track['position']}');
        }

        // Create track objects
        for (var track in trackData) {
          final trackId = track['id'] as String?;
          final trackName = track['name'] as String?;
          final position = track['position'] as int?;

          if (trackId != null && trackName != null) {
            final rating = ratingsMap[trackId];

            tracks.add({
              'trackId': trackId,
              'trackName': trackName,
              'trackNumber': position ?? 0,
              'trackTimeMillis': 0, // We don't have duration info
              'rating': rating, // Store the rating directly in track data
            });
          }
        }

        Logging.severe(
            'Found ${tracks.length} tracks in database for album $albumId');
      } else {
        // If no track data, create tracks from rating IDs
        int position = 1;
        for (var trackId in ratingsMap.keys) {
          tracks.add({
            'trackId': trackId,
            'trackName': 'Track $position',
            'trackNumber': position,
            'trackTimeMillis': 0,
            'rating': ratingsMap[trackId],
          });
          position++;
        }
      }

      // Create a simplified album object
      return {
        'id': albumId,
        'collectionId': albumId,
        'name': albumName,
        'collectionName': albumName,
        'artist': artistName,
        'artistName': artistName,
        'artworkUrl': '',
        'artworkUrl100': '',
        'url': url,
        'platform': 'discogs',
        'tracks': tracks,
      };
    } catch (e, stack) {
      Logging.severe('Error creating album with tracks from ratings', e, stack);

      // Return minimal album to avoid crashes
      return {
        'id': albumId,
        'collectionId': albumId,
        'name': 'Unknown Album',
        'collectionName': 'Unknown Album',
        'artist': 'Unknown Artist',
        'artistName': 'Unknown Artist',
        'artworkUrl': '',
        'artworkUrl100': '',
        'url': url,
        'platform': 'discogs',
        'tracks': [],
      };
    }
  }

  // Add a method to handle fallback for failed cached releases
  Future<void> _removeInvalidReleaseMapping(
      String masterId, String releaseId) async {
    try {
      final db = await getDatabaseInstance();
      Logging.severe(
          'REMOVING INVALID MAPPING: master $masterId -> release $releaseId');

      await db.delete(
        'master_release_map',
        where: 'master_id = ? AND release_id = ?',
        whereArgs: [masterId, releaseId],
      );

      // Add to 404 cache
      _addRecent404('release-$releaseId');

      Logging.severe('REMOVED invalid release mapping from database');
    } catch (e) {
      Logging.severe('Error removing invalid release mapping: $e');
    }
  }
}
