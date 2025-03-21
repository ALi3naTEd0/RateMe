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
    if (input.contains('music.apple.com') || input.contains('itunes.apple.com')) {
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
  static Future<List<Album>> searchAlbums(String query) async {
    final platform = detectPlatform(query);
    
    switch (platform) {
      case 'bandcamp':
        final album = await fetchBandcampAlbum(query);
        return album != null ? [album] : [];
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

  /// Search for albums on iTunes
  static Future<List<Album>> searchiTunesAlbums(String query) async {
    try {
      // 1. First search by general term
      final searchUrl = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
        '&entity=album&limit=50'
      );
      
      final searchResponse = await http.get(searchUrl);
      final searchData = jsonDecode(searchResponse.body);
      
      // Combine results with artist search
      final List<dynamic> results = searchData['results'];
      
      // Convert results to Album objects
      final List<Album> albums = [];
      for (var result in results) {
        if (result['wrapperType'] == 'collection' && 
            result['collectionType'] == 'Album') {
          try {
            // Fetch full album details
            final albumDetails = await fetchiTunesAlbumDetails(result['collectionId']);
            if (albumDetails != null) {
              albums.add(albumDetails);
            }
          } catch (e) {
            // If details fetch fails, create basic album from search result
            albums.add(Album(
              id: result['collectionId'],
              name: result['collectionName'],
              artist: result['artistName'],
              artworkUrl: result['artworkUrl100'],
              releaseDate: DateTime.parse(result['releaseDate']),
              platform: 'itunes',
              tracks: [],
            ));
          }
        }
      }
      
      return albums;
    } catch (e) {
      Logging.severe('Error searching iTunes albums', e);
      return [];
    }
  }

  /// Fetch detailed album information from iTunes
  static Future<Album?> fetchiTunesAlbumDetails(int albumId) async {
    try {
      final url = Uri.parse(
          'https://itunes.apple.com/lookup?id=$albumId&entity=song');
      final response = await http.get(url);
      final data = jsonDecode(response.body);
      
      if (data['results'].isEmpty) return null;
      
      // Get album info (first result)
      final albumInfo = data['results'][0];
      
      // Filter only audio tracks, excluding videos
      final trackList = data['results']
          .where((track) => 
            track['wrapperType'] == 'track' && 
            track['kind'] == 'song'
          )
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
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to load Bandcamp album');
      }
      
      final document = parse(response.body);
      
      // Extract album info from JSON-LD
      var ldJsonScript = document.querySelector('script[type="application/ld+json"]');
      if (ldJsonScript == null) {
        throw Exception('Could not find album data');
      }
      
      final ldJson = jsonDecode(ldJsonScript.text);
      
      // Extract album info
      String title = document
              .querySelector('meta[property="og:title"]')
              ?.attributes['content'] ??
          ldJson['name'] ??
          'Unknown Title';
      String artist = document
              .querySelector('meta[property="og:site_name"]')
              ?.attributes['content'] ??
          ldJson['byArtist']?['name'] ??
          'Unknown Artist';
      String artworkUrl = document
              .querySelector('meta[property="og:image"]')
              ?.attributes['content'] ??
          '';
      
      // Parse release date
      DateTime releaseDate;
      try {
        releaseDate = DateFormat("d MMMM yyyy HH:mm:ss 'GMT'").parse(ldJson['datePublished']);
      } catch (e) {
        try {
          releaseDate = DateTime.parse(ldJson['datePublished'].replaceAll(' GMT', 'Z'));
        } catch (e) {
          releaseDate = DateTime.now();
        }
      }
      
      // Extract album ID
      int albumId = int.tryParse(ldJson['@id']?.toString().split('/').last ?? '') ?? 
                   url.hashCode;
      
      // Extract tracks
      final List<Track> tracks = [];
      if (ldJson['track'] != null && ldJson['track']['itemListElement'] != null) {
        var trackItems = ldJson['track']['itemListElement'] as List;
        
        for (int i = 0; i < trackItems.length; i++) {
          var item = trackItems[i];
          var track = item['item'];
          var props = track['additionalProperty'] as List;
          
          var trackIdProp = props.firstWhere(
            (p) => p['name'] == 'track_id',
            orElse: () => {'value': null}
          );
          
          int trackId = trackIdProp['value'] ?? DateTime.now().millisecondsSinceEpoch + i;
          int position = item['position'] ?? i + 1;
          
          // Parse track duration
          String duration = track['duration'] ?? '';
          int durationMs = _parseDuration(duration);
          
          tracks.add(Track(
            id: trackId,
            name: track['name'],
            position: position,
            durationMs: durationMs,
            metadata: track,
          ));
        }
      }
      
      // Create unified album object
      return Album(
        id: albumId,
        name: title,
        artist: artist,
        artworkUrl: artworkUrl,
        releaseDate: releaseDate,
        platform: 'bandcamp',
        url: url,
        tracks: tracks,
        metadata: ldJson,
      );
    } catch (e) {
      Logging.severe('Error fetching Bandcamp album', e);
      return null;
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
        if (parts.length >= 3) {  // H:M:S
          totalMillis = ((parts[0] * 3600) + (parts[1] * 60) + parts[2]) * 1000;
        } else if (parts.length == 2) {  // M:S
          totalMillis = ((parts[0] * 60) + parts[1]) * 1000;
        } else if (parts.length == 1) {  // S
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
