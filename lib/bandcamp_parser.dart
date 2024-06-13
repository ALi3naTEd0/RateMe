// bandcamp_parser.dart
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'package:intl/intl.dart';
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
    int trackNumberCounter = 1;

    for (var trackElement in trackElements) {
      String title = trackElement.querySelector('.title-col span')?.text.trim() ?? '';
      String durationText = trackElement.querySelector('.time.secondaryText')?.text.trim() ?? '0:00';
      int durationMillis = _parseDuration(durationText);

      int trackId = UniqueIdGenerator.generateUniqueTrackId();

      tracks.add({
        'trackId': trackId,
        'collectionId': collectionId,
        'trackNumber': trackNumberCounter++,
        'title': title,
        'duration': durationMillis,
      });
    }

    return tracks;
  }

  static List<Map<String, dynamic>> extractAlbums(Document document, int collectionId) {
    var albumElements = document.querySelectorAll('.album-element-selector');
    List<Map<String, dynamic>> albums = [];

    for (var albumElement in albumElements) {
      String title = albumElement.querySelector('.album-title')?.text.trim() ?? '';
      String artist = albumElement.querySelector('.album-artist')?.text.trim() ?? '';
      String albumArtUrl = albumElement.querySelector('.album-art')?.attributes['src'] ?? '';

      List<Map<String, dynamic>> tracks = [];
      int trackNumberCounter = 1;

      var trackElements = albumElement.querySelectorAll('.track_row_view');

      for (var trackElement in trackElements) {
        String title = trackElement.querySelector('.title-col span')?.text.trim() ?? '';
        String durationText = trackElement.querySelector('.time.secondaryText')?.text.trim() ?? '0:00';
        int durationMillis = _parseDuration(durationText);

        int trackId = UniqueIdGenerator.generateUniqueTrackId();

        tracks.add({
          'trackId': trackId,
          'collectionId': collectionId,
          'trackNumber': trackNumberCounter++,
          'title': title,
          'duration': durationMillis,
        });
      }

      int uniqueCollectionId = UniqueIdGenerator.generateUniqueCollectionId();

      albums.add({
        'collectionId': uniqueCollectionId,
        'title': title,
        'artist': artist,
        'albumArtUrl': albumArtUrl,
        'tracks': tracks,
      });
    }

    return albums;
  }

  static DateTime? extractReleaseDate(Document document) {
    var releaseElement = document.querySelector('.tralbumData.tralbum-credits');
    if (releaseElement != null) {
      RegExp dateRegExp = RegExp(r'released (\w+ \d{1,2}, \d{4})');
      var match = dateRegExp.firstMatch(releaseElement.text);
      if (match != null) {
        String dateStr = match.group(1) ?? '';
        return DateFormat('MMMM d, yyyy').parse(dateStr);
      }
    }
    return null;
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
}
