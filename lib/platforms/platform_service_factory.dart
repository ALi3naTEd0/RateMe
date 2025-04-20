import 'platform_service_base.dart';
import 'spotify_service.dart';
import 'apple_music_service.dart';
import 'deezer_service.dart';
import 'discogs_service.dart';
import '../logging.dart';
import 'bandcamp_service.dart';

/// Factory to create platform-specific services
class PlatformServiceFactory {
  // Singleton pattern
  static final PlatformServiceFactory _instance =
      PlatformServiceFactory._internal();
  factory PlatformServiceFactory() => _instance;
  PlatformServiceFactory._internal();

  // Cache created services
  final Map<String, PlatformServiceBase> _services = {};

  /// Get a service for the specified platform
  PlatformServiceBase getService(String platformId) {
    final normalizedId = platformId.toLowerCase();

    // Return cached service if available
    if (_services.containsKey(normalizedId)) {
      return _services[normalizedId]!;
    }

    // Create new service instance
    PlatformServiceBase service;

    switch (normalizedId) {
      case 'spotify':
        service = SpotifyService();
        break;
      case 'apple_music':
      case 'itunes':
        service = AppleMusicService();
        break;
      case 'deezer':
        service = DeezerService();
        break;
      case 'discogs':
        // Ensure we're using the correct implementation
        service = DiscogsService();
        break;
      case 'bandcamp':
        service = BandcampService();
        break;
      default:
        Logging.severe('Unsupported platform service: $platformId');
        throw UnsupportedError('Platform not supported: $platformId');
    }

    // Cache the service
    _services[normalizedId] = service;
    return service;
  }

  /// Check if a platform is supported
  bool isPlatformSupported(String platformId) {
    final normalizedId = platformId.toLowerCase();
    return ['spotify', 'apple_music', 'itunes', 'deezer', 'discogs', 'bandcamp']
        .contains(normalizedId);
  }
}
