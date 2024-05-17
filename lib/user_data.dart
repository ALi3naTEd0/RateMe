import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class UserData {
  static Future<List<Map<String, dynamic>>> getSavedAlbums() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');
    if (savedAlbumsJson != null) {
      List<Map<String, dynamic>> savedAlbums = [];
      for (String json in savedAlbumsJson) {
        savedAlbums.add(jsonDecode(json));
      }

      // Obtener el orden guardado
      List<String>? albumOrder = prefs.getStringList('savedAlbumsOrder');
      if (albumOrder != null) {
        savedAlbums.sort((a, b) => albumOrder.indexOf(a['collectionId'].toString())
            .compareTo(albumOrder.indexOf(b['collectionId'].toString())));
      }

      return savedAlbums;
    } else {
      return [];
    }
  }

  static Future<void> saveAlbum(Map<String, dynamic> album) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');
    if (savedAlbumsJson == null) {
      savedAlbumsJson = [];
    }
    String albumJson = jsonEncode(album);
    savedAlbumsJson.add(albumJson);
    await prefs.setStringList('saved_albums', savedAlbumsJson);

    // Guardar el nuevo orden
    List<String> albumOrder = savedAlbumsJson.map((json) => jsonDecode(json)['collectionId'].toString()).toList();
    await prefs.setStringList('savedAlbumsOrder', albumOrder);
  }

  static Future<void> deleteAlbum(Map<String, dynamic> album) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');
    if (savedAlbumsJson != null) {
      List<Map<String, dynamic>> savedAlbums = [];
      for (String json in savedAlbumsJson) {
        savedAlbums.add(jsonDecode(json));
      }
      savedAlbums.removeWhere((savedAlbum) => savedAlbum['collectionId'] == album['collectionId']);
      savedAlbumsJson = savedAlbums.map((album) => jsonEncode(album)).toList();
      await prefs.setStringList('saved_albums', savedAlbumsJson);

      // Actualizar el orden
      List<String> albumOrder = savedAlbums.map((album) => album['collectionId'].toString()).toList();
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
}
