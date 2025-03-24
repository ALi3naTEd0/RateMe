import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'album_model.dart';
import 'logging.dart';

/// Service to handle interactions with different music platforms
class PlatformService {
  /// Detect platform from URL or search term
  static String detectPlatform(String input) {
    if (input.contains('music.apple.com') ||
        input.contains('itunes.apple.com')) {
      return 'itunes';
    } else if (input.contains('bandcamp.com')) {
      return 'bandcamp';
    } else if (input.contains('spotify.com')) {
      return 'spotify';
    } else if (input.contains('deezer.com')) {
      return 'deezer';
    } else {
      // Default to iTunes for search terms
      return 'itunes';
    }
  }

  /// Search for albums across all platforms
  static Future<List<dynamic>> searchAlbums(String query) async {
    if (query.isEmpty) return [];

    // Handle iTunes/Apple Music URLs
    if (query.contains('music.apple.com') ||
        query.contains('itunes.apple.com')) {
      try {
        final uri = Uri.parse(query);
        final pathSegments = uri.pathSegments;

        String? collectionId;
        if (pathSegments.contains('album')) {
          final albumIdIndex = pathSegments.indexOf('album') + 2;
          if (albumIdIndex < pathSegments.length) {
            collectionId = pathSegments[albumIdIndex].split('?').first;
          }
        } else {
          collectionId = uri.queryParameters['i'] ?? uri.queryParameters['id'];
        }

        if (collectionId != null) {
          final url = Uri.parse(
              'https://itunes.apple.com/lookup?id=$collectionId&entity=song');
          final response = await http.get(url);
          final data = jsonDecode(response.body);

          if (data['results'] != null && data['results'].isNotEmpty) {
            // Get album info (first result)
            final albumInfo = data['results'][0];

            // Get tracks (remaining results)
            final tracks = data['results']
                .skip(1) // Skip the first result (album info)
                .where((item) =>
                    item['wrapperType'] == 'track' && item['kind'] == 'song')
                .toList();

            // Add tracks to album info
            albumInfo['tracks'] = tracks;

            // Return just the album with its tracks
            return [albumInfo];
          }
        }
      } catch (e) {
        Logging.severe('Error processing iTunes/Apple Music URL', e);
      }
      return [];
    }

    final platform = detectPlatform(query);

    switch (platform) {
      case 'bandcamp':
        final album = await fetchBandcampAlbum(query);
        return album != null
            ? [
                {
                  'collectionName': album.name,
                  'artistName': album.artist,
                  'artworkUrl100': album.artworkUrl,
                  'collectionId': album.id,
                  'url': album.url,
                  'platform': 'bandcamp',
                  'releaseDate': album.releaseDate.toIso8601String(),
                  'wrapperType': 'collection',
                  'collectionType': 'Album',
                  'trackCount': album.tracks.length,
                  'tracks': album.tracks
                      .map((track) => ({
                            'trackId': track.id,
                            'trackNumber': track.position,
                            'trackName': track.name,
                            'trackTimeMillis': track.durationMs,
                            'kind': 'song',
                            'wrapperType': 'track',
                          }))
                      .toList(),
                }
              ]
            : [];
      case 'spotify':
        // TODO: Implement Spotify search
        throw UnimplementedError('Spotify search not implemented yet');
      case 'deezer':
        // TODO: Implement Deezer search
        throw UnimplementedError('Deezer search not implemented yet');
      case 'itunes':
      default:
        return await searchiTunesAlbums(query);
    }
  }

