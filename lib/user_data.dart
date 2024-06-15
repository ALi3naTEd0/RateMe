import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class UserData {
  static Future<List<Map<String, dynamic>>> getSavedAlbums() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');
    List<String>? albumOrder = prefs.getStringList('savedAlbumsOrder');

    if (savedAlbumsJson != null && albumOrder != null) {
      List<Map<String, dynamic>> savedAlbums = [];
      Map<String, Map<String, dynamic>> albumMap = {};

      for (String json in savedAlbumsJson) {
        Map<String, dynamic> album = jsonDecode(json);
        albumMap[album['collectionId'].toString()] = album;
      }

      for (String id in albumOrder) {
        if (albumMap.containsKey(id)) {
          savedAlbums.add(albumMap[id]!);
        }
      }

      return savedAlbums;
    } else {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getSavedAlbumRatings(
      int albumId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedRatingsJson =
        prefs.getStringList('saved_ratings_$albumId');

    if (savedRatingsJson != null) {
      List<Map<String, dynamic>> savedRatings = [];

      for (String json in savedRatingsJson) {
        savedRatings.add(jsonDecode(json));
      }

      return savedRatings;
    } else {
      return [];
    }
  }

  static Future<void> saveAlbum(Map<String, dynamic> album) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums') ?? [];
    List<String>? albumOrder = prefs.getStringList('savedAlbumsOrder') ?? [];

    String albumJson = jsonEncode(album);
    String albumId = album['collectionId'].toString();

    int existingIndex = savedAlbumsJson.indexWhere((json) {
      Map<String, dynamic> existingAlbum = jsonDecode(json);
      return existingAlbum['collectionId'] == album['collectionId'];
    });

    if (existingIndex != -1) {
      Map<String, dynamic> existingAlbum =
          jsonDecode(savedAlbumsJson[existingIndex]);
      existingAlbum.addAll(album);
      savedAlbumsJson[existingIndex] = jsonEncode(existingAlbum);
    } else {
      savedAlbumsJson.add(albumJson);
      albumOrder.add(albumId);
    }

    await prefs.setStringList('saved_albums', savedAlbumsJson);
    await prefs.setStringList('savedAlbumsOrder', albumOrder);
  }

  static Future<void> deleteAlbum(Map<String, dynamic> album) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');
    List<String>? albumOrder = prefs.getStringList('savedAlbumsOrder');

    if (savedAlbumsJson != null && albumOrder != null) {
      List<Map<String, dynamic>> savedAlbums = [];

      for (String json in savedAlbumsJson) {
        savedAlbums.add(jsonDecode(json));
      }

      savedAlbums.removeWhere(
          (savedAlbum) => savedAlbum['collectionId'] == album['collectionId']);
      albumOrder.remove(album['collectionId'].toString());

      savedAlbumsJson = savedAlbums.map((album) => jsonEncode(album)).toList();

      await prefs.setStringList('saved_albums', savedAlbumsJson);
      await prefs.setStringList('savedAlbumsOrder', albumOrder);

      await _deleteRatings(album['collectionId']);
    }
  }

  static Future<void> _deleteRatings(int collectionId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_ratings_$collectionId');
  }

  static Future<void> saveAlbumOrder(List<String> albumIds) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('savedAlbumsOrder', albumIds);
  }

  static Future<List<String>> getSavedAlbumOrder() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? albumIds = prefs.getStringList('savedAlbumsOrder');
    return albumIds ?? [];
  }

  static Future<void> saveRating(
      int albumId, int trackId, double rating) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedRatingsJson =
        prefs.getStringList('saved_ratings_$albumId') ?? [];

    int trackIndex = savedRatingsJson.indexWhere((json) {
      Map<String, dynamic> ratingData = jsonDecode(json);
      return ratingData['trackId'] == trackId;
    });

    if (trackIndex != -1) {
      Map<String, dynamic> ratingData =
          jsonDecode(savedRatingsJson[trackIndex]);
      ratingData['rating'] = rating;
      savedRatingsJson[trackIndex] = jsonEncode(ratingData);
    } else {
      Map<String, dynamic> ratingData = {'trackId': trackId, 'rating': rating};
      String ratingJson = jsonEncode(ratingData);
      savedRatingsJson.add(ratingJson);
    }

    await prefs.setStringList('saved_ratings_$albumId', savedRatingsJson);
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
    if (trackIdsStr != null) {
      return trackIdsStr.map((id) => int.tryParse(id) ?? 0).toList();
    } else {
      return [];
    }
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
}
