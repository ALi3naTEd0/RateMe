import 'package:shared_preferences/shared_preferences.dart';

Future<List<String>> getSavedAlbumsFromSharedPreferences() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  List<String>? savedAlbums = prefs.getStringList('saved_albums') ?? [];
  return savedAlbums;
}
