import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'logging.dart';

class UserData {
  static const String _savedAlbumsKey = 'saved_albums';
  static const String _savedAlbumOrderKey = 'saved_album_order';
  static const String _ratingsPrefix = 'saved_ratings_';

  static Future<List<Map<String, dynamic>>> getSavedAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> albumOrder = prefs.getStringList(_savedAlbumOrderKey) ?? [];
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      
      List<Map<String, dynamic>> albums = savedAlbums
          .map((albumJson) => jsonDecode(albumJson) as Map<String, dynamic>)
          .toList();

      albums.sort((a, b) {
        int indexA = albumOrder.indexOf(a['collectionId'].toString());
        int indexB = albumOrder.indexOf(b['collectionId'].toString());
        return indexA.compareTo(indexB);
      });

      return albums;
    } catch (e, stackTrace) {
      Logging.severe('Error getting saved albums', e, stackTrace);
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getSavedAlbumRatings(
      int albumId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String key = '${_ratingsPrefix}$albumId';
      
      // Debug log para ver qué estamos recuperando
      Logging.info('Getting ratings for album: $albumId');
      Logging.info('Using key: $key');
      
      List<String> ratings = prefs.getStringList(key) ?? [];
      Logging.info('Retrieved ratings: $ratings');
      
      final decodedRatings = ratings
          .map((r) => jsonDecode(r) as Map<String, dynamic>)
          .toList();
      
      Logging.info('Decoded ratings: $decodedRatings');
      return decodedRatings;
    } catch (e, stackTrace) {
      Logging.severe('Error getting saved ratings for album $albumId', e, stackTrace);
      return [];
    }
  }

  static Future<void> saveAlbum(Map<String, dynamic> album) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      String albumJson = jsonEncode(album);

      if (!savedAlbums.contains(albumJson)) {
        savedAlbums.add(albumJson);
        await prefs.setStringList(_savedAlbumsKey, savedAlbums);
        
        String albumId = album['collectionId'].toString();
        List<String> albumOrder = prefs.getStringList(_savedAlbumOrderKey) ?? [];
        if (!albumOrder.contains(albumId)) {
          albumOrder.add(albumId);
          await prefs.setStringList(_savedAlbumOrderKey, albumOrder);
        }
      }
    } catch (e, stackTrace) {
      Logging.severe('Error saving album', e, stackTrace);
      rethrow;
    }
  }

  static Future<void> deleteAlbum(Map<String, dynamic> album) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      String albumJson = jsonEncode(album);
      
      savedAlbums.removeWhere((saved) => saved == albumJson);
      await prefs.setStringList(_savedAlbumsKey, savedAlbums);

      String albumId = album['collectionId'].toString();
      List<String> albumOrder = prefs.getStringList(_savedAlbumOrderKey) ?? [];
      albumOrder.remove(albumId);
      await prefs.setStringList(_savedAlbumOrderKey, albumOrder);

      await prefs.remove('${_ratingsPrefix}${album['collectionId']}');
    } catch (e, stackTrace) {
      Logging.severe('Error deleting album', e, stackTrace);
      rethrow;
    }
  }

  static Future<void> _deleteRatings(int collectionId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_ratings_$collectionId');
  }

  static Future<void> saveAlbumOrder(List<String> albumIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_savedAlbumOrderKey, albumIds);
    } catch (e, stackTrace) {
      Logging.severe('Error saving album order', e, stackTrace);
      rethrow;
    }
  }

  static Future<List<String>> getSavedAlbumOrder() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? albumIds = prefs.getStringList('savedAlbumsOrder');
    return albumIds ?? [];
  }

  static Future<void> saveRating(
      int albumId, int trackId, double rating) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String key = '${_ratingsPrefix}$albumId';
      
      // Debug log para ver qué valores estamos guardando
      Logging.info('Saving rating - Album: $albumId, Track: $trackId, Rating: $rating');
      Logging.info('Using key: $key');

      List<String> ratings = prefs.getStringList(key) ?? [];
      Logging.info('Existing ratings: $ratings');
      
      Map<String, dynamic> ratingData = {
        'trackId': trackId,
        'rating': rating,
        'timestamp': DateTime.now().toIso8601String(),
      };

      int index = ratings.indexWhere((r) {
        Map<String, dynamic> saved = jsonDecode(r);
        return saved['trackId'] == trackId;
      });

      if (index != -1) {
        ratings[index] = jsonEncode(ratingData);
      } else {
        ratings.add(jsonEncode(ratingData));
      }

      await prefs.setStringList(key, ratings);
      Logging.info('Saved ratings successfully: ${ratings.toString()}');
      
      // Verificar inmediatamente después de guardar
      List<String>? verifyRatings = prefs.getStringList(key);
      Logging.info('Verification - Retrieved ratings: ${verifyRatings.toString()}');
    } catch (e, stackTrace) {
      Logging.severe('Error saving rating', e, stackTrace);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> getSavedAlbumById(int albumId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');

    if (savedAlbumsJson != null) {
      for (String json in savedAlbumsJson) {
        Map<String, dynamic> album = jsonDecode(json);

        if (album['collectionId'] == albumId) {
          return album;
        }
      }
    }

    return null;
  }

  static Future<List<int>> getSavedAlbumTrackIds(int collectionId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String key = 'album_track_ids_$collectionId';
    List<String>? trackIdsStr = prefs.getStringList(key);
    return trackIdsStr?.map((id) => int.tryParse(id) ?? 0).toList() ?? [];
  }

  static Future<void> saveAlbumTrackIds(
      int collectionId, List<int> trackIds) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String key = 'album_track_ids_$collectionId';
    List<String> trackIdsStr = trackIds.map((id) => id.toString()).toList();
    await prefs.setStringList(key, trackIdsStr);
  }

  static Future<void> exportRatings(String filePath) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');

    if (savedAlbumsJson != null) {
      Map<int, List<Map<String, dynamic>>> ratingsMap = {};
      for (String json in savedAlbumsJson) {
        Map<String, dynamic> album = jsonDecode(json);
        int albumId = album['collectionId'];
        List<Map<String, dynamic>> ratings =
            await getSavedAlbumRatings(albumId);
        ratingsMap[albumId] = ratings;
      }

      // Write ratingsMap to file
      // Example implementation for writing to file omitted for brevity
    }
  }

  static Future<void> importRatings(String filePath) async {
    // Example implementation for importing ratings from file omitted for brevity
  }

  static Future<Map<int, double>?> getRatings(int albumId) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String key = '${_ratingsPrefix}$albumId';  // Usar el mismo prefijo que en saveRating
      List<String>? savedRatings = prefs.getStringList(key);

      if (savedRatings != null && savedRatings.isNotEmpty) {
        Map<int, double> ratingsMap = {};
        
        for (String ratingJson in savedRatings) {
          Map<String, dynamic> rating = jsonDecode(ratingJson);
          int trackId = rating['trackId'];
          double ratingValue = rating['rating'].toDouble();
          ratingsMap[trackId] = ratingValue;
        }

        return ratingsMap;
      }
    } catch (e, stackTrace) {
      Logging.severe('Error getting ratings for album $albumId', e, stackTrace);
    }
    return null;
  }

  // Método para verificar las calificaciones guardadas (debug)
  static Future<void> debugPrintRatings(int albumId) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String key = '${_ratingsPrefix}$albumId';
      List<String>? savedRatings = prefs.getStringList(key);
      
      Logging.info('Debug: Ratings for album $albumId');
      Logging.info('Key used: $key');
      Logging.info('Raw saved ratings: $savedRatings');
      
      if (savedRatings != null) {
        for (String rating in savedRatings) {
          Logging.info('Rating entry: $rating');
        }
      }
    } catch (e, stackTrace) {
      Logging.severe('Error debugging ratings', e, stackTrace);
    }
  }

  // Método para inspeccionar todas las keys y valores en SharedPreferences
  static Future<void> inspectAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      
      Logging.info('=== INSPECTING ALL SHARED PREFERENCES DATA ===');
      Logging.info('Total keys found: ${allKeys.length}');
      
      for (String key in allKeys) {
        if (key.startsWith(_ratingsPrefix)) {
          final ratings = prefs.getStringList(key);
          Logging.info('Rating Key: $key');
          Logging.info('Rating Values: $ratings');
          
          if (ratings != null) {
            for (String rating in ratings) {
              Logging.info('  Decoded rating: ${jsonDecode(rating)}');
            }
          }
        } else {
          final value = prefs.get(key);
          Logging.info('Key: $key');
          Logging.info('Value: $value');
        }
      }
      Logging.info('=== END INSPECTION ===');
    } catch (e, stackTrace) {
      Logging.severe('Error inspecting data', e, stackTrace);
    }
  }

  static Future<void> clearAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      Logging.info('All user data cleared');
    } catch (e, stackTrace) {
      Logging.severe('Error clearing all data', e, stackTrace);
      rethrow;
    }
  }
}
