import 'dart:convert';
import 'package:http/http.dart' as http;
import '../logging.dart';
import 'platform_service_base.dart';

class BandcampService extends PlatformServiceBase {
  @override
  String get platformId => 'bandcamp';

  @override
  String get displayName => 'Bandcamp';

  @override
  Future<String?> findAlbumUrl(String artist, String albumName) async {
    // Not implemented: Bandcamp does not have a public search API.
    throw UnimplementedError('BandcampService.findAlbumUrl is not implemented');
  }

  @override
  Future<bool> verifyAlbumExists(String artist, String albumName) async {
    // Not implemented: Bandcamp does not have a public search API.
    throw UnimplementedError(
        'BandcampService.verifyAlbumExists is not implemented');
  }

  @override
  Future<Map<String, dynamic>?> fetchAlbumDetails(String url) async {
    try {
      Logging.severe('BandcampService: Fetching album details for $url');
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        Logging.severe('BandcampService: Failed to fetch page');
        return null;
      }
      final html = response.body;

      // STRATEGY 1: Try to find JSON-LD first (it usually has the best album data)
      final jsonLdData = _extractTrackDataFromJsonLd(html);
      if (jsonLdData != null) {
        Logging.severe('BandcampService: Using JSON-LD extraction');
        return jsonLdData;
      }

      // STRATEGY 2: Look for TralbumData with more flexible patterns
      final tralbumData = _extractTrackDataFromTralbum(html);
      if (tralbumData != null) {
        Logging.severe('BandcampService: Using TralbumData extraction');
        return tralbumData;
      }

      // STRATEGY 3: Look for track-info elements in HTML
      final trackElementsData = _extractTrackDataFromElements(html, url);
      if (trackElementsData != null) {
        Logging.severe('BandcampService: Using HTML track elements extraction');
        return trackElementsData;
      }

      // STRATEGY 4: Try to extract from meta tags and page structure
      final metaData = _extractFromMetaAndPage(html, url);
      if (metaData != null) {
        Logging.severe('BandcampService: Using meta tags extraction');
        return metaData;
      }

      // STRATEGY 5: Create placeholder tracks from page content
      final placeholderData = _createPlaceholderTracks(html, url);
      if (placeholderData != null) {
        Logging.severe('BandcampService: Using placeholder tracks');
        return placeholderData;
      }

      Logging.severe('BandcampService: All extraction methods failed');
      return null;
    } catch (e, stack) {
      Logging.severe('BandcampService.fetchAlbumDetails error', e, stack);
      return null;
    }
  }

  // Extract album data from TralbumData object
  Map<String, dynamic>? _extractTrackDataFromTralbum(String html) {
    try {
      // Try multiple patterns for TralbumData
      final patterns = [
        r'window\.TralbumData\s*=\s*({.*?})\s*;\s*',
        r'TralbumData\s*=\s*({.*?})\s*;',
        r'data-tralbum="(.*?)"',
      ];

      String? tralbumJson;
      for (final pattern in patterns) {
        final match = RegExp(pattern, dotAll: true).firstMatch(html);
        if (match != null) {
          tralbumJson = match.group(1);
          break;
        }
      }

      if (tralbumJson == null) return null;

      // For HTML-encoded JSON in data attributes
      if (tralbumJson.contains('&quot;')) {
        tralbumJson = tralbumJson
            .replaceAll('&quot;', '"')
            .replaceAll('&amp;', '&')
            .replaceAll('&#39;', "'");
      }

      // Parse the JSON
      String fixedJson = tralbumJson
          .replaceAll(RegExp(r"(\w+):"), r'"\1":') // keys to quoted
          .replaceAll(RegExp(r"'"), '"')
          .replaceAll(RegExp(r',\s*}'), '}')
          .replaceAll(RegExp(r',\s*]'), ']');

      dynamic tralbum;
      try {
        tralbum = json.decode(fixedJson);
      } catch (e) {
        try {
          Logging.severe('First JSON parse failed, trying alternate fix');
          String altJson = tralbumJson;
          altJson = altJson
              .replaceAll(RegExp(r":\s*'"), ':"')
              .replaceAll(RegExp(r"',"), '",')
              .replaceAll(RegExp(r"'\s*}"), '"}')
              .replaceAll(RegExp(r"'\s*]"), '"]');
          tralbum = json.decode(altJson);
        } catch (e2) {
          Logging.severe('Failed to parse TralbumData JSON: $e2');
          return null;
        }
      }

      // Extract album info
      var albumTitle = '';
      var artistName = '';
      var artworkUrl = '';
      final tracks = <Map<String, dynamic>>[];

      // Extract album title
      albumTitle = tralbum['current']?['title'] ??
          tralbum['title'] ??
          tralbum['album_title'] ??
          '';

      // Extract artist name
      artistName = tralbum['artist'] ??
          tralbum['artist_name'] ??
          tralbum['current']?['artist'] ??
          '';

      // Extract artwork
      artworkUrl = tralbum['artFullsizeUrl'] ??
          tralbum['art_id'] ??
          tralbum['artwork_url'] ??
          tralbum['current']?['art_id'] ??
          '';

      // Extract tracks
      List<dynamic>? trackInfoList; // Explicit type annotation
      if (tralbum['trackinfo'] is List) {
        trackInfoList = tralbum['trackinfo'];
      } else if (tralbum['tracks'] is List) {
        trackInfoList = tralbum['tracks'];
      }

      if (trackInfoList != null) {
        int pos = 1;
        for (final t in trackInfoList) {
          if (t == null) continue;

          // FIX: Safely convert id to string, handling both int and String types
          final trackIdRaw = t['track_id'] ?? t['id'] ?? pos;
          final trackId = trackIdRaw.toString();

          final trackTitle = t['title'] ?? t['name'] ?? 'Track $pos';

          // ENHANCED DURATION PARSING: Handle all possible Bandcamp duration formats
          int trackDuration = 0;
          final durationRaw = t['duration'];
          if (durationRaw != null) {
            if (durationRaw is num) {
              // Bandcamp sometimes provides duration in seconds as a number
              trackDuration = (durationRaw * 1000).round();
            } else if (durationRaw is String) {
              if (durationRaw.startsWith('P') || durationRaw.startsWith('PT')) {
                // ISO 8601 duration format (PT1H2M3S or P00H05M34S)
                trackDuration = _parseIso8601DurationToMillis(durationRaw);
              } else if (durationRaw.contains(':')) {
                // MM:SS format
                trackDuration = _parseTimeStringToMillis(durationRaw);
              } else {
                // Try to parse as a number if possible
                final durationNum = double.tryParse(durationRaw);
                if (durationNum != null) {
                  trackDuration = (durationNum * 1000).round();
                }
              }
            }
          }

          tracks.add({
            'trackId': trackId,
            'trackName': trackTitle,
            'trackNumber': pos,
            'trackTimeMillis': trackDuration,
          });
          pos++;
        }
      }

      if (tracks.isEmpty) return null;

      return {
        'id': tralbum['album_id']?.toString() ?? '',
        'collectionId': tralbum['album_id']?.toString() ?? '',
        'name': albumTitle,
        'collectionName': albumTitle,
        'artist': artistName,
        'artistName': artistName,
        'artworkUrl': artworkUrl,
        'artworkUrl100': artworkUrl,
        'releaseDate': '',
        'url': tralbum['url'] ?? '',
        'platform': 'bandcamp',
        'tracks': tracks,
      };
    } catch (e) {
      Logging.severe('Error extracting from TralbumData: $e');
      return null;
    }
  }

  // Add new method to parse time strings like "4:30" or "1:23:45"
  int _parseTimeStringToMillis(String timeString) {
    try {
      final parts = timeString.split(':');
      if (parts.length == 2) {
        // MM:SS format
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        return (minutes * 60 + seconds) * 1000;
      } else if (parts.length == 3) {
        // HH:MM:SS format
        final hours = int.tryParse(parts[0]) ?? 0;
        final minutes = int.tryParse(parts[1]) ?? 0;
        final seconds = int.tryParse(parts[2]) ?? 0;
        return (hours * 3600 + minutes * 60 + seconds) * 1000;
      }
      return 0;
    } catch (e) {
      Logging.severe('Error parsing time string: $e');
      return 0;
    }
  }

  // Extract from JSON-LD (prefer this for album-level data)
  Map<String, dynamic>? _extractTrackDataFromJsonLd(String html) {
    try {
      final jsonLdMatch = RegExp(
        r'<script type="application/ld\+json">\s*(\{.*?\})\s*</script>',
        dotAll: true,
      ).firstMatch(html);

      if (jsonLdMatch != null) {
        final jsonLdRaw = jsonLdMatch.group(1);
        if (jsonLdRaw != null) {
          try {
            final jsonLd = json.decode(jsonLdRaw);

            // Only proceed if this is a MusicAlbum
            if (jsonLd['@type'] == 'MusicAlbum') {
              // Album-level info
              final albumTitle = jsonLd['name'] ?? '';
              final artistName = (jsonLd['byArtist'] is Map)
                  ? (jsonLd['byArtist']['name'] ?? '')
                  : '';

              Logging.severe(
                  'BANDCAMP: Extracted title: "$albumTitle" and artist: "$artistName"');

              // Artwork: try image from albumRelease, fallback to top-level
              String artworkUrl = '';
              if (jsonLd['albumRelease'] is List &&
                  jsonLd['albumRelease'].isNotEmpty &&
                  jsonLd['albumRelease'][0]['image'] is List &&
                  jsonLd['albumRelease'][0]['image'].isNotEmpty) {
                artworkUrl = jsonLd['albumRelease'][0]['image'][0];
              } else if (jsonLd['image'] is String) {
                artworkUrl = jsonLd['image'];
              }

              // --- Track extraction ---
              List<Map<String, dynamic>> tracks = [];
              // Bandcamp now uses: "track": { "@type": "ItemList", "itemListElement": [ ... ] }
              if (jsonLd['track'] is Map &&
                  jsonLd['track']['@type'] == 'ItemList' &&
                  jsonLd['track']['itemListElement'] is List) {
                final itemList = jsonLd['track']['itemListElement'];

                // Log only the number of tracks, not every single one
                Logging.severe(
                    'BANDCAMP: Processing ${itemList.length} tracks');

                int pos = 1;
                for (final item in itemList) {
                  if (item is Map && item['item'] is Map) {
                    final trackObj = item['item'];
                    final trackName = trackObj['name'] ?? 'Track $pos';
                    final trackId = (() {
                      // Try to get Bandcamp's numeric track_id from additionalProperty
                      if (trackObj['additionalProperty'] is List) {
                        final prop = trackObj['additionalProperty'].firstWhere(
                            (p) =>
                                p is Map &&
                                p['name'] == 'track_id' &&
                                p['value'] != null,
                            orElse: () => null);
                        if (prop != null && prop['value'] != null) {
                          return prop['value'].toString();
                        }
                      }
                      // Fallback to @id or position
                      return trackObj['@id'] ??
                          trackObj['url'] ??
                          pos.toString();
                    })();
                    final duration = trackObj['duration'];
                    int durationMs = 0;
                    if (duration != null) {
                      durationMs = _parseIso8601DurationToMillis(duration,
                          logOutput: false); // Add logOutput param
                    }
                    tracks.add({
                      'trackId': trackId,
                      'trackName': trackName,
                      'trackNumber': pos,
                      'trackTimeMillis': durationMs,
                    });

                    // Remove individual track logging - too noisy
                    pos++;
                  }
                }
              }

              // After processing all tracks, log summary
              Logging.severe(
                  'BANDCAMP: Created album object with ${tracks.length} tracks');

              return {
                'id': '', // Not available in JSON-LD
                'collectionId': '',
                'name': albumTitle,
                'collectionName': albumTitle,
                'artist': artistName,
                'artistName': artistName,
                'artworkUrl': artworkUrl,
                'artworkUrl100': artworkUrl,
                'releaseDate': jsonLd['datePublished'] ?? '',
                'url': jsonLd['@id'] ?? jsonLd['url'] ?? '',
                'platform': 'bandcamp',
                'tracks': tracks,
              };
            }
          } catch (e) {
            Logging.severe('BandcampService: Failed to parse JSON-LD', e);
          }
        }
      }
      return null;
    } catch (e) {
      Logging.severe('Error extracting from JSON-LD: $e');
      return null;
    }
  }

  // Extract tracks from HTML elements
  Map<String, dynamic>? _extractTrackDataFromElements(String html, String url) {
    try {
      // Try to extract album title
      String albumTitle = 'Unknown Album';
      final albumTitleMatch =
          RegExp(r'<h2\s+class="trackTitle[^"]*">(.*?)</h2>', dotAll: true)
                  .firstMatch(html) ??
              RegExp(r'<meta\s+property="og:title"\s+content="([^"]+)"',
                      dotAll: true)
                  .firstMatch(html);
      if (albumTitleMatch != null) {
        albumTitle = _cleanHtml(albumTitleMatch.group(1) ?? albumTitle);
      }

      // Try to extract artist name
      String artistName = 'Unknown Artist';
      final artistMatch =
          RegExp(r'<span\s+itemprop="byArtist".*?>(.*?)</span>', dotAll: true)
                  .firstMatch(html) ??
              RegExp(r'<meta\s+property="og:site_name"\s+content="([^"]+)"',
                      dotAll: true)
                  .firstMatch(html);
      if (artistMatch != null) {
        artistName = _cleanHtml(artistMatch.group(1) ?? artistName);
      }

      // Try to find album art
      String artworkUrl = '';
      final artworkMatch = RegExp(
                  r'<meta\s+property="og:image"\s+content="([^"]+)"',
                  dotAll: true)
              .firstMatch(html) ??
          RegExp(r'<a\s+class="popupImage".*?href="([^"]+)"', dotAll: true)
              .firstMatch(html) ??
          RegExp(r'id="tralbumArt".*?<img\s+src="([^"]+)"', dotAll: true)
              .firstMatch(html);
      if (artworkMatch != null) {
        artworkUrl = artworkMatch.group(1) ?? '';
      }

      // Match only <tr> rows with BOTH data-track-id and data-duration
      final rowPattern = RegExp(
        r'<tr[^>]*data-track-id="(\d+)"[^>]*data-duration="([^"]+)"[^>]*>(.*?)</tr>',
        dotAll: true,
      );
      final rowMatches = rowPattern.allMatches(html).toList();

      List<Map<String, dynamic>> tracks = [];
      int pos = 1;
      for (final row in rowMatches) {
        final bandcampTrackId = row.group(1);
        final durationIso = row.group(2);
        final rowHtml = row.group(3) ?? '';

        // Extract track title
        final titleMatch =
            RegExp(r'class="track-title">(.*?)</span>', dotAll: true)
                .firstMatch(rowHtml);
        final trackName =
            titleMatch != null ? _cleanHtml(titleMatch.group(1) ?? '') : '';

        int durationMs = 0;
        if (durationIso != null && durationIso.isNotEmpty) {
          durationMs = _parseIso8601DurationToMillis(durationIso);
        }

        if (bandcampTrackId != null && trackName.isNotEmpty) {
          tracks.add({
            'trackId': bandcampTrackId,
            'trackName': trackName,
            'trackNumber': pos,
            'trackTimeMillis': durationMs,
          });
          pos++;
        }
      }

      if (tracks.isEmpty) return null;

      Logging.severe(
          'BandcampService: Extracted ${tracks.length} tracks from HTML elements');

      return {
        'id': '',
        'collectionId': '',
        'name': albumTitle,
        'collectionName': albumTitle,
        'artist': artistName,
        'artistName': artistName,
        'artworkUrl': artworkUrl,
        'artworkUrl100': artworkUrl,
        'releaseDate': '',
        'url': url,
        'platform': 'bandcamp',
        'tracks': tracks,
      };
    } catch (e) {
      Logging.severe('Error extracting from HTML elements: $e');
      return null;
    }
  }

  // Extract from meta tags
  Map<String, dynamic>? _extractFromMetaAndPage(String html, String url) {
    try {
      // Extract album title
      String albumTitle = 'Unknown Album';
      final titleMatch =
          RegExp(r'<meta\s+property="og:title"\s+content="([^"]+)"')
              .firstMatch(html);
      if (titleMatch != null) {
        albumTitle = _cleanHtml(titleMatch.group(1) ?? albumTitle);
      }

      // Extract artist
      String artistName = 'Unknown Artist';
      final artistMatch =
          RegExp(r'<meta\s+property="og:site_name"\s+content="([^"]+)"')
                  .firstMatch(html) ??
              RegExp(r'<meta\s+property="music:musician"\s+content="([^"]+)"')
                  .firstMatch(html);
      if (artistMatch != null) {
        artistName = _cleanHtml(artistMatch.group(1) ?? artistName);
      }

      // Extract album art
      String artworkUrl = '';
      final artworkMatch =
          RegExp(r'<meta\s+property="og:image"\s+content="([^"]+)"')
              .firstMatch(html);
      if (artworkMatch != null) {
        artworkUrl = artworkMatch.group(1) ?? '';
      }

      // Try to extract track information from description
      String description = '';
      final descMatch =
          RegExp(r'<meta\s+property="og:description"\s+content="([^"]+)"')
              .firstMatch(html);
      if (descMatch != null) {
        description = descMatch.group(1) ?? '';
      }

      // Try to extract track count from description
      final trackCountMatch = RegExp(r'(\d+)\s+track').firstMatch(description);
      if (trackCountMatch != null) {
        int.tryParse(trackCountMatch.group(1) ?? '0') ?? 0;
      }

      // Try to extract track names from tracklist section
      List<String> trackNames = [];
      final tracklistMatch =
          RegExp(r'<ol\s+class="track-list\s*">(.*?)</ol>', dotAll: true)
              .firstMatch(html);
      if (tracklistMatch != null) {
        final tracklist = tracklistMatch.group(1) ?? '';
        final trackItems =
            RegExp(r'<div\s+class="track-title">(.*?)</div>', dotAll: true)
                .allMatches(tracklist);
        trackNames =
            trackItems.map((m) => _cleanHtml(m.group(1) ?? '')).toList();
      }

      // If we got track names
      if (trackNames.isNotEmpty) {
        final tracks = <Map<String, dynamic>>[];
        for (int i = 0; i < trackNames.length; i++) {
          if (trackNames[i].trim().isNotEmpty) {
            tracks.add({
              'trackId': (i + 1).toString(),
              'trackName': trackNames[i],
              'trackNumber': i + 1,
              'trackTimeMillis': 0,
            });
          }
        }

        if (tracks.isNotEmpty) {
          Logging.severe(
              'BandcampService: Extracted ${tracks.length} tracks from meta and page');
          return {
            'id': '',
            'collectionId': '',
            'name': albumTitle,
            'collectionName': albumTitle,
            'artist': artistName,
            'artistName': artistName,
            'artworkUrl': artworkUrl,
            'artworkUrl100': artworkUrl,
            'releaseDate': '',
            'url': url,
            'platform': 'bandcamp',
            'tracks': tracks,
          };
        }
      }

      return null;
    } catch (e) {
      Logging.severe('Error extracting from meta and page: $e');
      return null;
    }
  }

  // Create placeholder tracks as last resort
  Map<String, dynamic>? _createPlaceholderTracks(String html, String url) {
    try {
      // Extract album title
      String albumTitle = 'Unknown Album';
      final titleMatch = RegExp(r'<title>(.*?)</title>').firstMatch(html);
      if (titleMatch != null) {
        albumTitle = _cleanHtml(titleMatch.group(1) ?? albumTitle);
      }

      // Extract artist (fallback to domain name)
      String artistName = 'Unknown Artist';
      Uri? uri = Uri.tryParse(url);
      if (uri != null) {
        final host = uri.host;
        if (host.contains('bandcamp.com')) {
          final subdomain = host.split('.').first;
          if (subdomain != 'bandcamp') {
            artistName = subdomain.replaceAll(RegExp(r'[^a-zA-Z0-9]'), ' ');
            // Convert to title case
            artistName = artistName.split(' ').map((word) {
              return word.isNotEmpty
                  ? '${word[0].toUpperCase()}${word.substring(1)}'
                  : '';
            }).join(' ');
          }
        }
      }

      // Get general page content to look for possible track names
      final bodyContent = RegExp(r'<body.*?>(.*?)</body>', dotAll: true)
              .firstMatch(html)
              ?.group(1) ??
          '';

      // Find all spans that might be track titles and are in a list structure
      final possibleTrackElements = RegExp(
              r'<(li|tr)[^>]*>.*?<(span|div)[^>]*>(.*?)</(span|div)>.*?</(li|tr)>',
              dotAll: true)
          .allMatches(bodyContent);

      List<String> possibleTracks = [];
      for (var match in possibleTrackElements) {
        final content = _cleanHtml(match.group(3) ?? '');
        if (content.isNotEmpty && content.length < 100) {
          // Avoid large blocks of text
          possibleTracks.add(content);
        }
      }

      // If we can't find anything that looks like tracks, create numbered placeholders
      if (possibleTracks.isEmpty || possibleTracks.length > 30) {
        // If unreasonable # of tracks
        // Try to estimate track count from page metrics
        int estimatedTrackCount = 1;

        // Look for references to track numbers
        final trackNumberRefs =
            RegExp(r'track\s+(\d+)', caseSensitive: false).allMatches(html);
        if (trackNumberRefs.isNotEmpty) {
          final maxTrack = trackNumberRefs
              .map((m) => int.tryParse(m.group(1) ?? '1') ?? 1)
              .reduce((a, b) => a > b ? a : b);
          estimatedTrackCount = maxTrack;
        } else {
          // Default to 8 tracks for a typical album, or more if page is larger
          estimatedTrackCount = html.length > 100000 ? 12 : 8;
        }

        // Create numbered placeholders
        possibleTracks =
            List.generate(estimatedTrackCount, (i) => 'Track ${i + 1}');
      }

      // Create track objects
      final tracks = <Map<String, dynamic>>[];
      for (int i = 0; i < possibleTracks.length; i++) {
        tracks.add({
          'trackId': (i + 1).toString(),
          'trackName': possibleTracks[i],
          'trackNumber': i + 1,
          'trackTimeMillis': 0,
        });
      }
      Logging.severe(
          'BandcampService: Created ${tracks.length} placeholder tracks');

      return {
        'id': '',
        'collectionId': '',
        'name': albumTitle,
        'collectionName': albumTitle,
        'artist': artistName,
        'artistName': artistName,
        'artworkUrl': '',
        'artworkUrl100': '',
        'releaseDate': '',
        'url': url,
        'platform': 'bandcamp',
        'tracks': tracks,
      };
    } catch (e) {
      Logging.severe('Error creating placeholder tracks: $e');
      return null;
    }
  }

  // Helper to clean HTML content
  String _cleanHtml(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  // Helper to parse ISO 8601 duration (e.g. PT3M45S or P00H05M34S)
  int _parseIso8601DurationToMillis(String? duration, {bool logOutput = true}) {
    if (duration == null) return 0;

    try {
      // New Pattern for P00H05M34S format
      if (duration.startsWith('P') &&
          duration.contains('H') &&
          duration.contains('M') &&
          duration.contains('S')) {
        final hoursMatch = RegExp(r'P\d+H').firstMatch(duration);
        final hours = hoursMatch != null
            ? int.tryParse(
                    hoursMatch.group(0)!.replaceAll(RegExp(r'[PH]'), '')) ??
                0
            : 0;

        final minutesMatch = RegExp(r'\d+M').firstMatch(duration);
        final minutes = minutesMatch != null
            ? int.tryParse(minutesMatch.group(0)!.replaceAll('M', '')) ?? 0
            : 0;

        final secondsMatch = RegExp(r'\d+S').firstMatch(duration);
        final seconds = secondsMatch != null
            ? int.tryParse(secondsMatch.group(0)!.replaceAll('S', '')) ?? 0
            : 0;
        return ((hours * 3600) + (minutes * 60) + seconds) * 1000;
      }

      // Standard PT3M45S format
      final match =
          RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?').firstMatch(duration);
      if (match == null) return 0;

      final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
      final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
      final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;

      // Calculate milliseconds
      final milliseconds = ((hours * 3600) + (minutes * 60) + seconds) * 1000;

      // Only log if explicitly requested
      if (logOutput) {
        Logging.severe('Parsed duration $duration to $milliseconds ms');
      }

      return milliseconds;
    } catch (e) {
      Logging.severe('Error parsing ISO 8601 duration: $e');
      return 0;
    }
  }
}
