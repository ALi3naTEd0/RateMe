import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
        // Prioritize cover_big over cover_medium over cover_small
        if (data['cover_big'] != null && data['cover_big'].toString().isNotEmpty) {
          result['artworkUrl'] = data['cover_big'];
          result['artworkUrl100'] = data['cover_big']; // Use high-res for both fields
          Logging.severe('Updated Deezer artwork to high-res: ${data['cover_big']}');
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
                };
              }).toList();

              result['tracks'] = tracks;
              Logging.severe('Added ${tracks.length} tracks to Deezer album (no limit applied)');
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
}
