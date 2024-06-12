import 'package:shared_preferences/shared_preferences.dart';

class UniqueIdGenerator {
  static int _lastCollectionId = 1000000000;
  static int _lastTrackId = 2000000000;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!_initialized) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      _lastCollectionId = prefs.getInt('lastCollectionId') ?? 1000000000;
      _lastTrackId = prefs.getInt('lastTrackId') ?? 2000000000;
      _initialized = true;
    }
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

  static int getLastCollectionId() {
    return _lastCollectionId;
  }

  static int getLastTrackId() {
    return _lastTrackId;
  }
}
