import 'package:intl/intl.dart';
import 'logging.dart';

/// Unified album model that works across different music platforms
class Album {
  final int id;
  final String name;
  final String artist;
  final String artworkUrl;
  final DateTime releaseDate;
  final String platform; // "itunes", "bandcamp", "spotify", "deezer"
  final String? url;
  final List<Track> tracks;
  final Map<String, dynamic>? metadata; // Additional platform-specific data

  Album({
    required this.id,
    required this.name, 
    required this.artist,
    required this.artworkUrl,
    required this.releaseDate,
    required this.platform,
    this.url,
    this.tracks = const [],
    this.metadata,
  });

  // Legacy property getters
  String get collectionName => name;
  String get artistName => artist;
  String get artworkUrl100 => artworkUrl;

  /// Convert Album to a Map for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'artworkUrl': artworkUrl,
      'releaseDate': releaseDate.toIso8601String(),
      'platform': platform,
      'url': url,
      'tracks': tracks.map((track) => track.toJson()).toList(),
      'metadata': metadata,
      'modelVersion': 1, // Version of the data model
    };
  }

  /// Convert to legacy format for backward compatibility
  Map<String, dynamic> toLegacyJson() {
    return {
      'collectionId': id,
      'collectionName': name,
      'artistName': artist,
      'artworkUrl100': artworkUrl,
      'releaseDate': releaseDate.toIso8601String(),
      'url': url,
      // Include all metadata for maximum compatibility
      ...?metadata,
    };
  }

  /// Create an Album from JSON (new format)
  factory Album.fromJson(Map<String, dynamic> json) {
    try {
      // Check if this is new format vs legacy format
      if (json.containsKey('modelVersion')) {
        // New format
        return Album(
          id: json['id'],
          name: json['name'],
          artist: json['artist'],
          artworkUrl: json['artworkUrl'],
          releaseDate: DateTime.parse(json['releaseDate']),
          platform: json['platform'],
          url: json['url'],
          tracks: (json['tracks'] as List?)
              ?.map((trackJson) => Track.fromJson(trackJson))
              .toList() ?? [],
          metadata: json['metadata'],
        );
      } else {
        // Legacy format - convert automatically
        return Album.fromLegacy(json);
      }
    } catch (e, stack) {
      Logging.severe('Error creating Album from JSON', e, stack);
      // Provide a reasonable fallback to prevent crashes
      return Album(
        id: json['id'] ?? json['collectionId'] ?? DateTime.now().millisecondsSinceEpoch,
        name: json['name'] ?? json['collectionName'] ?? 'Unknown Album',
        artist: json['artist'] ?? json['artistName'] ?? 'Unknown Artist',
        artworkUrl: json['artworkUrl'] ?? json['artworkUrl100'] ?? '',
        releaseDate: DateTime.now(),
        platform: 'unknown',
        metadata: json, // Store original for debugging
      );
    }
  }

  /// Create an Album from legacy data structure
  factory Album.fromLegacy(Map<String, dynamic> legacy) {
    try {
      // Detect platform
      final bool isBandcamp = legacy['url']?.toString().contains('bandcamp.com') ?? false;
      final platform = isBandcamp ? 'bandcamp' : 'itunes';
      
      // Parse release date depending on format
      DateTime releaseDate;
      try {
        if (legacy['releaseDate'] != null) {
          releaseDate = DateTime.parse(legacy['releaseDate']);
        } else {
          releaseDate = DateTime.now();
        }
      } catch (e) {
        // Try other formats
        try {
          releaseDate = DateFormat("d MMMM yyyy").parse(legacy['releaseDate'] ?? '');
        } catch (e) {
          releaseDate = DateTime.now();
        }
      }

      // Convert legacy tracks to unified Track model
      final List<Track> tracks = [];
      if (legacy['tracks'] != null) {
        for (var trackData in legacy['tracks']) {
          try {
            tracks.add(Track.fromLegacy(trackData, isBandcamp));
          } catch (e) {
            Logging.severe('Error parsing track', e);
            // Continue with other tracks
          }
        }
      }

      // Handle the collection ID according to platform
      int id;
      if (legacy['id'] != null) {
        id = legacy['id'] is int ? legacy['id'] : int.parse(legacy['id'].toString());
      } else if (legacy['collectionId'] != null) {
        id = legacy['collectionId'] is int ? legacy['collectionId'] : int.parse(legacy['collectionId'].toString());
      } else {
        id = DateTime.now().millisecondsSinceEpoch;
      }

      return Album(
        id: id,
        name: legacy['collectionName'] ?? legacy['title'] ?? 'Unknown Album',
        artist: legacy['artistName'] ?? legacy['artist'] ?? 'Unknown Artist',
        artworkUrl: legacy['artworkUrl100'] ?? legacy['artwork'] ?? '',
        releaseDate: releaseDate,
        platform: platform,
        url: legacy['url'],
        tracks: tracks,
        metadata: legacy,  // Store original data for compatibility
      );
    } catch (e, stack) {
      Logging.severe('Error converting legacy album', e, stack);
      // Provide a fallback to prevent crashes
      return Album(
        id: DateTime.now().millisecondsSinceEpoch, 
        name: legacy['collectionName'] ?? legacy['title'] ?? 'Unknown Album',
        artist: legacy['artistName'] ?? legacy['artist'] ?? 'Unknown Artist',
        artworkUrl: legacy['artworkUrl100'] ?? '',
        releaseDate: DateTime.now(),
        platform: 'unknown',
        metadata: legacy, // Store original for debugging
      );
    }
  }
}

