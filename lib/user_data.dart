import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

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

  static Future<List<Map<String, dynamic>>> getSavedAlbumRatings(int albumId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedRatingsJson = prefs.getStringList('saved_ratings_$albumId');
    
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
      Map<String, dynamic> existingAlbum = jsonDecode(savedAlbumsJson[existingIndex]);
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

      savedAlbums.removeWhere((savedAlbum) => savedAlbum['collectionId'] == album['collectionId']);
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

  static Future<void> exportRatings(String filePath) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');

    if (savedAlbumsJson != null) {
      // Obtener el historial de calificaciones de cada álbum guardado
      Map<int, List<Map<String, dynamic>>> ratingsMap = {};
      for (String json in savedAlbumsJson) {
        Map<String, dynamic> album = jsonDecode(json);
        int albumId = album['collectionId'];
        List<Map<String, dynamic>> ratings = await getSavedAlbumRatings(albumId);
        ratingsMap[albumId] = ratings;
      }

      // Escribir el historial de calificaciones en un archivo
      File file = File(filePath);
      await file.writeAsString(jsonEncode(ratingsMap));
    }
  }

  static Future<void> importRatings(String filePath) async {
    File file = File(filePath);
    String fileContent = await file.readAsString();
    Map<int, List<Map<String, dynamic>>> ratingsMap = jsonDecode(fileContent);

    for (int albumId in ratingsMap.keys) {
      List<Map<String, dynamic>> ratings = ratingsMap[albumId] ?? [];
      for (Map<String, dynamic> rating in ratings) {
        int trackId = rating['trackId'];
        double ratingValue = rating['rating'];
        await saveRating(albumId, trackId, ratingValue);
      }
    }
  }
}
