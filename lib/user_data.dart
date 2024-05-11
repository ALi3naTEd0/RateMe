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
      return savedAlbums;
    } else {
      return [];
    }
  }

  static void saveAlbum(Map<String, dynamic> album) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');
    if (savedAlbumsJson == null) {
      savedAlbumsJson = [];
    }
    String albumJson = jsonEncode(album);
    savedAlbumsJson.add(albumJson);
    await prefs.setStringList('saved_albums', savedAlbumsJson);
  }
}
