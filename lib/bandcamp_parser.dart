import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';

class BandcampParser {
  static String extractAlbumCoverUrl(Document document) {
    var imageElement = document.querySelector('.popupImage');
    return imageElement != null ? imageElement.attributes['href'] ?? '' : '';
  }

  static List<Map<String, dynamic>> extractTracks(Document document) {
    var trackElements = document.querySelectorAll('.track_row_view');

    List<Map<String, dynamic>> tracks = [];

    for (int i = 0; i < trackElements.length; i++) {
      var trackElement = trackElements[i];
      String trackNumberText = trackElement.querySelector('.track-number-col')?.text.trim() ?? '';
      String title = trackElement.querySelector('.title-col span')?.text.trim() ?? '';
      String durationText = trackElement.querySelector('.time-col')?.text.trim() ?? '0:00';
      int durationMillis = _parseDuration(durationText);

      tracks.add({
        'trackId': i + 1, // Usa un identificador simple incremental
        'trackNumber': int.tryParse(trackNumberText) ?? i + 1,
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

  static List<Map<String, dynamic>> extractAlbums(Document document) {
    var albumElements = document.querySelectorAll('.album-element-selector'); // Selector de ejemplo, cámbialo según tu HTML

    List<Map<String, dynamic>> albums = [];

    for (int i = 0; i < albumElements.length; i++) {
      var albumElement = albumElements[i];
      String title = albumElement.querySelector('.album-title')?.text.trim() ?? '';
      String artist = albumElement.querySelector('.album-artist')?.text.trim() ?? '';
      String albumArtUrl = albumElement.querySelector('.album-art')?.attributes['src'] ?? '';

      albums.add({
        'collectionId': i + 1, // Genera un ID único para el álbum
        'title': title,
        'artist': artist,
        'albumArtUrl': albumArtUrl,
      });
    }

    return albums;
  }
}