  /// Search for albums on iTunes with improved artist search
  static Future<List<dynamic>> searchiTunesAlbums(String query) async {
    try {
      Logging.severe('Starting iTunes search for query: "$query"');

      // 1. Perform multiple search queries for better coverage
      final responses = await Future.wait([
        // General search - highest relevance but may miss artist-specific results
        http.get(Uri.parse(
            'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
            '&entity=album&limit=50')),

        // Artist-specific search - better for exact artist matches
        http.get(Uri.parse(
            'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
            '&attribute=artistTerm&entity=album&limit=100')),

        // Album name search - better for exact album title matches
        http.get(Uri.parse(
            'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
            '&attribute=albumTerm&entity=album&limit=25')),
      ]);

      // 2. Collect and merge all search results
      final Map<int, dynamic> allAlbums = {};

      // Process results from each search
      for (var response in responses) {
        final data = jsonDecode(response.body);
        for (var item in data['results'] ?? []) {
          if (item['wrapperType'] == 'collection' &&
              item['collectionType'] == 'Album') {
            // Use collection ID as key to avoid duplicates
            allAlbums[item['collectionId']] = item;
          }
        }
      }

      // Convert back to list
      final List<dynamic> albums = allAlbums.values.toList();

      // Add debug logs for search results
      Logging.severe('iTunes raw search returned ${albums.length} albums');

      // Sample the first result for debugging
      if (albums.isNotEmpty) {
        Logging.severe('First album sample: ${jsonEncode({
              'id': albums[0]['collectionId'],
              'name': albums[0]['collectionName'],
              'artist': albums[0]['artistName'],
              'explicitness': albums[0]['collectionExplicitness'],
              'releaseDate': albums[0]['releaseDate'],
            })}');
      }

      // 3. Sort by relevance: exact artist matches first, then by release date
      final queryLower = query.toLowerCase();
      final exactArtistMatches = <dynamic>[];
      final partialArtistMatches = <dynamic>[];
      final otherResults = <dynamic>[];

      for (var album in albums) {
        String artistName = album['artistName']?.toString().toLowerCase() ?? '';
        String albumName =
            album['collectionName']?.toString().toLowerCase() ?? '';

        // Process clean/explicit versions
        if (album['collectionExplicitness'] == 'cleaned' &&
            !album['collectionName'].toString().endsWith(' (Clean)')) {
          album = Map<String, dynamic>.from(album);
          album['collectionName'] = "${album['collectionName']} (Clean)";
        }

        // Sort into appropriate category
        if (artistName == queryLower) {
          exactArtistMatches.add(album);
        } else if (artistName.contains(queryLower) ||
            albumName.contains(queryLower)) {
          partialArtistMatches.add(album);
        } else {
          otherResults.add(album);
        }
      }

      // Sort each group by release date (newest first)
      for (var group in [
        exactArtistMatches,
        partialArtistMatches,
        otherResults
      ]) {
        group.sort((a, b) => DateTime.parse(b['releaseDate'])
            .compareTo(DateTime.parse(a['releaseDate'])));
      }

      // 4. Combine all sorted groups
      final sortedAlbums = [
        ...exactArtistMatches,
        ...partialArtistMatches,
        ...otherResults
      ];

      // 5. Fetch track details for top results
      const maxDetailedResults = 20; // Limit for performance
      final List<dynamic> detailedAlbums = [];