/// Unified track model that works across different music platforms
class Track {
  final int id;
  final String name;
  final int position;
  final int durationMs;
  final Map<String, dynamic>? metadata; // Additional platform-specific data

  Track({
    required this.id,
    required this.name,
    required this.position,
    required this.durationMs,
    this.metadata,
  });

  /// Convert Track to a Map for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'position': position,
      'durationMs': durationMs,
      'metadata': metadata,
    };
  }

  /// Convert to legacy format for backward compatibility
  Map<String, dynamic> toLegacyJson(bool isBandcamp) {
    final Map<String, dynamic> legacy = {
      'trackId': id,
      'trackNumber': position,
      'position': position,
    };
    
    // Add platform-specific fields
    if (isBandcamp) {
      legacy['title'] = name;
      legacy['duration'] = durationMs;
    } else {
      legacy['trackName'] = name;
      legacy['trackTimeMillis'] = durationMs;
    }
    
    // Add any additional metadata
    if (metadata != null) {
      legacy.addAll(metadata!);
    }
    
    return legacy;
  }

  /// Create a Track from JSON (new format)
  factory Track.fromJson(Map<String, dynamic> json) {
    try {
      return Track(
        id: json['id'],
        name: json['name'],
        position: json['position'],
        durationMs: json['durationMs'],
        metadata: json['metadata'],
      );
    } catch (e) {
      Logging.severe('Error creating Track from JSON', e);
      // Provide fallback
      return Track(
        id: json['id'] ?? DateTime.now().millisecondsSinceEpoch,
        name: json['name'] ?? 'Unknown Track',
        position: json['position'] ?? 0,
        durationMs: json['durationMs'] ?? 0,
        metadata: json,
      );
    }
  }

  /// Create a Track from legacy data structure
  factory Track.fromLegacy(Map<String, dynamic> legacy, bool isBandcamp) {
    try {
      int trackId;
      if (legacy['trackId'] != null) {
        trackId = legacy['trackId'] is int ? legacy['trackId'] : int.parse(legacy['trackId'].toString());
      } else if (legacy['id'] != null) {
        trackId = legacy['id'] is int ? legacy['id'] : int.parse(legacy['id'].toString());
      } else {
        trackId = DateTime.now().millisecondsSinceEpoch;
      }
      
      int position = 0;
      if (legacy['trackNumber'] != null) {
        position = legacy['trackNumber'] is int ? legacy['trackNumber'] : int.parse(legacy['trackNumber'].toString());
      } else if (legacy['position'] != null) {
        position = legacy['position'] is int ? legacy['position'] : int.parse(legacy['position'].toString());
      }
      
      String name = isBandcamp 
          ? legacy['title'] ?? 'Unknown Track'
          : legacy['trackName'] ?? 'Unknown Track';
      
      int durationMs = 0;
      if (isBandcamp && legacy['duration'] != null) {
        durationMs = legacy['duration'] is int ? legacy['duration'] : int.parse(legacy['duration'].toString());
      } else if (!isBandcamp && legacy['trackTimeMillis'] != null) {
        durationMs = legacy['trackTimeMillis'] is int ? legacy['trackTimeMillis'] : int.parse(legacy['trackTimeMillis'].toString());
      }

      return Track(
        id: trackId,
        name: name,
        position: position,
        durationMs: durationMs,
        metadata: legacy,  // Store original data for compatibility
      );
    } catch (e) {
      Logging.severe('Error converting legacy track', e);
      // Provide a fallback
      return Track(
        id: DateTime.now().millisecondsSinceEpoch,
        name: isBandcamp ? legacy['title'] ?? 'Unknown Track' : legacy['trackName'] ?? 'Unknown Track',
        position: 0,
        durationMs: 0,
        metadata: legacy,
      );
    }
  }
}
