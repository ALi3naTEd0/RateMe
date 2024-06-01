import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BandcampParser {
  static int _lastTrackId = 0; // Variable estática para mantener el último trackId utilizado

  static Future<void> _loadLastTrackId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _lastTrackId = prefs.getInt('last_track_id') ?? 0;
  }

  static Future<void> _saveLastTrackId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_track_id', _lastTrackId);
  }

  static String extractAlbumCoverUrl(Document document) {
    var imageElement = document.querySelector('.popupImage');
    return imageElement != null ? imageElement.attributes['href'] ?? '' : '';
  }

  static List<Map<String, dynamic>> extractTracks(Document document) {
    var trackElements = document.querySelectorAll('.track_row_view');

    List<Map<String, dynamic>> tracks = [];
    int trackNumberCounter = 1; // Contador para el número de pista
    
    for (var trackElement in trackElements) {
      String trackNumberText = trackElement.querySelector('.track-number-col')?.text.trim() ?? '';
      String title = trackElement.querySelector('.title-col span')?.text.trim() ?? '';
      String durationText = trackElement.querySelector('.time.secondaryText')?.text.trim() ?? '0:00';
      int durationMillis = _parseDuration(durationText);

      // Utilizamos el último trackId utilizado y lo incrementamos
      _lastTrackId++;

      tracks.add({
        'trackId': _lastTrackId,
        'trackNumber': trackNumberCounter++, // Utilizamos el contador para el número de pista
        'title': title,
        'duration': durationMillis,
      });
    }

    _saveLastTrackId(); // Guardar el último trackId utilizado

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
    
    for (var albumElement in albumElements) {
      String title = albumElement.querySelector('.album-title')?.text.trim() ?? '';
      String artist = albumElement.querySelector('.album-artist')?.text.trim() ?? '';
      String albumArtUrl = albumElement.querySelector('.album-art')?.attributes['src'] ?? '';

      albums.add({
        'collectionId': albums.length + 1, // Utilizamos el índice de la lista de álbumes como ID
        'title': title,
        'artist': artist,
        'albumArtUrl': albumArtUrl,
      });
    }

    return albums;
  }
}
