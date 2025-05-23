import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart'; // Import for potential date formatting needs
import 'dart:convert'; // Add this import for jsonDecode
import '../services/logging.dart'; // Import logging

/// Unified album model
class Album {
  final dynamic id; // Support both int and String IDs
  final String name;
  final String artist;
  final String artworkUrl;
  final String url;
  final String platform;
  final DateTime releaseDate;
  final Map<String, dynamic> metadata;
  List<Track> tracks; // <-- remove 'final' here

  Album({
    required this.id,
    required this.name,
    required this.artist,
    required this.artworkUrl,
    required this.url,
    required this.platform,
    required this.releaseDate,
    this.metadata = const {},
    this.tracks = const [],
  });

  // Getters for backward compatibility
  String get artistName => artist;
  String get collectionName => name;
  String get artworkUrl100 => artworkUrl;

  // Create from JSON (new format)
  factory Album.fromJson(Map<String, dynamic> json) {
    // Handle ID conversion
    dynamic albumId = json['id'] ?? json['collectionId'];
    if (albumId is String && int.tryParse(albumId) != null) {
      albumId = int.parse(albumId);
    }

    List<Track> parsedTracks = [];
    if (json['tracks'] != null && json['tracks'] is List) {
      for (var trackJson in json['tracks']) {
        try {
          if (trackJson is Map<String, dynamic>) {
            // Handle track ID conversion
            dynamic trackId = trackJson['id'] ?? trackJson['trackId'];
            if (trackId is int) {
              trackId = trackId.toString();
            }
            trackJson['id'] = trackId;
            parsedTracks.add(Track.fromJson(trackJson));
          }
        } catch (e) {
          debugPrint('Error parsing track: $e');
        }
      }
    }

    // Parse release date with enhanced handling for Deezer and other platforms
    DateTime releaseDate;
    final platform = json['platform']?.toString().toLowerCase() ?? 'unknown';
    final isDateLoading = json['dateLoading'] == true;
    final albumName = json['name'] ?? json['collectionName'] ?? 'Unknown Album';

    // Only log platform detection for non-Deezer platforms
    if (platform != 'deezer') {
      Logging.severe('Album model: Processing $platform album "$albumName"');
    }

    final rawDate = json['releaseDate'] ?? json['release_date'];

    // Only log this for non-Deezer platforms to reduce noise
    if (platform != 'deezer') {
      Logging.severe(
          'Album "$albumName": Parsing date field: $rawDate (platform: $platform, loading: $isDateLoading)');
    }

    try {
      // ENHANCED DEEZER DATE PARSING: First check for Deezer specific date fields
      if (platform == 'deezer') {
        // Try multiple date formats and locations for Deezer albums
        String? dateStr;

        // Option 1: Direct releaseDate field
        if (json['releaseDate'] != null) {
          dateStr = json['releaseDate'].toString();
        }
        // Option 2: Direct release_date field
        else if (json['release_date'] != null) {
          dateStr = json['release_date'].toString();
        }
        // Option 3: Check the data field which might contain the full album object from the API
        else if (json['data'] != null) {
          try {
            Map<String, dynamic>? dataMap;
            if (json['data'] is String) {
              dataMap = jsonDecode(json['data']);
            } else if (json['data'] is Map) {
              dataMap = Map<String, dynamic>.from(json['data']);
            }

            if (dataMap != null) {
              // Try both field naming conventions in the data field
              dateStr = dataMap['releaseDate']?.toString() ??
                  dataMap['release_date']?.toString();
            }
          } catch (e) {
            // Silent catch - just continue with other date parsing methods
          }
        }

        // Parse the date string if we found one
        if (dateStr != null && dateStr.isNotEmpty) {
          try {
            releaseDate = DateTime.parse(dateStr);
            // Skip the rest of the date parsing logic
            return Album(
              id: albumId ?? DateTime.now().millisecondsSinceEpoch,
              name: json['name'] ?? json['collectionName'] ?? 'Unknown Album',
              artist: json['artist'] ?? json['artistName'] ?? 'Unknown Artist',
              artworkUrl: _getBestArtworkUrl(json),
              url: json['url'] ?? json['collectionViewUrl'] ?? '',
              platform: platform,
              releaseDate: releaseDate,
              metadata: json,
              tracks: parsedTracks,
            );
          } catch (e) {
            // Silent catch - just continue with other date parsing methods
          }
        }
      }

      // If date is still loading or missing or explicitly marked as unknown, use a sensible fallback date
      if (isDateLoading ||
          rawDate == null ||
          rawDate == 'unknown' ||
          (rawDate is String && rawDate.isEmpty)) {
        // Use placeholder
        releaseDate = DateTime(2000, 1, 1);

        // Only log this for non-Deezer platforms
        if (platform != 'deezer') {
          Logging.severe(
              'Album.fromJson: Date unknown or missing, using placeholder date');
        }
      }
      // Check if the data field has the release date information (common for platforms with rich data)
      else if (rawDate is String &&
          platform == 'deezer' &&
          json['data'] != null) {
        // For Deezer, try to extract from the data field which may contain the proper date
        try {
          final dataJson =
              json['data'] is String ? jsonDecode(json['data']) : json['data'];

          if (dataJson is Map && dataJson['releaseDate'] != null) {
            final deezerDate = dataJson['releaseDate'];

            if (deezerDate is String) {
              // Deezer typically uses YYYY-MM-DD format
              releaseDate = DateTime.parse(deezerDate);
            } else {
              throw Exception('Deezer date not in expected format');
            }
          } else {
            throw Exception('No releaseDate in Deezer data field');
          }
        } catch (e) {
          // Try the original date as fallback
          if (DateTime.tryParse(rawDate) != null) {
            releaseDate = DateTime.parse(rawDate);
          } else {
            releaseDate = DateTime(2000, 1, 1);
          }
        }
      }
      // Normal date parsing for all other cases
      else if (rawDate is String) {
        // Handle YYYY-MM-DD format directly
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate)) {
          releaseDate = DateTime.parse(rawDate);
        }
        // Handle full ISO format
        else if (DateTime.tryParse(rawDate) != null) {
          releaseDate = DateTime.parse(rawDate);
        }
        // Handle potential year-only format (e.g., from Discogs search)
        else if (RegExp(r'^\d{4}$').hasMatch(rawDate)) {
          releaseDate = DateTime.parse('$rawDate-01-01'); // Default to Jan 1st
        } else {
          if (platform != 'deezer') {
            Logging.severe(
                'Album.fromJson: Unknown date string format "$rawDate", falling back.');
          }
          releaseDate = DateTime.now(); // Fallback for unknown string formats
        }
      } else if (rawDate is DateTime) {
        releaseDate = rawDate; // Already a DateTime object
      } else if (rawDate is int) {
        // Handle numeric timestamps (milliseconds since epoch)
        releaseDate = DateTime.fromMillisecondsSinceEpoch(rawDate);

        if (platform != 'deezer') {
          Logging.severe(
              'Album.fromJson: Parsed int timestamp to date: ${DateFormat('yyyy-MM-dd').format(releaseDate)}');
        }
      } else {
        if (platform != 'deezer') {
          Logging.severe(
              'Album.fromJson: releaseDate field has unexpected type ${rawDate.runtimeType}, falling back.');
        }
        releaseDate = DateTime.now(); // Fallback for wrong type
      }
    } catch (e, stack) {
      // Always log errors, regardless of platform
      Logging.severe(
          'Album.fromJson: Error parsing release date "$rawDate"', e, stack);
      // Use placeholder date on errors too
      releaseDate = DateTime(2000, 1, 1);
    }

    // Only log final parsed date for non-Deezer
    if (platform != 'deezer') {
      Logging.severe(
          'Album.fromJson: Final parsed releaseDate: ${DateFormat('yyyy-MM-dd').format(releaseDate)}');
    }

    // Ensure artwork URL is properly handled
    String artworkUrl = _getBestArtworkUrl(json);

    final album = Album(
      id: albumId ??
          DateTime.now().millisecondsSinceEpoch, // Use timestamp as fallback ID
      name: json['name'] ?? json['collectionName'] ?? 'Unknown Album',
      artist: json['artist'] ?? json['artistName'] ?? 'Unknown Artist',
      artworkUrl: artworkUrl,
      url: json['url'] ?? json['collectionViewUrl'] ?? '',
      platform: platform,
      releaseDate: releaseDate,
      metadata: json,
      tracks: parsedTracks,
    );

    // Reduce logging for Deezer albums
    if (platform == 'deezer') {
      // Log minimal info for Deezer albums
      Logging.severe('Created Album: ${album.name} by ${album.artist}');
    } else {
      // Keep detailed logging for other platforms
      Logging.severe('Created Album with:'
          ' name="${album.name}",'
          ' artist="${album.artist}",'
          ' platform="${album.platform}",'
          ' releaseDate="${DateFormat('yyyy-MM-dd').format(album.releaseDate)}",'
          ' artworkUrl="${album.artworkUrl}"');
    }

    return album;
  }

  // Helper method to get the best available artwork URL - simplified
  static String _getBestArtworkUrl(Map<String, dynamic> json) {
    String artworkUrl = '';

    if (json['artworkUrl'] != null &&
        json['artworkUrl'].toString().isNotEmpty) {
      artworkUrl = json['artworkUrl'].toString();
    } else if (json['artworkUrl100'] != null &&
        json['artworkUrl100'].toString().isNotEmpty) {
      artworkUrl = json['artworkUrl100'].toString();
    } else if (json['artwork_url'] != null &&
        json['artwork_url'].toString().isNotEmpty) {
      artworkUrl = json['artwork_url'].toString();
    }

    return artworkUrl;
  }

  // Create from legacy format (old data model)
  factory Album.fromLegacy(Map<String, dynamic> legacy) {
    // Extract tracks directly if available
    List<Track> tracks = [];
    if (legacy.containsKey('tracks') && legacy['tracks'] is List) {
      for (var trackData in legacy['tracks']) {
        try {
          // Only try to parse maps, not Track objects
          if (trackData is Map<String, dynamic>) {
            tracks.add(Track(
              id: trackData['trackId'] ?? trackData['id'] ?? 0,
              name: trackData['trackName'] ??
                  trackData['title'] ??
                  'Unknown Track',
              position: trackData['trackNumber'] ?? trackData['position'] ?? 0,
              durationMs:
                  trackData['trackTimeMillis'] ?? trackData['duration'] ?? 0,
              metadata: trackData,
            ));
          } else if (trackData is Track) {
            // If it's already a Track object, add it directly
            tracks.add(trackData);
          }
        } catch (e) {
          debugPrint('Error parsing legacy track: $e');
        }
      }
    }

    // Parse release date with better error handling and logging
    DateTime releaseDate;
    final rawDate = legacy['releaseDate'];
    Logging.severe(
        'Album.fromLegacy: Parsing releaseDate field: $rawDate (type: ${rawDate?.runtimeType})'); // Log raw date
    try {
      if (rawDate != null && rawDate is String && rawDate.isNotEmpty) {
        // Handle YYYY-MM-DD format directly
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate)) {
          releaseDate = DateTime.parse(rawDate);
        }
        // Handle full ISO format
        else if (DateTime.tryParse(rawDate) != null) {
          releaseDate = DateTime.parse(rawDate);
        }
        // Handle potential year-only format (e.g., from Discogs search)
        else if (RegExp(r'^\d{4}$').hasMatch(rawDate)) {
          releaseDate = DateTime.parse('$rawDate-01-01'); // Default to Jan 1st
        } else {
          Logging.severe(
              'Album.fromLegacy: Unknown date string format "$rawDate", falling back.');
          releaseDate = DateTime.now(); // Fallback for unknown string formats
        }
      } else {
        Logging.severe(
            'Album.fromLegacy: releaseDate field is null, empty, or wrong type, falling back.');
        releaseDate = DateTime.now(); // Fallback for null or wrong type
      }
    } catch (e, stack) {
      Logging.severe(
          'Album.fromLegacy: Error parsing release date "$rawDate"', e, stack);
      releaseDate = DateTime.now(); // Fallback on any parsing error
    }
    Logging.severe(
        'Album.fromLegacy: Parsed releaseDate: ${DateFormat('yyyy-MM-dd').format(releaseDate)}'); // Log parsed date

    // Determine platform - have better detection
    String platform = legacy['platform']?.toString() ?? 'unknown';

    // Try to detect platform from ID format or URL if not specified
    if (platform == 'unknown') {
      final albumId =
          legacy['id']?.toString() ?? legacy['collectionId']?.toString() ?? '';
      final url = legacy['url']?.toString() ?? '';

      if (url.contains('bandcamp.com')) {
        platform = 'bandcamp';
      } else if (albumId.isNotEmpty &&
          albumId.length > 10 &&
          !albumId.contains(RegExp(r'^[0-9]+$'))) {
        platform = 'spotify';
      } else if (albumId.isNotEmpty && int.tryParse(albumId) != null) {
        platform = 'itunes';
      }

      debugPrint('Auto-detected platform as $platform based on ID/URL format');
    }

    return Album(
      id: legacy['collectionId'] ??
          legacy['id'] ??
          DateTime.now().millisecondsSinceEpoch,
      name: legacy['collectionName'] ?? legacy['name'] ?? 'Unknown Album',
      artist: legacy['artistName'] ?? legacy['artist'] ?? 'Unknown Artist',
      artworkUrl: legacy['artworkUrl100'] ?? legacy['artworkUrl'] ?? '',
      url: legacy['url'] ?? legacy['collectionViewUrl'] ?? '',
      platform: platform,
      releaseDate: releaseDate,
      metadata: legacy,
      tracks: tracks,
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'artworkUrl': artworkUrl,
      'url': url,
      'platform': platform,
      'releaseDate': releaseDate.toIso8601String(),
      'modelVersion': 1,
      'metadata': metadata,
      'tracks': tracks.map((track) => track.toJson()).toList(),

      // Legacy field mappings for compatibility
      'collectionId': id,
      'collectionName': name,
      'artistName': artist,
      'artworkUrl100': artworkUrl,
    };
  }
}

