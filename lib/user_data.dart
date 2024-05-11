import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Class for managing user data such as saved albums.
class UserData {
  /// Retrieves the list of saved albums from SharedPreferences.
  static Future<List<Map<String, dynamic>>> getSavedAlbums() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');
    if (savedAlbumsJson != null) {
      List<Map<String, dynamic>> savedAlbums = [];
      for (String json in savedAlbumsJson) {
        savedAlbums.add(jsonDecode(json));
      }
      return savedAlbums;
    } else {
      return [];
    }
  }

  /// Saves the given album to SharedPreferences.
  static Future<void> saveAlbum(Map<String, dynamic> album) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');
    if (savedAlbumsJson == null) {
      savedAlbumsJson = [];
    }
    String albumJson = jsonEncode(album);
    savedAlbumsJson.add(albumJson);
    await prefs.setStringList('saved_albums', savedAlbumsJson);
  }

  /// Deletes the given album from SharedPreferences.
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
    }
  }
}
