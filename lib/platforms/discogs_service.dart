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

      final versionsUrl = '$_baseUrl/masters/$masterId/versions';
      final versionsResponse = await http.get(Uri.parse(
          '$versionsUrl?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}'));

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
          'Trying to find a release with track durations for master: $masterId');

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
            'Found cached release ID: $cachedReleaseId for master $masterId');

        // Get all recent 404 errors from a memory cache or temporary store
        final recent404s = _getRecent404s();

        // If this URL recently gave us a 404, don't try it again
        if (recent404s.contains('release-$cachedReleaseId')) {
          Logging.severe(
              'Cached release $cachedReleaseId recently returned 404, skipping');
        } else {
          // Try the cached release URL
          final releaseUrl = 'https://www.discogs.com/release/$cachedReleaseId';
          final releaseDetails = await fetchAlbumDetails(releaseUrl);

          if (releaseDetails != null &&
              _hasValidTrackDurations(releaseDetails) &&
              _hasValidTrackNames(releaseDetails)) {
            Logging.severe(
                'Cached release $cachedReleaseId has valid durations and track names');
            return releaseDetails;
          } else {
            Logging.severe(
                'Cached release $cachedReleaseId no longer valid or missing durations/names');
            // Remove this invalid mapping to avoid trying it again
            await db.delete(
              'master_release_map',
              where: 'master_id = ? AND release_id = ?',
              whereArgs: [masterId, cachedReleaseId],
            );
            // Add to 404 list to avoid trying again in this session
            _addRecent404('release-$cachedReleaseId');
          }
        }
      }

      // Get all versions from the master
      final versionsUrl = '$_baseUrl/masters/$masterId/versions';
      final versionsResponse = await http.get(Uri.parse(
          '$versionsUrl?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}'));

      if (versionsResponse.statusCode != 200) {
        Logging.severe(
            'Failed to get versions for master $masterId: ${versionsResponse.statusCode}');
        return null;
      }

      final versionsData = jsonDecode(versionsResponse.body);
      if (versionsData['versions'] == null ||
          versionsData['versions'] is! List ||
          versionsData['versions'].isEmpty) {
        Logging.severe('No versions found for master $masterId');
        return null;
      }

      final List<dynamic> versions = versionsData['versions'];
      Logging.severe('Found ${versions.length} releases of master $masterId');

      // Score and sort versions by potential quality
      final List<Map<String, dynamic>> scoredVersions = [];
      for (var version in versions) {
        int score = 0;
        final format = version['format']?.toString().toLowerCase() ?? '';
        final country = version['country']?.toString() ?? '';

        // Prioritize digital formats which tend to have better track info
        if (format.contains('flac') ||
            format.contains('alac') ||
            format.contains('mp3')) {
          score += 90;
        }
        // Then vinyl and CD
        else if (format.contains('vinyl') || format.contains('lp')) {
          score += 70;
        } else if (format.contains('cd')) {
          score += 80;
        }

        // Prioritize certain countries that tend to have better track info
        if (country.contains('US') ||
            country.contains('UK') ||
            country.contains('Japan')) {
          score += 10;
        }

        // Format-specific boosts
        if (format.contains('digital')) score += 5;
        if (format.contains('remaster')) score += 5;

        // Log the version with its score
        Logging.severe(
            '  ${scoredVersions.length + 1}. releases/${version['id']} - Score: $score - Format: $format, Country: $country');

        scoredVersions.add({'version': version, 'score': score});
      }

      // Sort by score (highest first)
      scoredVersions.sort((a, b) => b['score'].compareTo(a['score']));

      // Take top 12 or however many are available
      final topVersions = scoredVersions.take(12).toList();

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
            'Trying $attempts/${topVersions.length}: releases/$releaseId (Format: $format)');

        // Check if this URL recently gave us a 404
        if (_getRecent404s().contains('release-$releaseId')) {
          Logging.severe('Release $releaseId recently returned 404, skipping');
          continue;
        }

        final releaseUrl = 'https://www.discogs.com/release/$releaseId';
        try {
          // IMPORTANT: Use a direct API call here to ensure we get track details
          final apiUrl = '$_baseUrl/releases/$releaseId';
          final apiUrlWithAuth =
              '$apiUrl?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}';

          Logging.severe('Directly fetching from Discogs API: $apiUrl');
          final response = await http.get(Uri.parse(apiUrlWithAuth));

          if (response.statusCode == 200) {
            // Process release details directly
            final releaseDetails = _processDiscogsResponse(
                response.body, releaseUrl, 'release', releaseId);

            // Check if this release has track durations and names
            final hasDurations = _hasValidTrackDurations(releaseDetails);
            final hasNames = _hasValidTrackNames(releaseDetails);
            Logging.severe(
                'Version $releaseId has ${releaseDetails?['tracks']?.length ?? 0} tracks with ${(hasDurations ? 'has' : 'missing')} durations and ${(hasNames ? 'valid' : 'invalid')} names');

            if (hasDurations && hasNames) {
              // Success! Save this mapping for future use
              await saveValidRelease(masterId, releaseId);

              // Important: Make sure track IDs match the master ID for ratings to work!
              if (releaseDetails != null && releaseDetails['tracks'] is List) {
                // Create new tracks with proper IDs that match the master format
                final tracks =
                    List<Map<String, dynamic>>.from(releaseDetails['tracks']);
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
              }

              // Log what we found
              Logging.severe(
                  'Found valid release $releaseId with track durations and names for master $masterId');
              return releaseDetails;
            } else {
              Logging.severe(
                  'Release $releaseId has incomplete track info (durations: $hasDurations, names: $hasNames), skipping');
            }
          } else {
            Logging.severe(
                'API error for release $releaseId: ${response.statusCode}');
            _addRecent404('release-$releaseId');
          }
        } catch (e) {
          Logging.severe('Error fetching release $releaseId: $e');
          // Track this as a problematic URL
          _addRecent404('release-$releaseId');
        }
      }

      // Try to get info from other music platforms like Spotify using platform matches
      Logging.severe(
          'Could not find any Discogs release with valid track info for master $masterId, checking other platforms');
      return await _tryAlternatePlatform(
          'https://www.discogs.com/master/$masterId');
    } catch (e, stack) {
      Logging.severe('Error in getMasterWithTrackDurations', e, stack);
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

  // Helper method to check if a release has valid track durations
  bool _hasValidTrackDurations(Map<String, dynamic>? releaseDetails) {
    if (releaseDetails == null ||
        releaseDetails['tracks'] == null ||
        releaseDetails['tracks'] is! List ||
        releaseDetails['tracks'].isEmpty) {
      return false;
    }

    // Check if at least 50% of tracks have durations
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

    // Return true if at least half the tracks have durations
    return percentage >= 0.5;
  }

  @override
  Future<String?> findAlbumUrl(String artist, String albumName) async {
    try {
      Logging.severe('Searching for Discogs URL: "$albumName" by "$artist"');

      // Normalize names for better matching
      final normalizedArtist = normalizeForComparison(artist);
      final normalizedAlbum = normalizeForComparison(albumName);

      // Construct search query
      final query = Uri.encodeComponent('$artist $albumName');
      final url = Uri.parse(
          '$_baseUrl/database/search?q=$query&type=release,master&per_page=20'
          '&key=${ApiKeys.discogsConsumerKey}'
          '&secret=${ApiKeys.discogsConsumerSecret}');

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
      // Similar implementation to findAlbumUrl, but just return true/false
      final normalizedArtist = normalizeForComparison(artist);
      final normalizedAlbum = normalizeForComparison(albumName);

      final query = Uri.encodeComponent('$artist $albumName');
      final url = Uri.parse(
          '$_baseUrl/database/search?q=$query&type=release&per_page=10'
          '&key=${ApiKeys.discogsConsumerKey}'
          '&secret=${ApiKeys.discogsConsumerSecret}');

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

  // Override the fetchAlbumDetails method to use Apple Music as fallback for track durations
  @override
  Future<Map<String, dynamic>?> fetchAlbumDetails(String url) async {
    try {
      Logging.severe('Fetching Discogs album details from URL: $url');

      // Extract the release or master ID from the URL
      String? id;
      String type = 'release'; // Default to release

      if (url.contains('/release/')) {
        final regExp = RegExp(r'/release/(\d+)');
        final match = regExp.firstMatch(url);
        id = match?.group(1);
      } else if (url.contains('/master/')) {
        final regExp = RegExp(r'/master/(\d+)');
        final match = regExp.firstMatch(url);
        id = match?.group(1);
        type = 'master';
      }

      if (id == null) {
        Logging.severe('Could not extract ID from Discogs URL: $url');
        return null;
      }

      // The albumId we'll use for database queries
      final albumId = type == 'master' ? 'master-$id' : 'release-$id';

      // Check if we already have tracks with durations in the database
      final tracksFromDb = await _getTracksFromDatabase(albumId);
      bool hasDurations = false;

      if (tracksFromDb.isNotEmpty) {
        // Check if these tracks have durations
        for (var track in tracksFromDb) {
          if ((track['trackTimeMillis'] ?? 0) > 0) {
            hasDurations = true;
            break;
          }
        }

        if (hasDurations) {
          Logging.severe('Found tracks with durations in database, using them');

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
        }
      }

      // If this is a master URL, we should try to use the specific getMasterWithTrackDurations method
      if (type == 'master') {
        final masterWithDurations = await getMasterWithTrackDurations(id);
        if (masterWithDurations != null) {
          // Use the data from our specialized master lookup
          return masterWithDurations;
        }
      }

      // Try to fetch using the ID and type through the regular API
      String apiUrl = '$_baseUrl/$type/$id';
      apiUrl +=
          '?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}';

      final response = await http.get(Uri.parse(apiUrl));

      // If error and this is a master, try to find a working release version
      if (response.statusCode != 200 && type == 'master') {
        Logging.severe(
            'Error fetching master details (${response.statusCode}), trying to find a release version');

        // Use our improved method to try multiple releases
        final masterWithDurations = await getMasterWithTrackDurations(id);
        if (masterWithDurations != null) {
          // Log the tracks to verify they have names
          Logging.severe(
              'Found master with ${masterWithDurations['tracks'].length} tracks. Sample track: ${masterWithDurations['tracks'].isNotEmpty ? masterWithDurations['tracks'][0] : "No tracks"}');
          return masterWithDurations;
        }

        // If our improved method fails, try importing from another platform
        return await _tryAlternatePlatform(url);
      } else if (response.statusCode == 200) {
        // For successful responses
        final masterDetails =
            _processDiscogsResponse(response.body, url, type, id);

        // Log the original track names for debugging
        if (masterDetails != null &&
            masterDetails['tracks'] != null &&
            masterDetails['tracks'] is List) {
          Logging.severe(
              'Original response has ${masterDetails['tracks'].length} tracks. Sample track: ${masterDetails['tracks'].isNotEmpty ? masterDetails['tracks'][0] : "No tracks"}');
        }

        // If this is a master, check if it has track durations and names
        if (type == 'master' &&
            (!_hasValidTrackDurations(masterDetails) ||
                !_hasValidTrackNames(masterDetails))) {
          // Try to find a release with durations and real track names
          Logging.severe(
              'Master response has missing track info, looking for releases with complete info');
          final masterWithDurations = await getMasterWithTrackDurations(id);

          if (masterWithDurations != null) {
            // Use release data but keep original URL
            masterWithDurations['url'] = url;
            Logging.severe(
                'Found alternate release with ${masterWithDurations['tracks'].length} tracks. Sample track: ${masterWithDurations['tracks'].isNotEmpty ? masterWithDurations['tracks'][0] : "No tracks"}');
            return masterWithDurations;
          }

          // Try other platforms as last resort
          final alternatePlatform = await _tryAlternatePlatform(url);
          if (alternatePlatform != null) {
            return alternatePlatform;
          }
        }

        return masterDetails;
      }

      Logging.severe('Discogs API error: ${response.statusCode}');

      // Try to get track data from database if API call fails
      if (tracksFromDb.isNotEmpty) {
        Logging.severe(
            'Recovered ${tracksFromDb.length} tracks from database for album $albumId');

        // Construct a minimal album object with the tracks from DB
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
      }

      // Try all alternative platforms as a last resort
      return await _tryAlternatePlatform(url);
    } catch (e, stack) {
      Logging.severe('Error fetching Discogs album details', e, stack);
      return null;
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
        return null;
      }

      // Try to get album info from the database
      final db = await getDatabaseInstance();
      final results = await db.query(
        'platform_matches',
        where: 'album_id = ?',
        whereArgs: [id],
      );

      // Check if we have any matches for other platforms
      for (var match in results) {
        final platform = match['platform'] as String;
        final matchUrl = match['url'] as String?;

        if (platform != 'discogs' && matchUrl != null && matchUrl.isNotEmpty) {
          Logging.severe(
              'Found alternate platform match: $platform - $matchUrl');

          // Use PlatformServiceFactory to get the service for this platform
          try {
            final platformFactory = PlatformServiceFactory();
            if (platformFactory.isPlatformSupported(platform)) {
              final service = platformFactory.getService(platform);
              final albumDetails = await service.fetchAlbumDetails(matchUrl);

              if (albumDetails != null) {
                Logging.severe('Successfully fetched details from $platform');

                // Fix: Make sure we preserve the Discogs ID format
                albumDetails['id'] =
                    type == 'master' ? 'master-$id' : 'release-$id';
                albumDetails['collectionId'] = albumDetails['id'];
                albumDetails['url'] = url; // Keep original Discogs URL

                // Store these tracks in our database for future use
                if (albumDetails['tracks'] is List) {
                  await storeTrackNames(albumDetails['id'].toString(),
                      List<Map<String, dynamic>>.from(albumDetails['tracks']));
                }

                return albumDetails;
              }
            }
          } catch (e) {
            Logging.severe(
                'Error fetching from alternate platform $platform: $e');
          }
        }
      }

      // If no platform match in our database, try finding one via the album info
      if (type == 'master') {
        try {
          // Try to get basic album details to search other platforms
          final masterUrl = '$_baseUrl/masters/$id';
          final response = await http.get(Uri.parse(
              '$masterUrl?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}'));

          if (response.statusCode == 200) {
            final masterData = jsonDecode(response.body);
            final artistName = masterData['artists']?.first['name'] ?? '';
            final albumName = masterData['title'] ?? '';

            if (artistName.isNotEmpty && albumName.isNotEmpty) {
              // Try to find on other platforms
              Logging.severe(
                  'Searching other platforms for: $artistName - $albumName');

              final platformFactory = PlatformServiceFactory();

              // Try Apple Music first (best track data)
              if (platformFactory.isPlatformSupported('apple_music')) {
                final appleService = platformFactory.getService('apple_music');
                final appleUrl =
                    await appleService.findAlbumUrl(artistName, albumName);

                if (appleUrl != null) {
                  final appleDetails =
                      await appleService.fetchAlbumDetails(appleUrl);
                  if (appleDetails != null &&
                      _hasValidTrackDurations(appleDetails)) {
                    Logging.severe(
                        'Found Apple Music match with duration data');

                    // Save this platform match
                    await db.insert(
                      'platform_matches',
                      {
                        'album_id': id,
                        'platform': 'apple_music',
                        'url': appleUrl,
                        'verified': 1,
                        'timestamp': DateTime.now().toIso8601String(),
                      },
                      conflictAlgorithm: ConflictAlgorithm.replace,
                    );

                    // Fix the ID and URL to match Discogs
                    appleDetails['id'] = 'master-$id';
                    appleDetails['collectionId'] = 'master-$id';
                    appleDetails['url'] = url;
                    appleDetails['platform'] = 'discogs';

                    // Store these tracks in our database for future use
                    await storeTrackNames(
                        appleDetails['id'].toString(),
                        List<Map<String, dynamic>>.from(
                            appleDetails['tracks']));

                    return appleDetails;
                  }
                }
              }

              // Try Spotify next
              if (platformFactory.isPlatformSupported('spotify')) {
                final spotifyService = platformFactory.getService('spotify');
                final spotifyUrl =
                    await spotifyService.findAlbumUrl(artistName, albumName);

                if (spotifyUrl != null) {
                  final spotifyDetails =
                      await spotifyService.fetchAlbumDetails(spotifyUrl);
                  if (spotifyDetails != null &&
                      _hasValidTrackDurations(spotifyDetails)) {
                    Logging.severe('Found Spotify match with duration data');

                    // Save this platform match
                    await db.insert(
                      'platform_matches',
                      {
                        'album_id': id,
                        'platform': 'spotify',
                        'url': spotifyUrl,
                        'verified': 1,
                        'timestamp': DateTime.now().toIso8601String(),
                      },
                      conflictAlgorithm: ConflictAlgorithm.replace,
                    );

                    // Fix the ID and URL to match Discogs
                    spotifyDetails['id'] = 'master-$id';
                    spotifyDetails['collectionId'] = 'master-$id';
                    spotifyDetails['url'] = url;
                    spotifyDetails['platform'] = 'discogs';

                    // Store these tracks in our database for future use
                    await storeTrackNames(
                        spotifyDetails['id'].toString(),
                        List<Map<String, dynamic>>.from(
                            spotifyDetails['tracks']));

                    return spotifyDetails;
                  }
                }
              }

              // Try Deezer as last resort
              if (platformFactory.isPlatformSupported('deezer')) {
                final deezerService = platformFactory.getService('deezer');
                final deezerUrl =
                    await deezerService.findAlbumUrl(artistName, albumName);

                if (deezerUrl != null) {
                  final deezerDetails =
                      await deezerService.fetchAlbumDetails(deezerUrl);
                  if (deezerDetails != null &&
                      _hasValidTrackDurations(deezerDetails)) {
                    Logging.severe('Found Deezer match with duration data');

                    // Save this platform match
                    await db.insert(
                      'platform_matches',
                      {
                        'album_id': id,
                        'platform': 'deezer',
                        'url': deezerUrl,
                        'verified': 1,
                        'timestamp': DateTime.now().toIso8601String(),
                      },
                      conflictAlgorithm: ConflictAlgorithm.replace,
                    );

                    // Fix the ID and URL to match Discogs
                    deezerDetails['id'] = 'master-$id';
                    deezerDetails['collectionId'] = 'master-$id';
                    deezerDetails['url'] = url;
                    deezerDetails['platform'] = 'discogs';

                    // Store these tracks in our database for future use
                    await storeTrackNames(
                        deezerDetails['id'].toString(),
                        List<Map<String, dynamic>>.from(
                            deezerDetails['tracks']));

                    return deezerDetails;
                  }
                }
              }
            }
          }
        } catch (e) {
          Logging.severe('Error searching other platforms: $e');
        }
      }

      Logging.severe('No working alternate platform found');
      return null;
    } catch (e, stack) {
      Logging.severe('Error trying alternate platforms', e, stack);
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
}
