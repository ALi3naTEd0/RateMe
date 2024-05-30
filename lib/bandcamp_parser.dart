import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';

class BandcampParser {
  static String extractAlbumCoverUrl(Document document) {
    var imageElement = document.querySelector('.popupImage');

    return imageElement != null ? imageElement.attributes['href'] ?? '' : '';
  }

  static List<Map<String, dynamic>> extractTracks(Document document) {
    var trackElements = document.querySelectorAll('.track-number-col');
    var titleElements = document.querySelectorAll('.title-col');
    var durationElements = document.querySelectorAll('.time.secondaryText');

    List<Map<String, dynamic>> tracks = [];

    for (int i = 0; i < trackElements.length; i++) {
      String trackNumberText = trackElements[i].text.trim();
      String title = titleElements[i].text.trim();
      String durationText = durationElements[i].text.trim();
      int durationMillis = _parseDuration(durationText);

      tracks.add({
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
}
