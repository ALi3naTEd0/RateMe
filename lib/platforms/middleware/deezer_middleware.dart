import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:rateme/core/services/search_service.dart';
import '../../core/services/logging.dart';
import '../../features/albums/details_page.dart';

/// Middleware for Deezer albums that handles fetching accurate release dates
/// before displaying the album details
class DeezerMiddleware {
  final String _baseUrl = 'https://api.deezer.com';

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
        'Starting Deezer album enhancement for: ${album['collectionName'] ?? album['name']}');

    try {
      // Fetch enhanced data with accurate dates
      final enhancedAlbum = await _enhanceDeezerAlbum(album);

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
      Logging.severe('Error enhancing Deezer album', e);

      // Close loading dialog on error
      navigatorState.pop();

      // Show details page with original data
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
              'Fetching release date...',
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

  /// Enhances a Deezer album with accurate release date information
  static Future<Map<String, dynamic>> _enhanceDeezerAlbum(
      Map<String, dynamic> album) async {
    try {
      final result = Map<String, dynamic>.from(album);

      // Extract the ID from the album
      final albumId = album['id'] ?? album['collectionId'];
      if (albumId == null) {
        Logging.severe('No album ID found for Deezer album');
        return result;
      }

      Logging.severe('Fetching accurate date for Deezer album ID: $albumId');

      // Fetch the complete album details to get the accurate release date
      final apiUrl = Uri.parse('https://api.deezer.com/album/$albumId');
      final response = await http.get(apiUrl);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Extract the release date
        if (data['release_date'] != null) {
          final releaseDate = data['release_date'].toString();
          result['releaseDate'] = releaseDate;
          Logging.severe('Updated Deezer album release date to: $releaseDate');
        } else {
          Logging.severe('No release date found in Deezer API response');
        }

        // Also update any missing album information
        if (data['title'] != null && data['title'].toString().isNotEmpty) {
          result['name'] = data['title'];
          result['collectionName'] = data['title'];
        }

        if (data['artist'] != null && data['artist']['name'] != null) {
          result['artist'] = data['artist']['name'];
          result['artistName'] = data['artist']['name'];
        }

        // Ensure we have proper artwork URLs
        if (data['cover_big'] != null) {
          result['artworkUrl'] = data['cover_big'];
        }

        if (data['cover_medium'] != null) {
          result['artworkUrl100'] = data['cover_medium'];
        }

        // CRITICAL FIX: Always ensure we have the highest quality artwork
        // Prioritize cover_xl (1000x1000) over cover_big (500x500) over cover_medium over cover_small
        if (data['cover_xl'] != null && data['cover_xl'].toString().isNotEmpty) {
          result['artworkUrl'] = data['cover_xl'];
          result['artworkUrl100'] = data['cover_xl']; // Use highest-res for both fields
          Logging.severe('Updated Deezer artwork to XL-res (1000x1000): ${data['cover_xl']}');
        } else if (data['cover_big'] != null && data['cover_big'].toString().isNotEmpty) {
          result['artworkUrl'] = data['cover_big'];
          result['artworkUrl100'] = data['cover_big']; // Use high-res for both fields
          Logging.severe('Updated Deezer artwork to big-res (500x500): ${data['cover_big']}');
        } else if (data['cover_medium'] != null && data['cover_medium'].toString().isNotEmpty) {
          result['artworkUrl'] = data['cover_medium'];
          result['artworkUrl100'] = data['cover_medium'];
          Logging.severe('Updated Deezer artwork to medium-res: ${data['cover_medium']}');
        } else if (data['cover_small'] != null && data['cover_small'].toString().isNotEmpty) {
          result['artworkUrl'] = data['cover_small'];
          result['artworkUrl100'] = data['cover_small'];
          Logging.severe('Updated Deezer artwork to small-res: ${data['cover_small']}');
        }

        // Check if we need to get tracks information too
        if (!album.containsKey('tracks') ||
            album['tracks'] == null ||
            (album['tracks'] is List && (album['tracks'] as List).isEmpty)) {
          Logging.severe('Fetching tracks for Deezer album');

          // Get track information with NO LIMIT to fetch ALL tracks
          final tracksUrl =
              Uri.parse('https://api.deezer.com/album/$albumId/tracks?limit=1000'); // Increased limit
          final tracksResponse = await http.get(tracksUrl);

          if (tracksResponse.statusCode == 200) {
            final tracksData = jsonDecode(tracksResponse.body);

            if (tracksData['data'] != null && tracksData['data'] is List) {
              // Format tracks in the standard format used by the app
              final tracks =
                  tracksData['data'].map<Map<String, dynamic>>((track) {
                return {
                  'trackId': track['id'],
                  'trackName': track['title'],
                  'trackNumber': track['track_position'],
                  'trackTimeMillis': track['duration'] *
                      1000, // Convert seconds to milliseconds
                  'artistName': track['artist']['name'],
                  // CRITICAL FIX: Add disk number for proper multi-disk sorting
                  'disc_number': track['disk_number'] ?? 1,
                  'disk_number': track['disk_number'] ?? 1, // Alternative field name
                  'diskNumber': track['disk_number'] ?? 1, // Camel case variant
                  'position': track['track_position'],
                  'id': track['id'],
                  'name': track['title'],
                  'durationMs': track['duration'] * 1000,
                };
              }).toList();

              result['tracks'] = tracks;
              Logging.severe('Added ${tracks.length} tracks to Deezer album with disk numbers');
              
              // Log first few tracks to verify disk numbering
              for (int i = 0; i < tracks.length && i < 5; i++) {
                final track = tracks[i];
                Logging.severe('Track ${i + 1}: "${track['trackName']}" - Disk: ${track['disc_number']}, Position: ${track['trackNumber']}');
              }
            }
          }
        }
      } else {
        Logging.severe('Deezer API error: ${response.statusCode}');
      }

      // Make sure we don't have the loading flag anymore
      result['dateLoading'] = false;

      return result;
    } catch (e) {
      Logging.severe('Error enhancing Deezer album', e);

      // Remove loading flag even on error
      final result = Map<String, dynamic>.from(album);
      result['dateLoading'] = false;

      return result;
    }
  }

  /// Fetches cover art from Deezer API or constructs URL from md5_image
  /// Returns the highest quality cover URL available, or null if not found
  static Future<String?> fetchCoverArt(String albumId) async {
    try {
      Logging.severe('=== FETCHING COVER ART FOR DEEZER ALBUM: $albumId ===');

      final apiUrl = Uri.parse('https://api.deezer.com/album/$albumId');
      Logging.severe('Calling API: $apiUrl');
      
      final response = await http.get(apiUrl);
      Logging.severe('API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Log EVERYTHING the API returns
        Logging.severe('=== FULL API RESPONSE ===');
        Logging.severe('Response keys: ${data.keys.toList()}');
        Logging.severe('cover: ${data['cover']}');
        Logging.severe('cover_small: ${data['cover_small']}');
        Logging.severe('cover_medium: ${data['cover_medium']}');
        Logging.severe('cover_big: ${data['cover_big']}');
        Logging.severe('cover_xl: ${data['cover_xl']}');
        Logging.severe('md5_image: ${data['md5_image']}');
        Logging.severe('=== END FULL API RESPONSE ===');

        // First try the direct URLs if available
        if (data['cover_xl'] != null && data['cover_xl'].toString().isNotEmpty && data['cover_xl'].toString() != 'null') {
          Logging.severe('Returning cover_xl: ${data['cover_xl']}');
          return data['cover_xl'];
        }
        
        if (data['cover_big'] != null && data['cover_big'].toString().isNotEmpty && data['cover_big'].toString() != 'null') {
          Logging.severe('Returning cover_big: ${data['cover_big']}');
          return data['cover_big'];
        }

        // If direct URLs are null/empty, construct from md5_image
        if (data['md5_image'] != null && data['md5_image'].toString().isNotEmpty) {
          final md5 = data['md5_image'].toString();
          Logging.severe('Direct URLs are null/empty, constructing from md5_image: $md5');
          
          // Deezer CDN URL format: https://e-cdns-images.dzcdn.net/images/cover/{md5}/1000x1000.jpg
          final cdnUrl = 'https://e-cdns-images.dzcdn.net/images/cover/$md5/1000x1000.jpg';
          Logging.severe('Constructed CDN URL: $cdnUrl');
          
          // RETURN IT IMMEDIATELY - don't verify with HEAD request
          Logging.severe('Returning constructed CDN URL without verification');
          return cdnUrl;
        }
        
        // Fallback to medium/small if available
        if (data['cover_medium'] != null && data['cover_medium'].toString().isNotEmpty && data['cover_medium'].toString() != 'null') {
          return data['cover_medium'];
        }
        if (data['cover_small'] != null && data['cover_small'].toString().isNotEmpty && data['cover_small'].toString() != 'null') {
          return data['cover_small'];
        }

        Logging.severe('ERROR: API returned no usable cover data');
        return null;
      } else {
        Logging.severe('API error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e, stack) {
      Logging.severe('Exception fetching Deezer cover art', e, stack);
      return null;
    }
  }

  /// Fetch album details from Deezer API
  /// Returns a Map with album details including releaseDate
  Future<Map<String, dynamic>?> getAlbumInfo(String albumId) async {
    try {
      final url = Uri.parse('$_baseUrl/album/$albumId');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Extract and format the release date from Deezer response
        if (data.containsKey('release_date')) {
          final releaseDate = data['release_date'];

          // Create a standardized album details map
          return {
            'releaseDate': releaseDate,
            'title': data['title'],
            'artist': data['artist']?['name'],
            'tracks': data['tracks']?['data'],
            // Include any other fields needed
          };
        }
      }

      Logging.severe('Failed to get Deezer album info: ${response.statusCode}');
      return null;
    } catch (e, stack) {
      Logging.severe('Error fetching Deezer album details', e, stack);
      return null;
    }
  }

  /// Fetches cover art with fallback to other platforms if Deezer fails
  /// Returns the highest quality cover URL available, or null if not found
  static Future<String?> fetchCoverArtWithFallback(String albumId, String albumName, String artistName) async {
    try {
      Logging.severe('=== FETCHING COVER ART WITH FALLBACK ===');
      Logging.severe('Album ID: $albumId, Name: $albumName, Artist: $artistName');

      // First try Deezer
      final deezerArtwork = await fetchCoverArt(albumId);
      if (deezerArtwork != null && deezerArtwork.isNotEmpty) {
        Logging.severe('Successfully fetched from Deezer');
        return deezerArtwork;
      }

      Logging.severe('Deezer failed, trying other platforms...');

      // Try Spotify
      try {
        final spotifyResult = await SearchService.searchSpotify('$artistName $albumName');
        if (spotifyResult != null && spotifyResult['results'] is List && spotifyResult['results'].isNotEmpty) {
          final firstResult = spotifyResult['results'][0];
          final artworkUrl = firstResult['artworkUrl'] ?? firstResult['artworkUrl100'];
          if (artworkUrl != null && artworkUrl.toString().isNotEmpty) {
            Logging.severe('Found artwork from Spotify: $artworkUrl');
            return artworkUrl.toString();
          }
        }
      } catch (e) {
        Logging.severe('Spotify search failed: $e');
      }

      // Try Apple Music
      try {
        final itunesResult = await SearchService.searchITunes('$artistName $albumName');
        if (itunesResult != null && itunesResult['results'] is List && itunesResult['results'].isNotEmpty) {
          final firstResult = itunesResult['results'][0];
          final artworkUrl = firstResult['artworkUrl100'] ?? firstResult['artworkUrl'];
          if (artworkUrl != null && artworkUrl.toString().isNotEmpty) {
            final highResUrl = artworkUrl.toString().replaceAll('100x100', '600x600');
            Logging.severe('Found artwork from Apple Music: $highResUrl');
            return highResUrl;
          }
        }
      } catch (e) {
        Logging.severe('Apple Music search failed: $e');
      }

      Logging.severe('All platforms failed to provide artwork');
      return null;
    } catch (e, stack) {
      Logging.severe('Exception in fetchCoverArtWithFallback', e, stack);
      return null;
    }
  }
}
