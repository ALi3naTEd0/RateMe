import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'id_generator.dart';

class BandcampParser {
  static String extractAlbumCoverUrl(Document document) {
    var imageElement = document.querySelector('.popupImage');
    return imageElement != null ? imageElement.attributes['href'] ?? '' : '';
  }

  static List<Map<String, dynamic>> extractTracks(Document document, int collectionId) {
    var trackElements = document.querySelectorAll('.track_row_view');

    List<Map<String, dynamic>> tracks = [];
    int trackNumberCounter = 1; // Contador para el número de pista
    
    for (var trackElement in trackElements) {
      String trackNumberText = trackElement.querySelector('.track-number-col')?.text.trim() ?? '';
      String title = trackElement.querySelector('.title-col span')?.text.trim() ?? '';
      String durationText = trackElement.querySelector('.time.secondaryText')?.text.trim() ?? '0:00';
      int durationMillis = _parseDuration(durationText);

      // Generamos un ID único para cada pista
      int trackId = UniqueIdGenerator.generateUniqueTrackId();

      tracks.add({
        'trackId': trackId,
        'collectionId': collectionId,
        'trackNumber': trackNumberCounter++, // Utilizamos el contador para el número de pista
        'title': title,
        'duration': durationMillis,
      });
    }

    return tracks;
  }

  static int _parseDuration(String durationText) {
    var parts = durationText.split(':');
    if (parts.length == 2) {
      int minutes = int.tryParse(parts[0]) ?? 0;
      int seconds = int.tryParse(parts[1]) ?? 0;
      return (minutes * 60 + seconds) * 1000;
    } else {
      return 0;
    }
  }

  static Map<String, dynamic> extractAlbumDetails(Document document) {
    String title = document.querySelector('.trackTitle')?.text.trim() ?? '';
    String artist = document.querySelector('.artistTitle')?.text.trim() ?? '';
    String releaseDate = document.querySelector('.tralbumData.tralbum-credits')?.text.trim() ?? '';
    String albumArtUrl = extractAlbumCoverUrl(document);

    return {
      'title': title,
      'artist': artist,
      'releaseDate': releaseDate,
      'albumArtUrl': albumArtUrl,
    };
  }
}