      for (int i = 0; i < sortedAlbums.length && i < maxDetailedResults; i++) {
        final album = sortedAlbums[i];
        try {
          Logging.severe(
              'Fetching details for album ID: ${album['collectionId']} - "${album['collectionName']}" by ${album['artistName']}');

          final url = Uri.parse(
              'https://itunes.apple.com/lookup?id=${album['collectionId']}&entity=song');
          final response = await http.get(url);
          final data = jsonDecode(response.body);

          Logging.severe(
              'iTunes lookup status: ${response.statusCode}, result count: ${data['resultCount']}');

          if (data['results'] != null && data['results'].isNotEmpty) {
            final albumInfo = data['results'][0];

            // Debug log the raw album info
            Logging.severe(
                'Raw album info for ${albumInfo['collectionName']}: ${jsonEncode({
                  'collectionId': albumInfo['collectionId'],
                  'colName': albumInfo['collectionName'],
                  'artworkUrl': albumInfo['artworkUrl100'],
                  'trackCount': albumInfo['trackCount'],
                  'releaseDate': albumInfo['releaseDate'],
                  'explicitness': albumInfo['collectionExplicitness'],
                  'hasView': albumInfo.containsKey('collectionViewUrl'),
                })}');

            // Ensure track list is properly created even if empty
            final tracks = data['results']
                .skip(1)
                .where((item) =>
                    item['wrapperType'] == 'track' && item['kind'] == 'song')
                .toList();

            Logging.severe(
                'Found ${tracks.length} tracks for album ID: ${album['collectionId']}');

            // Sample the first track for debugging if available
            if (tracks.isNotEmpty) {
              Logging.severe('First track sample: ${jsonEncode({
                    'trackId': tracks[0]['trackId'],
                    'trackName': tracks[0]['trackName'],
                    'trackNumber': tracks[0]['trackNumber'],
                    'duration': tracks[0]['trackTimeMillis'],
                  })}');
            }

            // Always add tracks array, even if empty
            albumInfo['tracks'] = tracks;

            // Make sure other critical fields are preserved
            if (album['collectionExplicitness'] == 'cleaned' ||
                album['collectionName'].toString().contains('(Clean)')) {
              final originalName = albumInfo['collectionName'];
              albumInfo['collectionName'] =
                  album['collectionName'].toString().endsWith(' (Clean)')
                      ? album['collectionName']
                      : "${album['collectionName']} (Clean)";
              albumInfo['collectionExplicitness'] = 'cleaned';

              // Log the clean version transformation
              Logging.severe(
                  'Transformed clean album name from "$originalName" to "${albumInfo['collectionName']}"');
            }

            // Ensure platform field exists
            albumInfo['platform'] = 'itunes';

            // Make sure URL field exists
            if (!albumInfo.containsKey('url') &&
                albumInfo.containsKey('collectionViewUrl')) {
              albumInfo['url'] = albumInfo['collectionViewUrl'];
            }

            detailedAlbums.add(albumInfo);
          } else {
            // If lookup fails, add the original album with empty tracks array
            Logging.severe(
                'No results found for album ID: ${album['collectionId']} - adding with empty tracks');
            album['tracks'] = [];
            album['platform'] = 'itunes'; // Ensure platform field exists
            detailedAlbums.add(album);
          }
        } catch (e, stack) {
          Logging.severe(
              'Error fetching tracks for album ID: ${album['collectionId']}',
              e,
              stack);
          // If track fetch fails, still add the album with empty tracks array
          album['tracks'] = [];
          album['platform'] = 'itunes'; // Ensure platform field exists
          detailedAlbums.add(album);
        }
      }

      // 6. Add remaining albums without detailed tracks
      if (sortedAlbums.length > maxDetailedResults) {
        for (int i = maxDetailedResults; i < sortedAlbums.length; i++) {
          final album = sortedAlbums[i];
          // Make sure each album has at least an empty tracks array
          album['tracks'] = [];
          detailedAlbums.add(album);
        }
      }

      // 7. If we have exact artist matches, also fetch their full discography
      if (exactArtistMatches.isNotEmpty) {
        try {
          final artistId = exactArtistMatches.first['artistId'];
          final discUrl = Uri.parse(
              'https://itunes.apple.com/lookup?id=$artistId&entity=album&limit=200');
          final discResponse = await http.get(discUrl);
          final discData = jsonDecode(discResponse.body);

          // Get album IDs already in our results to avoid duplicates
          final existingIds =
              detailedAlbums.map((a) => a['collectionId']).toSet();

          // Add missing albums from discography
          for (var item in discData['results'] ?? []) {
            if (item['wrapperType'] == 'collection' &&
                item['collectionType'] == 'Album' &&
                !existingIds.contains(item['collectionId'])) {
              // Mark clean versions
              if (item['collectionExplicitness'] == 'cleaned' &&
                  !item['collectionName'].toString().endsWith(' (Clean)')) {
                item = Map<String, dynamic>.from(item);
                item['collectionName'] = "${item['collectionName']} (Clean)";
              }

              detailedAlbums.add(item);
              existingIds.add(item['collectionId']);
            }
          }
        } catch (e) {
          Logging.severe('Error fetching artist discography', e);
          // Continue without discography if it fails
        }
      }

      Logging.severe(
          'iTunes search completed - returning ${detailedAlbums.length} albums');
      return detailedAlbums;
    } catch (e, stack) {
      Logging.severe('Error searching iTunes albums', e, stack);
      return [];
    }
  }

  /// Fetch detailed album information from iTunes
  static Future<Album?> fetchiTunesAlbumDetails(int albumId) async {
    try {
      final url =
          Uri.parse('https://itunes.apple.com/lookup?id=$albumId&entity=song');
      final response = await http.get(url);
      final data = jsonDecode(response.body);

      if (data['results'].isEmpty) return null;

      // Get album info (first result)
      final albumInfo = data['results'][0];

      // Filter only audio tracks, excluding videos
      final trackList = data['results']
          .where((track) =>
              track['wrapperType'] == 'track' && track['kind'] == 'song')
          .toList();

      // Convert tracks to unified model
      final List<Track> tracks = [];
      for (var trackData in trackList) {
        tracks.add(Track(
          id: trackData['trackId'],
          name: trackData['trackName'],
          position: trackData['trackNumber'],
          durationMs: trackData['trackTimeMillis'] ?? 0,
          metadata: trackData,
        ));
      }

      // Create unified album object
      return Album(
        id: albumInfo['collectionId'],
        name: albumInfo['collectionName'],
        artist: albumInfo['artistName'],
        artworkUrl: albumInfo['artworkUrl100'],
        releaseDate: DateTime.parse(albumInfo['releaseDate']),
        platform: 'itunes',
        url: albumInfo['collectionViewUrl'] ?? '', // Add this line
        tracks: tracks,
        metadata: albumInfo,
      );
    } catch (e) {
      Logging.severe('Error fetching iTunes album details', e);
      return null;
    }
  }

  /// Fetch Bandcamp album
  static Future<Album?> fetchBandcampAlbum(String url) async {
    try {
      Logging.severe('BANDCAMP: Starting album fetch for URL: $url');
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to load Bandcamp album');
      }

      final document = parse(response.body);

      // Extract album info from JSON-LD
      var ldJsonScript =
          document.querySelector('script[type="application/ld+json"]');
      if (ldJsonScript == null) {
        Logging.severe(
            'BANDCAMP: No JSON-LD script found, trying fallback methods');
        throw Exception('Could not find album data');
      }

      final ldJson = jsonDecode(ldJsonScript.text);
      Logging.severe('BANDCAMP: Successfully parsed JSON-LD data');

      // Extract album info with detailed logging
      String title = document
              .querySelector('meta[property="og:title"]')
              ?.attributes['content'] ??
          ldJson['name'] ??
          'Unknown Title';
      Logging.severe('BANDCAMP: Extracted title: $title');

      String artist = document
              .querySelector('meta[property="og:site_name"]')
              ?.attributes['content'] ??
          ldJson['byArtist']?['name'] ??
          'Unknown Artist';
      Logging.severe('BANDCAMP: Extracted artist: $artist');

      String artworkUrl = document
              .querySelector('meta[property="og:image"]')
              ?.attributes['content'] ??
          '';
      Logging.severe('BANDCAMP: Extracted artwork URL: $artworkUrl');

      // Parse release date
      DateTime releaseDate;
      try {
        Logging.severe(
            'BANDCAMP: Parsing release date from: ${ldJson['datePublished']}');
        releaseDate = DateFormat("d MMMM yyyy HH:mm:ss 'GMT'")
            .parse(ldJson['datePublished']);
      } catch (e) {
        try {
          releaseDate =
              DateTime.parse(ldJson['datePublished'].replaceAll(' GMT', 'Z'));
        } catch (e) {
          Logging.severe(
              'BANDCAMP: Using fallback date due to parsing error: $e');
          releaseDate = DateTime.now();
        }
      }

      // Extract album ID with consistent generation
      int albumId = url.hashCode;
      try {
        if (ldJson['@id'] != null) {
          final idString = ldJson['@id'].toString().split('/').last;
          if (idString.isNotEmpty) {
            albumId = int.tryParse(idString) ?? url.hashCode;
          }
        }
      } catch (e) {
        Logging.severe('BANDCAMP: Using URL hash as album ID due to error: $e');
      }
      Logging.severe('BANDCAMP: Using album ID: $albumId');

      // Extract tracks with improved error handling
      final List<Track> tracks = [];
      if (ldJson['track'] != null &&
          ldJson['track']['itemListElement'] != null) {
        Logging.severe('BANDCAMP: Found track list in JSON-LD');
        var trackItems = ldJson['track']['itemListElement'] as List;
        Logging.severe('BANDCAMP: Processing ${trackItems.length} tracks');

        for (int i = 0; i < trackItems.length; i++) {
          try {
            var item = trackItems[i];
            var track = item['item'];

            // Generate consistent trackId - this is crucial for ratings to work
            int trackId = albumId * 1000 + (i + 1);
            try {
              var props = track['additionalProperty'] as List;
              var trackIdProp = props.firstWhere((p) => p['name'] == 'track_id',
                  orElse: () => {'value': null});

              if (trackIdProp['value'] != null) {
                trackId = trackIdProp['value'];
              }
            } catch (e) {
              Logging.severe(
                  'BANDCAMP: Error extracting track ID, using generated one: $e');
            }

            int position = item['position'] ?? i + 1;
            String trackName = track['name'] ?? 'Track ${i + 1}';

            // Use the new parser for duration
            String duration = track['duration'] ?? '';
            int durationMs = parseBandcampDuration(duration);

            tracks.add(Track(
              id: trackId,
              name: trackName,
              position: position,
              durationMs: durationMs, // This should now have correct duration
              metadata: {
                'trackId': trackId,
                'trackName': trackName,
                'trackNumber': position,
                'trackTimeMillis': durationMs,
                'duration': durationMs,
                'title': trackName,
              },
            ));

            Logging.severe(
                'BANDCAMP: Added track: $trackName (ID: $trackId, Position: $position)');
          } catch (e) {
            Logging.severe('BANDCAMP: Error processing track ${i + 1}: $e');
          }
        }
      } else {
        Logging.severe('BANDCAMP: No tracks found in JSON-LD');
      }

      // Create unified album object with consistent metadata
      Logging.severe(
          'BANDCAMP: Creating album object with ${tracks.length} tracks');
      return Album(
        id: albumId,
        name: title,
        artist: artist,
        artworkUrl: artworkUrl,
        releaseDate: releaseDate,
        platform: 'bandcamp',
        url: url,
        tracks: tracks,
        metadata: {
          'collectionId': albumId,
          'id': albumId,
          'collectionName': title,
          'artistName': artist,
          'artworkUrl100': artworkUrl,
          'url': url,
          'platform': 'bandcamp',
          'releaseDate': releaseDate.toIso8601String(),
          'tracks': tracks.map((t) => t.metadata).toList(),
        },
      );
    } catch (e, stack) {
      Logging.severe('BANDCAMP: Error fetching album', e, stack);
      return null;
    }
  }

  static int parseBandcampDuration(String duration) {
    try {
      // Handle Bandcamp's P00H02M23S format
      if (duration.startsWith('P')) {
        // Extract hours, minutes, seconds
        final regex = RegExp(r'P(\d+)H(\d+)M(\d+)S');
        final match = regex.firstMatch(duration);

        if (match != null) {
          final hours = int.parse(match.group(1) ?? '0');
          final minutes = int.parse(match.group(2) ?? '0');
          final seconds = int.parse(match.group(3) ?? '0');

          final totalMillis =
              ((hours * 3600) + (minutes * 60) + seconds) * 1000;
          Logging.severe('Parsed duration $duration to $totalMillis ms');
          return totalMillis;
        }
      }

      // Fallback to existing duration parsing for other formats
      return _parseDuration(duration);
    } catch (e) {
      Logging.severe('Error parsing Bandcamp duration: $duration', e);
      return 0;
    }
  }

  /// Parse ISO duration or time string to milliseconds
  static int _parseDuration(String isoDuration) {
    try {
      if (isoDuration.isEmpty) return 0;

      // Handle ISO duration format (PT1H2M3S)
      if (isoDuration.startsWith('PT')) {
        final regex = RegExp(r'(\d+)(?=[HMS])');
        final matches = regex.allMatches(isoDuration);
        final parts = matches.map((m) => int.parse(m.group(1)!)).toList();

        int totalMillis = 0;
        if (parts.length >= 3) {
          // H:M:S
          totalMillis = ((parts[0] * 3600) + (parts[1] * 60) + parts[2]) * 1000;
        } else if (parts.length == 2) {
          // M:S
          totalMillis = ((parts[0] * 60) + parts[1]) * 1000;
        } else if (parts.length == 1) {
          // S
          totalMillis = parts[0] * 1000;
        }
        return totalMillis;
      }

      // Handle MM:SS format
      final parts = isoDuration.split(':');
      if (parts.length == 2) {
        int minutes = int.tryParse(parts[0]) ?? 0;
        int seconds = int.tryParse(parts[1]) ?? 0;
        return (minutes * 60 + seconds) * 1000;
      }

      // Try parsing as seconds
      return (int.tryParse(isoDuration) ?? 0) * 1000;
    } catch (e) {
      Logging.severe('Error parsing duration: $isoDuration - $e');
      return 0;
    }
  }
}