/// Unified track model
class Track {
  final dynamic id;
  final String name;
  final int position;
  final int durationMs;
  final Map<String, dynamic> metadata;

  const Track({
    required this.id,
    required this.name,
    required this.position,
    this.durationMs = 0,
    this.metadata = const {},
  });

  // Create from JSON
  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] ?? json['trackId'] ?? 0,
      name:
          json['name'] ?? json['trackName'] ?? json['title'] ?? 'Unknown Track',
      position: json['position'] ?? json['trackNumber'] ?? 0,
      durationMs: json['durationMs'] ??
          json['trackTimeMillis'] ??
          json['duration'] ??
          0,
      metadata: json['metadata'] ?? {},
    );
  }

  // Create from legacy format
  factory Track.fromLegacy(Map<String, dynamic> legacy) {
    return Track(
      id: legacy['trackId'] ?? legacy['id'] ?? 0,
      name: legacy['trackName'] ?? legacy['title'] ?? 'Unknown Track',
      position: legacy['trackNumber'] ?? legacy['position'] ?? 0,
      durationMs: legacy['trackTimeMillis'] ?? legacy['duration'] ?? 0,
      metadata: legacy,
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'position': position,
      'durationMs': durationMs,
      'metadata': metadata,

      // Legacy field mappings for compatibility
      'trackId': id,
      'trackName': name,
      'trackNumber': position,
      'trackTimeMillis': durationMs,
      'title': name,
      'duration': durationMs,
    };
  }
}
