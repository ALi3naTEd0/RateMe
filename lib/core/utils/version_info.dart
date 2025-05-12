/// Contains version information for the app
class VersionInfo {
  /// Current app version string
  static const String versionString = '1.1.2';

  /// Build number for internal tracking
  static const int buildNumber = 1;

  /// Full version string including build number
  static String get fullVersionString => '$versionString-$buildNumber';
}
