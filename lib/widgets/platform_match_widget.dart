import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for Clipboard
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../album_model.dart';
import '../logging.dart';
import '../widgets/skeleton_loading.dart';
import '../platforms/platform_service_factory.dart';
import '../search_service.dart'; // Add import for SearchService

/// Widget that displays buttons to open an album in various streaming platforms
class PlatformMatchWidget extends StatefulWidget {
  final Album album;
  final bool showTitle;
  final double buttonSize;

  const PlatformMatchWidget({
    super.key,
    required this.album,
    this.showTitle = true,
    this.buttonSize = 40.0,
  });

  @override
  State<PlatformMatchWidget> createState() => _PlatformMatchWidgetState();
}

class _PlatformMatchWidgetState extends State<PlatformMatchWidget> {
  bool _isLoading = false;
  final Map<String, String?> _platformUrls = {};
  final List<String> _supportedPlatforms = [
    'spotify',
    'apple_music',
    'deezer',
    'discogs', // Add Discogs to supported platforms
  ];

  // Create a factory instance to access platform services
  final _platformFactory = PlatformServiceFactory();

  @override
  void initState() {
    super.initState();
    _findMatchingAlbums();
  }

  Future<void> _findMatchingAlbums() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // Initialize with existing URL if album is from one of our platforms
      final currentPlatform = widget.album.platform.toLowerCase();

      // Check if this is a bandcamp album
      final isBandcamp = currentPlatform == 'bandcamp' ||
          widget.album.url.toLowerCase().contains('bandcamp.com');

      if (isBandcamp) {
        // For bandcamp albums, add the original URL as a bandcamp platform URL
        _platformUrls['bandcamp'] = widget.album.url;
        Logging.severe('Added bandcamp source URL: ${widget.album.url}');
      } else if (_supportedPlatforms.contains(currentPlatform)) {
        _platformUrls[currentPlatform] = widget.album.url;
      }

      // Always ensure the source platform URL is available regardless of platform
      if (widget.album.url.isNotEmpty) {
        // Figure out which platform the album's URL belongs to
        String sourcePlatform = _determinePlatformFromUrl(widget.album.url);
        if (sourcePlatform.isNotEmpty) {
          _platformUrls[sourcePlatform] = widget.album.url;
          Logging.severe(
              'Added source platform URL: $sourcePlatform -> ${widget.album.url}');
        }
      }

      // Always search for additional platforms, even for Bandcamp albums
      // Create search query from album and artist
      final artist = widget.album.artist.trim();
      final albumName = widget.album.name.trim();
      Logging.severe('Searching for album matches: $artist - $albumName');

      // Search for the album on each platform we don't already have
      await Future.wait(_supportedPlatforms
          .where((platform) => !_platformUrls.containsKey(platform))
          .map((platform) async {
        if (_platformFactory.isPlatformSupported(platform)) {
          final service = _platformFactory.getService(platform);
          final url = await service.findAlbumUrl(artist, albumName);
          if (url != null) {
            _platformUrls[platform] = url;
          }
        }
      }));

      // Fix for Discogs URLs: Ensure they're website URLs, not API URLs
      if (_platformUrls.containsKey('discogs') &&
          _platformUrls['discogs'] != null) {
        final discogsUrl = _platformUrls['discogs']!;

        // Check if it's an API URL and convert it
        if (discogsUrl.contains('api.discogs.com') ||
            discogsUrl.contains('/api/')) {
          // Extract ID from URL - assuming format like https://api.discogs.com/masters/2243191
          final regExp = RegExp(r'/(masters|releases)/(\d+)');
          final match = regExp.firstMatch(discogsUrl);

          if (match != null && match.groupCount >= 2) {
            final type = match.group(1); // masters or releases
            final id = match.group(2); // the numeric ID

            if (type != null && id != null) {
              // Convert to website URL
              final correctedUrl = 'https://www.discogs.com/$type/$id';
              Logging.severe(
                  'Corrected Discogs API URL to website URL: $correctedUrl');
              _platformUrls['discogs'] = correctedUrl;
            }
          }
        }
      }

