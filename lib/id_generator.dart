import 'package:shared_preferences/shared_preferences.dart';

class UniqueIdGenerator {
  static late int _lastCollectionId;
  static late int _lastTrackId;

  static Future<void> initialize() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _lastCollectionId = prefs.getInt('lastCollectionId') ?? 1000000000;
    _lastTrackId = prefs.getInt('lastTrackId') ?? 2000000000;
  }

  static Future<void> saveLastGeneratedIds() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastCollectionId', _lastCollectionId);
    await prefs.setInt('lastTrackId', _lastTrackId);
  }

  static int generateUniqueCollectionId() {
    _lastCollectionId++;
    saveLastGeneratedIds();
    return _lastCollectionId;
  }

  static int generateUniqueTrackId() {
    _lastTrackId++;
    saveLastGeneratedIds();
    return _lastTrackId;
  }
}
