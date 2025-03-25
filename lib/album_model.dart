import 'package:flutter/foundation.dart';

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
  final List<Track> tracks;

  const Album({
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

    // Parse release date with better error handling
    DateTime releaseDate;
    try {
      if (json['releaseDate'] is String) {
        releaseDate = DateTime.parse(json['releaseDate']);
      } else if (json['releaseDate'] is DateTime) {
        releaseDate = json['releaseDate'];
      } else {
        releaseDate = DateTime.now();
      }
    } catch (e) {
      debugPrint('Error parsing release date: $e');
      releaseDate = DateTime.now();
    }

    return Album(
      id: albumId ?? 0,
      name: json['name'] ?? json['collectionName'] ?? 'Unknown Album',
      artist: json['artist'] ?? json['artistName'] ?? 'Unknown Artist',
      artworkUrl: json['artworkUrl'] ?? json['artworkUrl100'] ?? '',
      url: json['url'] ?? '',
      platform: json['platform'] ?? 'unknown',
      releaseDate: releaseDate,
      metadata: json['metadata'] ?? {},
      tracks: parsedTracks,
    );
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

    // Parse release date with better error handling
    DateTime releaseDate;
    try {
      if (legacy['releaseDate'] != null) {
        if (legacy['releaseDate'] is String) {
          releaseDate = DateTime.parse(legacy['releaseDate']);
        } else {
          releaseDate = DateTime.now();
        }
      } else {
        releaseDate = DateTime.now();
      }
    } catch (e) {
      debugPrint('Error parsing legacy release date: $e');
      releaseDate = DateTime.now();
    }

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
