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
    }

    // Default fallback
    return 'lib/icons/bandcamp.svg';
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
