import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'logging.dart';

class SearchService {
  /// Detect platform from URL or search term
  static String detectPlatform(String input) {
    if (input.contains('music.apple.com') || input.contains('itunes.apple.com')) {
      return 'itunes';
    } else if (input.contains('bandcamp.com')) {
      return 'bandcamp';
    } else {
      // Default to iTunes for search terms
      return 'itunes';
    }
  }

  /// Search albums based on query or URL
  static Future<List<dynamic>> searchAlbums(String query) async {
    if (query.isEmpty) return [];
    
    if (query.contains('bandcamp.com')) {
      try {
        // Get album info
        final response = await http.get(Uri.parse(query));
        final document = parse(response.body);
        
        // First try to get JSON-LD data
        var ldJsonScript = document.querySelector('script[type="application/ld+json"]');
        if (ldJsonScript != null) {
          final ldJson = jsonDecode(ldJsonScript.text);
          Logging.severe('Bandcamp JSON-LD data:', ldJson); // Debug log
          
          // Extract basic info
          final albumData = {
            'collectionName': ldJson['name'],
            'artistName': ldJson['byArtist']?['name'],
            'artworkUrl100': ldJson['image'],
            'url': query,
            'platform': 'bandcamp',
            'releaseDate': ldJson['datePublished'],
          };
          
          // Extract tracks
          if (ldJson['track']?['itemListElement'] != null) {
            final tracks = [];
            for (var item in ldJson['track']['itemListElement']) {
              final track = item['item'];
              final props = track['additionalProperty'] as List;
              final trackId = props.firstWhere(
                (p) => p['name'] == 'track_id', 
                orElse: () => {'value': null}
              )['value'];
              
              tracks.add({
                'trackId': trackId ?? DateTime.now().millisecondsSinceEpoch,
                'trackNumber': item['position'],
                'trackName': track['name'],
                'trackTimeMillis': _parseBandcampDuration(track['duration']),
              });
            }
            albumData['tracks'] = tracks;
          }
          
          Logging.severe('Processed Bandcamp album data:', albumData); // Debug log
          return [albumData];
        }
        
        // Fallback to meta tags if JSON-LD not available
        final title = document.querySelector('meta[property="og:title"]')?.attributes['content'];
        final artist = document.querySelector('meta[property="og:site_name"]')?.attributes['content'];
        final artwork = document.querySelector('meta[property="og:image"]')?.attributes['content'];
        
        Logging.severe('Bandcamp meta tags:', {
          'title': title,
          'artist': artist,
          'artwork': artwork
        }); // Debug log
        
        if (title != null) {
          return [{
            'collectionName': title.split(', by').first.trim(),
            'artistName': artist ?? title.split(', by').last.trim(),
            'artworkUrl100': artwork,
            'url': query,
            'platform': 'bandcamp'
          }];
        }
      } catch (e) {
        Logging.severe('Error processing Bandcamp URL', e);
      }
      return [];
    }
    
    // Handle non-Bandcamp searches
    return await searchiTunesAlbums(query);
  }

  /// Enhanced iTunes search with better handling of clean versions
  static Future<List<dynamic>> searchiTunesAlbums(String query) async {
    try {
      // 1. First search by general term
      final searchUrl = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
        '&entity=album&limit=50&sort=recent'
      );
      
      final searchResponse = await http.get(searchUrl);
      final searchData = jsonDecode(searchResponse.body);
      
      // 2. Search specifically by artist name to improve relevance
      final artistSearchUrl = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
        '&attribute=artistTerm&entity=album&limit=100'
      );
      
      final artistSearchResponse = await http.get(artistSearchUrl);
      final artistSearchData = jsonDecode(artistSearchResponse.body);
      
      // Combine results, filter and handle duplicates
      final Map<String, dynamic> uniqueAlbums = {};
      final List<dynamic> artistAlbums = [];
      final List<dynamic> otherAlbums = [];

      // Process artist-specific search results (higher priority)
      _processSearchResults(artistSearchData['results'], uniqueAlbums, true);
      
      // Apply the same deduplication logic to general search results
      _processSearchResults(searchData['results'], uniqueAlbums, false);
      
      // Filter and sort results
      final validAlbums = _filterAndSortAlbums(uniqueAlbums.values.toList(), query);
      
      // 4. If there's a specific artist match, get their full discography
      if (validAlbums.where((a) => 
        a['artistName'].toString().toLowerCase() == query.toLowerCase()
      ).isNotEmpty) {
        await _appendArtistDiscography(validAlbums, query);
      }
      
