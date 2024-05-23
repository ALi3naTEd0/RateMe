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

  static Future<void> saveAlbum(Map<String, dynamic> album) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');
    List<String>? albumOrder = prefs.getStringList('savedAlbumsOrder');

    if (savedAlbumsJson == null) {
      savedAlbumsJson = [];
    }
    if (albumOrder == null) {
      albumOrder = [];
    }

    String albumJson = jsonEncode(album);
    savedAlbumsJson.add(albumJson);
    albumOrder.add(album['collectionId'].toString());

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

      savedAlbums.removeWhere((savedAlbum) => savedAlbum['collectionId'] == album['collectionId']);
      albumOrder.remove(album['collectionId'].toString());

      savedAlbumsJson = savedAlbums.map((album) => jsonEncode(album)).toList();

      await prefs.setStringList('saved_albums', savedAlbumsJson);
      await prefs.setStringList('savedAlbumsOrder', albumOrder);
    }
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

  static Future<List<Map<String, dynamic>>> getSavedAlbumRatings(int albumId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedRatingsJson = prefs.getStringList('saved_ratings_$albumId');
    if (savedRatingsJson != null) {
      List<Map<String, dynamic>> savedRatings = [];
      for (String json in savedRatingsJson) {
        savedRatings.add(jsonDecode(json));
      }
      print('Ratings loaded: $savedRatings');
      return savedRatings;
    } else {
      print('No ratings found for album $albumId');
      return [];
    }
  }

  static Future<void> saveRating(int albumId, int trackId, double rating) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedRatingsJson = prefs.getStringList('saved_ratings_$albumId');
    if (savedRatingsJson == null) {
      savedRatingsJson = [];
    }
    Map<String, dynamic> ratingData = {'trackId': trackId, 'rating': rating};
    String ratingJson = jsonEncode(ratingData);
    savedRatingsJson.add(ratingJson);
    await prefs.setStringList('saved_ratings_$albumId', savedRatingsJson);
    print('Rating saved: $ratingData');
  }

  static Future<bool> isAlbumSaved(int albumId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');
    if (savedAlbumsJson != null) {
      for (String json in savedAlbumsJson) {
        Map<String, dynamic> album = jsonDecode(json);
        if (album['collectionId'] == albumId) {
          return true;
        }
      }
    }
    return false;
  }
}
