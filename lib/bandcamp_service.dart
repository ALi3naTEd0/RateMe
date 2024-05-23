import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class BandcampService {
  static Future<Map<String, dynamic>> fetchBandcampAlbumInfo(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      var document = html_parser.parse(response.body);

      String title = document.querySelector('meta[property="og:title"]')?.attributes['content'] ?? 'Unknown Title';
      String artist = document.querySelector('meta[property="og:site_name"]')?.attributes['content'] ?? 'Unknown Artist';
      String artworkUrl = document.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';

      return {
        'collectionName': title,
        'artistName': artist,
        'artworkUrl100': artworkUrl,
        'url': url,
      };
    } else {
      throw Exception('Failed to load Bandcamp album');
    }
  }
}