      // Verify matches for accuracy - remove potentially incorrect matches
      await _verifyMatches();
    } catch (e, stack) {
      Logging.severe('Error finding matching albums', e, stack);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Verify that matches are accurate by checking if they meet minimum match criteria
  Future<void> _verifyMatches() async {
    Logging.severe('Verifying platform matches for accuracy');

    final List<String> platformsToVerify = [..._supportedPlatforms, 'bandcamp'];
    final String artistName = widget.album.artist;
    final String albumName = widget.album.name;

    // Check if the current platform is iTunes, and if so, make sure apple_music is also marked as current
    final String currentPlatform = widget.album.platform.toLowerCase();
    final bool isITunesOrAppleMusic =
        currentPlatform == 'itunes' || currentPlatform == 'apple_music';

    // Handle album names with EP/Single designations
    String cleanedAlbumName = albumName;
    if (albumName.toLowerCase().contains("ep") ||
        albumName.toLowerCase().contains("single")) {
      cleanedAlbumName = SearchService.removeAlbumSuffixes(albumName);
      Logging.severe(
          'Using cleaned album name for matching: $cleanedAlbumName');
    }

    // Track platforms to remove due to failed verification
    final List<String> platformsToRemove = [];

    for (final platform in platformsToVerify) {
      if (_platformUrls.containsKey(platform)) {
        final url = _platformUrls[platform];

        if (url == null || url.isEmpty) {
          platformsToRemove.add(platform);
          continue;
        }

        // Skip verification for source platform
        if ((isITunesOrAppleMusic && platform == 'apple_music') ||
            (platform == currentPlatform)) {
          Logging.severe(
              'Skipping verification for $platform (source platform)');
          continue;
        }

        // Special case for Spotify with EP/Single in the source album name
        if (platform == 'spotify' &&
            (albumName.toLowerCase().contains("ep") ||
                albumName.toLowerCase().contains("single"))) {
          // Be more lenient with Spotify EP/Single matching
          Logging.severe(
              'Using special handling for Spotify EP/Single matching');

          try {
            if (_platformFactory.isPlatformSupported(platform)) {
              final service = _platformFactory.getService(platform);
              final albumDetails = await service.fetchAlbumDetails(url);

              if (albumDetails != null) {
                // For Spotify EP/Singles, do a special check
                String spotifyAlbumName = albumDetails['collectionName'] ?? '';
                String spotifyArtistName = albumDetails['artistName'] ?? '';

                // Check artist match directly
                bool artistMatches =
                    _normalizeForComparison(spotifyArtistName) ==
                        _normalizeForComparison(artistName);

                // Check if the album names match after cleaning
                bool albumsMatch = _normalizeForComparison(spotifyAlbumName) ==
                    _normalizeForComparison(cleanedAlbumName);

                if (artistMatches && albumsMatch) {
                  // Direct match after cleanup, keep this URL
                  Logging.severe(
                      'Direct match for Spotify after cleanup: $spotifyArtistName - $spotifyAlbumName');
                  continue;
                }

                // Standard scoring as fallback
                double matchScore = SearchService.calculateMatchScore(
                    artistName,
                    cleanedAlbumName,
                    spotifyArtistName,
                    spotifyAlbumName);

                // Lowered threshold just for Spotify EP/Single matches
                const double threshold = 0.45;

                Logging.severe(
                    'Spotify EP/Single match score: $matchScore (threshold: $threshold)');

                if (matchScore >= threshold) {
                  // Good enough match for Spotify with EP/Single
                  continue;
                }
              }
            }

            // If we get here, the Spotify match failed verification
            Logging.severe('Removing Spotify match as validation failed: $url');
            platformsToRemove.add(platform);
          } catch (e) {
            Logging.severe('Error in special Spotify verification: $e');
          }

          // Skip regular verification for Spotify in this case
          continue;
        }

        // Normal verification for other platforms and non-EP/Single Spotify matches
        if (url.contains('/search?') || url.contains('/search/')) {
          Logging.severe(
              '$platform URL is just a search URL, needs verification: $url');

          // For search URLs, we need stricter verification
          bool isValidMatch = false;

          try {
            if (_platformFactory.isPlatformSupported(platform)) {
              final service = _platformFactory.getService(platform);

              // Get album details if possible to compare accurately
              final albumDetails = await service.fetchAlbumDetails(url);

              if (albumDetails != null) {
                // Use the improved match scoring algorithm from SearchService
                final matchScore = SearchService.calculateMatchScore(
                    artistName,
                    cleanedAlbumName,
                    albumDetails['artistName'] ?? '',
                    albumDetails['collectionName'] ?? '');

                // All platforms share the same threshold for consistency
                const double threshold = 0.7;
                isValidMatch = matchScore >= threshold;
                Logging.severe(
                    'Match score for $platform: $matchScore (threshold: $threshold)');
              } else {
                // Fall back to basic verification if detailed info isn't available
                isValidMatch = await service.verifyAlbumExists(
                    artistName, cleanedAlbumName);
              }
            }
          } catch (e) {
            Logging.severe('Error verifying with platform service: $e');
          }

          if (!isValidMatch) {
            Logging.severe(
                'Removing $platform match as validation failed: $url');
            platformsToRemove.add(platform);
          }
        } else {
          // For direct URLs, attempt to fetch details and verify match quality
          try {
            if (_platformFactory.isPlatformSupported(platform)) {
              final service = _platformFactory.getService(platform);
              final albumDetails = await service.fetchAlbumDetails(url);

              if (albumDetails != null) {
                // Use the improved match scoring algorithm
                final matchScore = SearchService.calculateMatchScore(
                    artistName,
                    cleanedAlbumName,
                    albumDetails['artistName'] ?? '',
                    albumDetails['collectionName'] ?? '');

                // Log the match score
                Logging.severe(
                    'Direct URL match score for $platform: $matchScore');

                // Use a consistent threshold across all platforms
                const double threshold = 0.5;

                if (matchScore < threshold) {
                  Logging.severe(
                      'Removing $platform match due to low match score: $matchScore (threshold: $threshold)');
                  platformsToRemove.add(platform);
                }
              }
            }
          } catch (e) {
            Logging.severe('Error verifying direct URL match: $e');
          }
        }
      }
    }

    // Remove invalid platforms
    for (final platform in platformsToRemove) {
      _platformUrls.remove(platform);
    }

    Logging.severe(
        'After verification, have ${_platformUrls.length} valid platform matches: ${_platformUrls.keys.join(', ')}');
  }

  // Helper method to normalize strings for direct comparison
  String _normalizeForComparison(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove special chars
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  /// Determine which platform a URL belongs to
  String _determinePlatformFromUrl(String url) {
    final lowerUrl = url.toLowerCase();
    String platform = '';

    if (lowerUrl.contains('spotify.com') || lowerUrl.contains('open.spotify')) {
      platform = 'spotify';
    } else if (lowerUrl.contains('music.apple.com') ||
        lowerUrl.contains('itunes.apple.com')) {
      platform = 'apple_music'; // Always return 'apple_music' for consistency
    } else if (lowerUrl.contains('deezer.com')) {
      platform = 'deezer';
    } else if (lowerUrl.contains('bandcamp.com')) {
      platform = 'bandcamp';
    } else if (lowerUrl.contains('discogs.com')) {
      platform = 'discogs';
    }

    if (platform.isNotEmpty) {
      Logging.severe('Detected platform from URL: $platform for URL: $url');
    }

    return platform;
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything if we have no matches
    if (_isLoading) {
      return _buildSkeletonButtons();
    }

    // Get list of platforms that have valid URLs
    final availablePlatforms = _platformUrls.entries
        .where((entry) => entry.value != null && entry.value!.isNotEmpty)
        .map((entry) => entry.key)
        .toList();

    // Don't show anything if no platform links are available
    if (availablePlatforms.isEmpty) {
      return const SizedBox.shrink();
    }

    // Fix the order of platforms
    // Order: apple_music, spotify, deezer, bandcamp, discogs
    final sortedPlatforms = <String>[];

    // First add platforms in our desired order
    final platformOrder = [
      'apple_music',
      'spotify',
      'deezer',
      'discogs',
      'bandcamp' // moved to end
    ];
    for (final platform in platformOrder) {
      if (availablePlatforms.contains(platform)) {
        sortedPlatforms.add(platform);
      }
    }

    // Then add any remaining platforms
    for (final platform in availablePlatforms) {
      if (!sortedPlatforms.contains(platform)) {
        sortedPlatforms.add(platform);
      }
    }

    // Debug the order
    Logging.severe('Platform order: ${sortedPlatforms.join(', ')}');

    // Only hide the widget if the only match is the current platform AND it's not bandcamp
    // This allows bandcamp links to always show, but hides redundant platform links
    if (sortedPlatforms.length == 1 &&
        sortedPlatforms.first == widget.album.platform.toLowerCase() &&
        sortedPlatforms.first != 'bandcamp') {
      return const SizedBox.shrink();
    }

    return Padding(
      // Reduce padding to make the entire widget more compact vertically
      padding: const EdgeInsets.symmetric(vertical: 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: sortedPlatforms.map((platform) {
          final button = _buildPlatformButton(platform);
          // Reduce spacers between buttons even further
          return sortedPlatforms.indexOf(platform) < sortedPlatforms.length - 1
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    button,
                    const SizedBox(width: 6),
                  ],
                )
              : button;
        }).toList(),
      ),
    );
  }

  /// Build skeleton loading buttons while waiting for platform matches
  Widget _buildSkeletonButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildSkeletonButton(),
        const SizedBox(width: 16),
        _buildSkeletonButton(),
        const SizedBox(width: 16),
        _buildSkeletonButton(),
      ],
    );
  }

  /// Build an individual skeleton button
  Widget _buildSkeletonButton() {
    return SkeletonLoading(
      width: widget.buttonSize,
      height: widget.buttonSize,
      borderRadius: widget.buttonSize / 2,
    );
  }

  Widget _buildPlatformButton(String platform) {
    final bool hasMatch =
        _platformUrls.containsKey(platform) && _platformUrls[platform] != null;

    // Check if this is the current platform of the album
    // Fix iTunes/Apple Music platform comparison
    bool isSelected = false;

    final String currentPlatform = widget.album.platform.toLowerCase();

    if (platform == 'apple_music' &&
        (currentPlatform == 'itunes' || currentPlatform == 'apple_music')) {
      isSelected = true;
    } else if (platform == currentPlatform) {
      isSelected = true;
    }

    // Debug log to see what URLs we're using
    if (hasMatch) {
      Logging.severe(
          'Platform $platform URL: ${_platformUrls[platform]}, isSelected: $isSelected');
    }

    // Use SVG icons for better quality
    String iconPath;
    switch (platform) {
      case 'spotify':
        iconPath = 'lib/icons/spotify.svg';
        break;
      case 'apple_music':
        iconPath = 'lib/icons/apple_music.svg';
        break;
      case 'deezer':
        iconPath = 'lib/icons/deezer.svg';
        break;
      case 'bandcamp':
        iconPath = 'lib/icons/bandcamp.svg';
        break;
      case 'discogs':
        iconPath = 'lib/icons/discogs.svg';
        break;
      default:
        iconPath = '';
    }

    // Determine icon color based on theme and selection state
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    // Use primary color if selected, otherwise use default icon color
    final iconColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : (isDarkTheme ? Colors.white : Colors.black);

    // Create button content
    final buttonContent = SizedBox(
      width: widget.buttonSize,
      height: widget.buttonSize,
      child: iconPath.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.all(4.0), // Reduced from 8.0 to 4.0,
              child: SvgPicture.asset(
                iconPath,
                height: widget.buttonSize - 8, // Increased from 16 to 8
                width: widget.buttonSize - 8, // Increased from 16 to 8
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
            )
          : Icon(
              Icons.music_note,
              size: widget.buttonSize - 8, // Increased from 16 to 8
              color: iconColor,
            ),
    );

    // Add context menu for desktop platforms (right click)
    // and support long press for mobile platforms
    return Opacity(
      opacity: hasMatch ? 1.0 : 0.5,
      child: Tooltip(
        message: hasMatch
            ? (isSelected
                ? 'Current platform: ${_getPlatformName(platform)}'
                : 'Open in ${_getPlatformName(platform)}')
            : 'No match found in ${_getPlatformName(platform)}',
        child: GestureDetector(
          onLongPress: hasMatch
              ? () => _showContextMenu(platform, _platformUrls[platform]!)
              : null,
          child: InkWell(
            onTap: hasMatch ? () => _openUrl(_platformUrls[platform]!) : null,
            borderRadius: BorderRadius.circular(widget.buttonSize / 2),
            onSecondaryTap: hasMatch
                ? () => _showContextMenu(platform, _platformUrls[platform]!)
                : null,
            child: buttonContent,
          ),
        ),
      ),
    );
  }

  // Show context menu for mobile platforms via long press
  void _showContextMenu(String platform, String url) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset.zero);
    final Size buttonSize = button.size;

    // Position menu below the button and centered horizontally
    const double menuWidth = 200; // Estimated menu width
    final double centerX = position.dx + (buttonSize.width / 2);
    final double leftPosition = centerX - (menuWidth / 2);

    final RelativeRect rect = RelativeRect.fromLTRB(
      leftPosition, // LEFT: centered horizontally
      position.dy + buttonSize.height + 5, // TOP: just below the button
      MediaQuery.of(context).size.width - leftPosition - menuWidth, // RIGHT
      0, // BOTTOM: not constrained
    );

    showMenu<String>(
      context: context,
      position: rect,
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          height: 26, // Set a smaller height for more compact appearance
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.copy, size: 26),
              const SizedBox(width: 6),
              Text('Copy ${_getPlatformName(platform)} URL'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'open',
          height: 26, // Set a smaller height for more compact appearance
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.open_in_new, size: 26),
              const SizedBox(width: 6),
              Text('Open in ${_getPlatformName(platform)}'),
            ],
          ),
        ),
        // Add Share option
        PopupMenuItem<String>(
          value: 'share',
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.share, size: 26),
              const SizedBox(width: 6),
              Text('Share ${_getPlatformName(platform)} Link'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'copy') {
        _copyUrlToClipboard(platform, url);
      } else if (value == 'open') {
        _openUrl(url);
      } else if (value == 'share') {
        _shareUrl(platform, url);
      }
    });
  }

  // Copy URL to clipboard and show feedback
  void _copyUrlToClipboard(String platform, String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      // Show feedback using a snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${_getPlatformName(platform)} URL copied to clipboard'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      Logging.severe('Copied URL to clipboard: $url');
    } catch (e, stack) {
      Logging.severe('Error copying URL to clipboard', e, stack);
    }
  }

  // Add new method to handle sharing
  void _shareUrl(String platform, String url) async {
    try {
      // For desktop platforms, copy to clipboard and show a message
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${_getPlatformName(platform)} URL copied to clipboard for sharing'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // For mobile platforms, use the share plugin
        Share.share(
          'Check out this album on ${_getPlatformName(platform)}: $url',
          subject: 'Album link from RateMe',
        );
      }
      Logging.severe('Shared URL: $url');
    } catch (e, stack) {
      Logging.severe('Error sharing URL', e, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _getPlatformName(String platform) {
    switch (platform) {
      case 'spotify':
        return 'Spotify';
      case 'apple_music':
        return 'Apple Music';
      case 'deezer':
        return 'Deezer';
      case 'bandcamp':
        return 'Bandcamp';
      case 'discogs':
        return 'Discogs';
      default:
        return platform.split('_').map((s) => s.capitalize()).join(' ');
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      // Log the URL we're trying to open
      Logging.severe('Opening URL: $url');
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, stack) {
      Logging.severe('Error opening URL: $url', e, stack);
    }
  }
}

// Define the extension outside the class
extension StringExtension on String {
  String capitalize() {
    return isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
  }
}
