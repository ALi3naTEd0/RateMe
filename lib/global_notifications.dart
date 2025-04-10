import 'dart:async';
import 'search_service.dart';
import 'logging.dart';

/// Class for handling app-wide notifications/events
class GlobalNotifications {
  // Stream controller for search platform changes
  static final StreamController<SearchPlatform> _platformChangeController =
      StreamController<SearchPlatform>.broadcast();

  /// Stream of search platform changes that can be listened to throughout the app
  static Stream<SearchPlatform> get onSearchPlatformChanged =>
      _platformChangeController.stream;

  /// Notify when default search platform changes
  static void defaultSearchPlatformChanged(SearchPlatform platform) {
    Logging.severe(
        'Broadcasting default platform change: ${platform.displayName}');
    _platformChangeController.add(platform);
  }

  /// Close all streams when app is terminated
  static void dispose() {
    _platformChangeController.close();
  }
}