      return validAlbums;
    } catch (e) {
      Logging.severe('Error searching iTunes albums', e);
      return [];
    }
  }

  /// Fetch album information from Bandcamp
  static Future<Map<String, dynamic>?> fetchBandcampAlbumInfo(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = parse(response.body);
        var ldJsonScript = document.querySelector('script[type="application/ld+json"]');
        
        if (ldJsonScript != null) {
          final ldJson = jsonDecode(ldJsonScript.text);
          
          // Extract metadata from JSON-LD
          return {
            'id': ldJson['@id'] ?? url.hashCode,
            'name': ldJson['name'] ?? 'Unknown Album',
            'artist': ldJson['byArtist']?['name'] ?? 'Unknown Artist',
            'artworkUrl': ldJson['image'] ?? '',
            'url': url,
            'platform': 'bandcamp',
            'releaseDate': ldJson['datePublished'],
            'metadata': ldJson,
          };
        }
      }
      throw Exception('Failed to load Bandcamp album');
    } catch (e) {
      Logging.severe('Failed to fetch Bandcamp album info', e);
      return null;
    }
  }

  /// Process search results and handle duplicates
  static void _processSearchResults(List<dynamic> results, Map<String, dynamic> uniqueAlbums, bool isArtistSearch) {
    for (var item in results) {
      if (item['wrapperType'] == 'collection' && 
          item['collectionType'] == 'Album') {
          
        final String albumName = item['collectionName'].toString();
        final String artistName = item['artistName'].toString();
        
        final String cleanAlbumName = albumName
            .replaceAll(RegExp(r' - Single$'), '')
            .replaceAll(RegExp(r' - EP$'), '');
            
        final String albumKey = "${artistName}_${cleanAlbumName}".toLowerCase();
        
        if (uniqueAlbums.containsKey(albumKey)) {
          _handleDuplicate(uniqueAlbums, albumKey, item);
        } else {
          _addNewAlbum(uniqueAlbums, albumKey, item);
        }
      }
    }
  }

  /// Handle duplicate album entries
  static void _handleDuplicate(Map<String, dynamic> uniqueAlbums, String albumKey, dynamic newItem) {
    final existing = uniqueAlbums[albumKey];
    
    if ((newItem['trackCount'] ?? 0) > (existing['trackCount'] ?? 0)) {
      uniqueAlbums[albumKey] = newItem;
    }
    
    if (existing['collectionExplicitness'] != newItem['collectionExplicitness']) {
      if (newItem['collectionExplicitness'] == 'explicit') {
        uniqueAlbums[albumKey] = newItem;
      }
      
      if (newItem['collectionExplicitness'] == 'cleaned' && 
          !newItem['collectionName'].toString().contains('(Clean)')) {
        final cleanItem = Map<String, dynamic>.from(newItem);
        cleanItem['collectionName'] = "${cleanItem['collectionName']} (Clean)";
        uniqueAlbums["${albumKey}_clean"] = cleanItem;
      }
    }
  }

  /// Add new album to unique albums map
  static void _addNewAlbum(Map<String, dynamic> uniqueAlbums, String albumKey, dynamic item) {
    if (item['collectionExplicitness'] == 'cleaned' && 
        !item['collectionName'].toString().contains('(Clean)')) {
      item = Map<String, dynamic>.from(item);
      item['collectionName'] = "${item['collectionName']} (Clean)";
    }
    
    uniqueAlbums[albumKey] = item;
  }

  /// Filter and sort album results
  static List<dynamic> _filterAndSortAlbums(List<dynamic> albums, String query) {
    // Filter out albums with no track information
    final validAlbums = albums.where((album) {
      return album['trackCount'] != null && album['trackCount'] > 0;
    }).toList();
    
    // Separate exact artist match albums from others
    final artistAlbums = <dynamic>[];
    final otherAlbums = <dynamic>[];
    
    for (var album in validAlbums) {
      if (album['artistName'].toString().toLowerCase() == query.toLowerCase()) {
        artistAlbums.add(album);
      } else {
        otherAlbums.add(album);
      }
    }
    
    // Sort by release date (newest first)
    final sortByDate = (dynamic a, dynamic b) {
      final DateTime dateA = DateTime.parse(a['releaseDate']);
      final DateTime dateB = DateTime.parse(b['releaseDate']);
      return dateB.compareTo(dateA);
    };
    
    artistAlbums.sort(sortByDate);
    otherAlbums.sort(sortByDate);
    
    // Combine results prioritizing exact artist match
    return [...artistAlbums, ...otherAlbums];
  }

  /// Append artist's full discography to results
  static Future<void> _appendArtistDiscography(List<dynamic> results, String query) async {
    final artistId = results.first['artistId'];
    final artistUrl = Uri.parse(
      'https://itunes.apple.com/lookup?id=$artistId'
      '&entity=album&limit=200'
    );
    
    final artistResponse = await http.get(artistUrl);
    final artistData = jsonDecode(artistResponse.body);
    
    for (var item in artistData['results']) {
      if (item['wrapperType'] == 'collection' && 
          item['collectionType'] == 'Album') {
        
        bool alreadyAdded = results.any((existing) {
          return existing['collectionId'] == item['collectionId'];
        });
        
        if (!alreadyAdded) {
          if (item['collectionExplicitness'] == 'cleaned' && 
              !item['collectionName'].toString().contains('(Clean)')) {
            item = Map<String, dynamic>.from(item);
            item['collectionName'] = "${item['collectionName']} (Clean)";
          }
          
          if (item['artistName'].toString().toLowerCase() == query.toLowerCase()) {
            results.insert(
              results.where((a) => 
                a['artistName'].toString().toLowerCase() == query.toLowerCase()
              ).length,
              item
            );
          } else {
            results.add(item);
          }
        }
      }
    }
  }

  static int _parseBandcampDuration(String duration) {
    try {
      final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
      final match = regex.firstMatch(duration);
      
      if (match != null) {
        final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
        final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
        return (hours * 3600 + minutes * 60 + seconds) * 1000;
      }
    } catch (e) {
      Logging.severe('Error parsing duration', e);
    }
    return 0;
  }
}
