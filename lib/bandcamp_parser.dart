import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
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

  static List<Map<String, dynamic>> extractAlbums(Document document, int collectionId) {
    var albumElements = document.querySelectorAll('.album-element-selector'); // Selector de ejemplo, cámbialo según tu HTML
    List<Map<String, dynamic>> albums = [];
    
    for (var albumElement in albumElements) {
      String title = albumElement.querySelector('.album-title')?.text.trim() ?? '';
      String artist = albumElement.querySelector('.album-artist')?.text.trim() ?? '';
      String albumArtUrl = albumElement.querySelector('.album-art')?.attributes['src'] ?? '';

      List<Map<String, dynamic>> tracks = [];
      int trackNumberCounter = 1; // Reinicia el contador para cada álbum nuevo

      var trackElements = albumElement.querySelectorAll('.track_row_view');

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

      // Generamos un ID único para cada colección de álbumes
      int uniqueCollectionId = UniqueIdGenerator.generateUniqueCollectionId();

      albums.add({
        'collectionId': uniqueCollectionId,
        'title': title,
        'artist': artist,
        'albumArtUrl': albumArtUrl,
        'tracks': tracks, // Agrega las pistas al álbum
      });
    }
    return albums;
  }
}
