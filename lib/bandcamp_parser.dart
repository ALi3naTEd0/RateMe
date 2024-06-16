import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:html/dom.dart';

class BandcampParser {
  static String extractAlbumCoverUrl(Document document) {
    var imageElement = document.querySelector('.popupImage');
    return imageElement != null ? imageElement.attributes['href'] ?? '' : '';
  }

  static List<Map<String, dynamic>> extractTracks(Document document) {
    Element? scriptElement =
        document.querySelector('script[type="application/ld+json"]');

    Map<String, dynamic> contentJson =
        jsonDecode(scriptElement?.innerHtml ?? '');

    final int collectionId = _extractCollectionId(contentJson);

    return _extractTracksFromJson(contentJson, collectionId);
  }

  static List<Map<String, dynamic>> _extractTracksFromJson(
      Map<String, dynamic> contentJson, int collectionId) {
    List<dynamic> trackElements = contentJson['track']['itemListElement'] ?? [];
    List<Map<String, dynamic>> tracks = [];

    for (var trackElement in trackElements) {
      int position = trackElement['position'] ?? 0;
      var item = trackElement['item'];
      String title = item['name'] ?? '';
      String durationText = item['duration'] ?? 'P00H00M00S';
      int durationMillis = _parseDuration(durationText);

      int trackId = item['additionalProperty']?.firstWhere(
        (prop) => prop['name'] == 'track_id',
      )['value'];

      tracks.add({
        'trackId': trackId,
        'collectionId': collectionId,
        'trackNumber': position,
        'title': title,
        'duration': durationMillis,
      });
    }

    return tracks;
  }

  static int _extractCollectionId(Map<String, dynamic> contentJson) {
    if (contentJson.containsKey('albumRelease')) {
      List<dynamic> albumReleaseItems = contentJson['albumRelease'];
      for (var releaseItem in albumReleaseItems) {
        if (releaseItem['@id'] == contentJson['@id'] &&
            releaseItem.containsKey('additionalProperty')) {
          List<dynamic> additionalProperties =
              releaseItem['additionalProperty'];
          for (var property in additionalProperties) {
            if (property['name'] == 'item_id') {
              return property['value'];
            }
          }
        }
      }
    }
    return 0;
  }

  static List<Map<String, dynamic>> extractAlbums(Document document) {
    Element? scriptElement =
        document.querySelector('script[type="application/ld+json"]');

    Map<String, dynamic> contentJson =
        jsonDecode(scriptElement?.innerHtml ?? '');

    final int collectionId = _extractCollectionId(contentJson);

    List<Map<String, dynamic>> albums = [];

    String title = contentJson['name'] ?? '';
    String artist = contentJson['byArtist']['name'] ?? '';
    String albumArtUrl = contentJson['image'] ?? '';

    List<Map<String, dynamic>> tracks =
        _extractTracksFromJson(contentJson, collectionId);

    DateTime? releaseDate = extractReleaseDate(document);

    albums.add({
      'collectionId': collectionId,
      'title': title,
      'artist': artist,
      'albumArtUrl': albumArtUrl,
      'tracks': tracks,
      'releaseDate': releaseDate,
    });

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
    final regex = RegExp(
        r'P(?:(?<hours>\d+)H)?(?:(?<minutes>\d+)M)?(?:(?<seconds>\d+)S)?');
    final match = regex.firstMatch(durationText);

    if (match != null) {
      final hours = int.tryParse(match.namedGroup('hours') ?? '0') ?? 0;
      final minutes = int.tryParse(match.namedGroup('minutes') ?? '0') ?? 0;
      final seconds = int.tryParse(match.namedGroup('seconds') ?? '0') ?? 0;
      return (hours * 3600 + minutes * 60 + seconds) * 1000;
    } else {
      return 0;
    }
  }
}
