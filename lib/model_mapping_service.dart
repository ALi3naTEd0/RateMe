import 'album_model.dart';
import 'logging.dart';

class ModelMappingService {
  static bool isLegacyFormat(Map<String, dynamic> data) {
    return data.containsKey('collectionId') && 
           !data.containsKey('modelVersion');
  }

  static Album? mapItunesSearchResult(Map<String, dynamic> itunesData) {
    try {
      return Album(
        id: itunesData['collectionId'],
        name: itunesData['collectionName'],
        artist: itunesData['artistName'],
        artworkUrl: itunesData['artworkUrl100'],
        releaseDate: DateTime.parse(itunesData['releaseDate']),
        platform: 'itunes',
        metadata: itunesData,
      );
    } catch (e) {
      Logging.severe('Error mapping iTunes search result: $e');
      return null;
    }
  }
}
