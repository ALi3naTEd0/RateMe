import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/logging.dart';
import 'version_info.dart';

class UpdateChecker {
  static const String githubApiUrl = 'https://api.github.com/repos/ALi3naTEd0/RateMe/releases/latest';
  static const String githubReleasesUrl = 'https://github.com/ALi3naTEd0/RateMe/releases';

  static Future<UpdateInfo?> checkForUpdates() async {
    try {
      Logging.severe('Checking for updates from GitHub...');
      
      final response = await http.get(
        Uri.parse(githubApiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['tag_name'] as String;
        final releaseUrl = data['html_url'] as String;
        final publishedAt = DateTime.parse(data['published_at']);
        final releaseNotes = data['body'] as String? ?? '';
        final assets = data['assets'] as List<dynamic>? ?? [];

        // Parse current version - fix the undefined getter
        final currentVersion = VersionInfo.fullVersionString;
        
        Logging.severe('Current version: $currentVersion, Latest: $latestVersion');

        if (_isNewerVersion(currentVersion, latestVersion)) {
          return UpdateInfo(
            latestVersion: latestVersion,
            currentVersion: currentVersion,
            releaseUrl: releaseUrl,
            publishedAt: publishedAt,
            releaseNotes: releaseNotes,
            assets: assets.map((asset) => ReleaseAsset.fromJson(asset)).toList(),
          );
        }
      } else {
        Logging.severe('Failed to check for updates: ${response.statusCode}');
      }
    } catch (e, stack) {
      Logging.severe('Error checking for updates', e, stack);
    }
    return null;
  }

  static bool _isNewerVersion(String current, String latest) {
    try {
      // Remove 'v' prefix if present and split by dots
      final currentParts = current.replaceFirst('v', '').split('.');
      final latestParts = latest.replaceFirst('v', '').split('.');

      // Pad shorter version with zeros - fix missing braces
      final maxLength = [currentParts.length, latestParts.length].reduce((a, b) => a > b ? a : b);
      while (currentParts.length < maxLength) {
        currentParts.add('0');
      }
      while (latestParts.length < maxLength) {
        latestParts.add('0');
      }

      for (int i = 0; i < maxLength; i++) {
        final currentNum = int.tryParse(currentParts[i]) ?? 0;
        final latestNum = int.tryParse(latestParts[i]) ?? 0;
        
        if (latestNum > currentNum) return true;
        if (latestNum < currentNum) return false;
      }
      return false;
    } catch (e) {
      Logging.severe('Error comparing versions: $e');
      return false;
    }
  }

  static OSInfo detectOS() {
    if (Platform.isWindows) {
      return OSInfo(type: OSType.windows, name: 'Windows');
    } else if (Platform.isMacOS) {
      return OSInfo(type: OSType.macos, name: 'macOS');
    } else if (Platform.isLinux) {
      // Try to detect specific Linux distribution
      try {
        final osRelease = File('/etc/os-release');
        if (osRelease.existsSync()) {
          final content = osRelease.readAsStringSync();
          if (content.contains('fedora') || content.contains('Fedora')) {
            return OSInfo(type: OSType.linux, name: 'Fedora Linux', packageType: 'rpm');
          } else if (content.contains('ubuntu') || content.contains('Ubuntu')) {
            return OSInfo(type: OSType.linux, name: 'Ubuntu Linux', packageType: 'deb');
          } else if (content.contains('debian') || content.contains('Debian')) {
            return OSInfo(type: OSType.linux, name: 'Debian Linux', packageType: 'deb');
          } else if (content.contains('arch') || content.contains('Arch')) {
            return OSInfo(type: OSType.linux, name: 'Arch Linux', packageType: 'pkg');
          } else if (content.contains('opensuse') || content.contains('openSUSE')) {
            return OSInfo(type: OSType.linux, name: 'openSUSE Linux', packageType: 'rpm');
          }
        }
      } catch (e) {
        Logging.severe('Could not detect Linux distribution: $e');
      }
      return OSInfo(type: OSType.linux, name: 'Linux', packageType: 'appimage');
    } else if (Platform.isAndroid) {
      return OSInfo(type: OSType.android, name: 'Android');
    }
    
    return OSInfo(type: OSType.unknown, name: 'Unknown');
  }

  static List<ReleaseAsset> getRecommendedAssets(List<ReleaseAsset> assets, OSInfo osInfo) {
    final recommended = <ReleaseAsset>[];
    
    switch (osInfo.type) {
      case OSType.windows:
        // Prefer installer, then portable
        final installer = assets.where((a) => a.name.toLowerCase().contains('setup') || 
                                           a.name.toLowerCase().contains('installer')).firstOrNull;
        if (installer != null) recommended.add(installer);
        
        final portable = assets.where((a) => a.name.toLowerCase().contains('portable')).firstOrNull;
        if (portable != null) recommended.add(portable);
        break;
        
      case OSType.macos:
        final dmg = assets.where((a) => a.name.toLowerCase().endsWith('.dmg')).firstOrNull;
        if (dmg != null) recommended.add(dmg);
        break;
        
      case OSType.linux:
        // Recommend based on detected package type
        if (osInfo.packageType == 'deb') {
          final deb = assets.where((a) => a.name.toLowerCase().endsWith('.deb')).firstOrNull;
          if (deb != null) recommended.add(deb);
        } else if (osInfo.packageType == 'rpm') {
          final rpm = assets.where((a) => a.name.toLowerCase().endsWith('.rpm')).firstOrNull;
          if (rpm != null) recommended.add(rpm);
        }
        
        // Always include AppImage as universal option
        final appimage = assets.where((a) => a.name.toLowerCase().contains('appimage')).firstOrNull;
        if (appimage != null) recommended.add(appimage);
        
        // Include Flatpak if available
        final flatpak = assets.where((a) => a.name.toLowerCase().contains('flatpak')).firstOrNull;
        if (flatpak != null) recommended.add(flatpak);
        break;
        
      case OSType.android:
        final apk = assets.where((a) => a.name.toLowerCase().endsWith('.apk')).firstOrNull;
        if (apk != null) recommended.add(apk);
        break;
        
      case OSType.unknown:
        // Show all assets
        recommended.addAll(assets);
        break;
    }
    
    return recommended;
  }

  static Future<void> openReleaseDownload(String downloadUrl) async {
    try {
      final uri = Uri.parse(downloadUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      Logging.severe('Error opening download URL: $e');
      throw Exception('Could not open download link');
    }
  }

  static Future<void> openReleasePage(String releaseUrl) async {
    try {
      final uri = Uri.parse(releaseUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      Logging.severe('Error opening release page: $e');
      throw Exception('Could not open release page');
    }
  }
}

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseUrl;
  final DateTime publishedAt;
  final String releaseNotes;
  final List<ReleaseAsset> assets;

  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseUrl,
    required this.publishedAt,
    required this.releaseNotes,
    required this.assets,
  });
}

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;
  final String contentType;

  ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.contentType,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: json['name'] as String,
      downloadUrl: json['browser_download_url'] as String,
      size: json['size'] as int,
      contentType: json['content_type'] as String? ?? 'application/octet-stream',
    );
  }

  String get formattedSize {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

class OSInfo {
  final OSType type;
  final String name;
  final String? packageType;

  OSInfo({
    required this.type,
    required this.name,
    this.packageType,
  });
}

enum OSType {
  windows,
  macos,
  linux,
  android,
  unknown,
}

// Extension to add firstOrNull to Iterable
extension IterableExtension<T> on Iterable<T> {
  T? get firstOrNull {
    return isEmpty ? null : first;
  }
}
