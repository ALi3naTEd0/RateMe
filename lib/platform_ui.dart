import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A utility class that provides platform-specific UI elements like icons and cards
class PlatformUI {
  // ----- PLATFORM ICONS SECTION -----

  /// Get the asset path for a platform icon
  static String _getPlatformIconPath(String platform) {
    final platformLower = platform.toLowerCase();

    if (platformLower.contains('apple') ||
        platformLower.contains('itunes') ||
        platformLower == 'apple music') {
      return 'lib/icons/apple_music.svg';
    } else if (platformLower.contains('spotify')) {
      return 'lib/icons/spotify.svg';
    } else if (platformLower.contains('bandcamp')) {
      return 'lib/icons/bandcamp.svg';
    } else if (platformLower.contains('deezer')) {
      return 'lib/icons/deezer.svg';
    } else if (platformLower.contains('youtube') ||
        platformLower.contains('ytmusic')) {
      return 'lib/icons/youtube_music.svg';
    } else if (platformLower.contains('discogs')) {
      return 'lib/icons/discogs.svg';
    }

    // Default fallback
    return 'lib/icons/bandcamp.svg';
  }

  // Helper method to get the appropriate platform icon
  static IconData getPlatformIcon(Map<String, dynamic> album) {
    final String platform = _getPlatformType(album).toLowerCase();

    switch (platform) {
      case 'spotify':
        return Icons.album;
      case 'itunes':
      case 'apple_music':
        return Icons.album;
      case 'deezer':
        return Icons.album;
      case 'bandcamp':
        return Icons.album;
      case 'discogs':
        return Icons.album;
      default:
        // Instead of defaulting to bandcamp icon, let's use a generic music icon
        return Icons.album;
    }
  }

  // Helper method to get the platform type from an album
  static String _getPlatformType(Map<String, dynamic> album) {
    // First check explicit platform field
    if (album.containsKey('platform') && album['platform'] != null) {
      return album['platform'].toString();
    }

    // Then try to determine from URL
    final url = album['url']?.toString() ?? '';

    if (url.contains('itunes.apple.com') || url.contains('music.apple.com')) {
      return 'itunes';
    } else if (url.contains('spotify.com')) {
      return 'spotify';
    } else if (url.contains('deezer.com')) {
      return 'deezer';
    } else if (url.contains('bandcamp.com')) {
      return 'bandcamp';
    } else if (url.contains('discogs.com')) {
      return 'discogs';
    }

    // For iTunes API results, check for the collectionId/collectionName pattern
    if (album.containsKey('collectionId') &&
        album.containsKey('collectionName') &&
        !album.containsKey('platform')) {
      return 'itunes';
    }

    return 'unknown';
  }

  // Helper method to get platform color
  static Color getPlatformColor(Map<String, dynamic> album) {
    final String platform = _getPlatformType(album).toLowerCase();

    switch (platform) {
      case 'spotify':
        return const Color(0xFF1DB954);
      case 'itunes':
      case 'apple_music':
        return const Color(0xFFFC3C44);
      case 'deezer':
        return const Color(0xFF00C7F2);
      case 'bandcamp':
        return const Color(0xFF1DA0C3);
      case 'discogs':
        return const Color(0xFFFF5500);
      default:
        return Colors.grey.shade700;
    }
  }

  /// Widget that displays an icon for the given platform
  static Widget buildPlatformIcon({
    required String platform,
    double size = 24,
    Color? color,
  }) {
    final String assetPath = _getPlatformIconPath(platform);

    return Builder(
      builder: (context) {
        // Use theme's iconTheme directly for better theme reactivity
        final defaultColor = color ?? Theme.of(context).iconTheme.color;

        return SvgPicture.asset(
          assetPath,
          colorFilter: ColorFilter.mode(defaultColor!, BlendMode.srcIn),
          width: size,
          height: size,
        );
      },
    );
  }

  // ----- ALBUM CARD SECTION -----

  /// Build an album card for displaying in lists
  static Widget buildAlbumCard({
    required Map<String, dynamic> album,
    required VoidCallback onTap,
  }) {
    final platform = album['platform'] ?? 'unknown';
    final artworkUrl = album['artworkUrl100'] ?? '';
    final albumName =
        album['collectionName'] ?? album['name'] ?? 'Unknown Album';
    final artistName =
        album['artistName'] ?? album['artist'] ?? 'Unknown Artist';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              // Album artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: artworkUrl.isNotEmpty
                      ? Image.network(
                          artworkUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color: Colors.grey.shade800,
                            child:
                                const Icon(Icons.album, color: Colors.white54),
                          ),
                        )
                      : Container(
                          color: Colors.grey.shade800,
                          child: const Icon(Icons.album, color: Colors.white54),
                        ),
                ),
              ),

              const SizedBox(width: 12),

              // Album info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      albumName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Platform icon
              buildPlatformIcon(platform: platform, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
