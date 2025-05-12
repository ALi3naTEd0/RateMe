import '../../core/models/album_model.dart';
import '../../core/services/logging.dart';

class ModelMappingService {
  /// Check if the data is in legacy format
  static bool isLegacyFormat(Map<String, dynamic> data) {
    return !data.containsKey('modelVersion');
  }

  /// Map iTunes search result to unified Album model
  static Album mapItunesSearchResult(Map<String, dynamic> legacyData) {
    try {
      return Album(
        id: legacyData['collectionId'] ?? 0,
        name: legacyData['collectionName'] ?? 'Unknown Album',
        artist: legacyData['artistName'] ?? 'Unknown Artist',
        artworkUrl: legacyData['artworkUrl100'] ?? '',
        url: legacyData['collectionViewUrl'] ?? '',
        platform: 'itunes',
        releaseDate: legacyData['releaseDate'] != null
            ? DateTime.parse(legacyData['releaseDate'])
            : DateTime.now(),
        metadata: legacyData,
      );
    } catch (e) {
      Logging.severe('Error mapping iTunes album to unified model', e);
      throw Exception('Failed to map iTunes album: $e');
    }
  }

  /// Map Bandcamp album to unified Album model
  static Album mapBandcampAlbum(Map<String, dynamic> legacyData) {
    try {
      Logging.severe(
          'Mapping Bandcamp album to unified model: ${legacyData['collectionName']}');

      // Extract tracks if available
      List<Track> tracks = [];
      if (legacyData.containsKey('tracks') && legacyData['tracks'] is List) {
        List<dynamic> trackList = legacyData['tracks'];
        Logging.severe('Found ${trackList.length} tracks to map');

        for (var trackData in trackList) {
          try {
            tracks.add(Track(
              id: trackData['trackId'] ?? 0,
              name: trackData['trackName'] ?? 'Unknown Track',
              position: trackData['trackNumber'] ?? 0,
              durationMs: trackData['trackTimeMillis'] ?? 0,
              metadata: trackData,
            ));
          } catch (e) {
            Logging.severe('Error mapping track: $e');
            // Continue with next track
          }
        }
      }

      // Parse release date
      DateTime? releaseDate;
      try {
        if (legacyData['releaseDate'] != null) {
          if (legacyData['releaseDate'] is String) {
            String dateStr = legacyData['releaseDate'];
            // Try different date formats
            try {
              releaseDate = DateTime.parse(dateStr);
            } catch (_) {
              try {
                // Try Bandcamp's format "26 Feb 2025 00:00:00 GMT"
                releaseDate = DateTime.parse(dateStr.replaceAll(' GMT', 'Z'));
              } catch (_) {
                try {
                  releaseDate = DateTime.tryParse(dateStr);
                } catch (_) {
                  releaseDate = DateTime.now();
                }
              }
            }
          }
        }
      } catch (e) {
        Logging.severe('Error parsing release date: $e');
        releaseDate = DateTime.now();
      }

      return Album(
        id: legacyData['id'] ??
            legacyData['collectionId'] ??
            (legacyData['url']?.hashCode ??
                DateTime.now().millisecondsSinceEpoch),
        name: legacyData['name'] ??
            legacyData['collectionName'] ??
            'Unknown Album',
        artist: legacyData['artist'] ??
            legacyData['artistName'] ??
            'Unknown Artist',
        artworkUrl:
            legacyData['artworkUrl'] ?? legacyData['artworkUrl100'] ?? '',
        url: legacyData['url'] ?? '',
        platform: 'bandcamp',
        releaseDate: releaseDate ?? DateTime.now(),
        metadata: legacyData,
        tracks: tracks,
      );
    } catch (e) {
      Logging.severe('Error mapping Bandcamp album to unified model', e);
      throw Exception('Failed to map Bandcamp album: $e');
    }
  }

  /// Map iTunes album to unified Album model
  static Album mapItunesAlbum(Map<String, dynamic> legacyData) {
    return mapItunesSearchResult(legacyData);
  }
}
