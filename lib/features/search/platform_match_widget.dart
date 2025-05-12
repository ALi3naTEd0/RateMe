import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/album_model.dart';
import '../../core/services/logging.dart';
import '../../ui/widgets/skeleton_loading.dart';
import '../../platforms/platform_service_factory.dart';
import '../../core/services/search_service.dart';
import '../../database/database_helper.dart';

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
  // Track loading state per platform for progressive UI
  final Map<String, bool> _platformLoading = {};
  final Map<String, String?> _platformUrls = {};
  final List<String> _supportedPlatforms = [
    'apple_music',
    'spotify',
    'deezer',
    'discogs',
  ];

  // Create a factory instance to access platform services
  final _platformFactory = PlatformServiceFactory();

  // Platform URL cache with TTL (30 days in milliseconds)
  static final Map<String, Map<String, dynamic>> _platformUrlCache = {};
  static const int _cacheTTL =
      30 * 24 * 60 * 60 * 1000; // 30 days in milliseconds

  // Add this flag to track disposal state
  bool _disposed = false;
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    _initializePlatforms();
    _loadPlatformMatches();
  }

  void _initializePlatforms() {
    // Set all platforms to loading initially
    for (final platform in _supportedPlatforms) {
      _platformLoading[platform] = true;
    }

    // Also handle bandcamp
    _platformLoading['bandcamp'] = true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // Check cache first before loading from database or API
  String? _checkCache(String albumId, String platform) {
    final cacheKey = "${albumId}_$platform";
    final cachedData = _platformUrlCache[cacheKey];

    if (cachedData != null) {
      final timestamp = cachedData['timestamp'] as int;
      final url = cachedData['url'] as String?;

      // Check if cache is still valid (within TTL)
      if (DateTime.now().millisecondsSinceEpoch - timestamp < _cacheTTL) {
        Logging.info('Cache hit for $platform');
        return url;
      } else {
        // Remove expired cache
        _platformUrlCache.remove(cacheKey);
        Logging.info('Cache expired for $platform');
      }
    } else {
      Logging.info('Cache miss for $platform');
    }

    return null;
  }

  // Update cache with new URL
  void _updateCache(String albumId, String platform, String? url) {
    final cacheKey = "${albumId}_$platform";
    _platformUrlCache[cacheKey] = {
      'url': url,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<void> _loadPlatformMatches() async {
    try {
      final albumId = widget.album.id.toString();

      // First check source platform - always guaranteed
      _addSourcePlatform();

      // Make a copy of supported platforms to avoid concurrent modification
      final platformsToProcess = List<String>.from(_supportedPlatforms);

      // Also ensure 'discogs' is in the list of platforms to check
      if (!platformsToProcess.contains('discogs')) {
        platformsToProcess.add('discogs');
        _platformLoading['discogs'] = true;
      }

      // Process each platform independently and progressively update UI
      for (final platform in platformsToProcess) {
        // Skip if this is already the source platform
        if (_platformUrls.containsKey(platform)) {
          _updatePlatformLoadingState(platform, false);
          continue;
        }

        // Make sure we're tracking loading state for this platform
        if (!_platformLoading.containsKey(platform)) {
          _platformLoading[platform] = true;
        }

        // Check memory cache first
        final cachedUrl = _checkCache(albumId, platform);
        if (cachedUrl != null) {
          if (cachedUrl.isNotEmpty) {
            _platformUrls[platform] = cachedUrl;
          }
          _updatePlatformLoadingState(platform, false);
          continue;
        }

        // Try database next
        final dbUrl = await _loadPlatformFromDatabase(albumId, platform);
        if (dbUrl != null) {
          if (dbUrl.isNotEmpty) {
            _platformUrls[platform] = dbUrl;
            _updateCache(albumId, platform, dbUrl);
          }
          _updatePlatformLoadingState(platform, false);
          continue;
        }

        // If not in DB, search for it (in parallel)
        _findMatchForPlatform(albumId, platform);
      }

      // Mark initial loading complete
      if (_isInitialLoading && mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    } catch (e, stack) {
      Logging.severe('Error in platform match loading', e, stack);
      _markAllPlatformsLoaded();
    }
  }

  void _addSourcePlatform() {
    if (widget.album.url.isNotEmpty) {
      // Fix: Normalize platform name to lowercase for consistent comparison
      String currentPlatform = widget.album.platform.toLowerCase();

      // Normalize iTunes to apple_music
      if (currentPlatform == 'itunes') {
        currentPlatform = 'apple_music';
      }

      // For Bandcamp URLs, ensure the platform is set correctly regardless of the stored platform name
      if (widget.album.url.toLowerCase().contains('bandcamp.com') &&
          currentPlatform != 'bandcamp') {
        Logging.severe(
            'Correcting platform to bandcamp for URL: ${widget.album.url}');
        currentPlatform = 'bandcamp';
      }

      _platformUrls[currentPlatform] = widget.album.url;
      _updatePlatformLoadingState(currentPlatform, false);

      // For URL-based platform detection
      String urlDetectedPlatform = _determinePlatformFromUrl(widget.album.url);
      if (urlDetectedPlatform.isNotEmpty &&
          urlDetectedPlatform != currentPlatform) {
        _platformUrls[urlDetectedPlatform] = widget.album.url;
        _updatePlatformLoadingState(urlDetectedPlatform, false);
        Logging.severe(
            'Added additional platform from URL detection: $urlDetectedPlatform');
      }

      // Debug logging for Bandcamp
      if (currentPlatform == 'bandcamp' ||
          widget.album.url.toLowerCase().contains('bandcamp.com')) {
        Logging.severe(
            'Bandcamp album detected: platform=$currentPlatform, URL=${widget.album.url}');
      }

      // Update cache
      _updateCache(
          widget.album.id.toString(), currentPlatform, widget.album.url);
      if (urlDetectedPlatform.isNotEmpty) {
        _updateCache(
            widget.album.id.toString(), urlDetectedPlatform, widget.album.url);
      }
    }
  }

  // Update platform loading state with UI refresh
  void _updatePlatformLoadingState(String platform, bool isLoading) {
    if (!mounted || _disposed) return;

    setState(() {
      _platformLoading[platform] = isLoading;
    });
  }

  // Mark all platforms as loaded (for error cases)
  void _markAllPlatformsLoaded() {
    if (!mounted || _disposed) return;

    setState(() {
      for (final platform in _platformLoading.keys) {
        _platformLoading[platform] = false;
      }
      _isInitialLoading = false;
    });
  }

  // Load a single platform from database
  Future<String?> _loadPlatformFromDatabase(
      String albumId, String platform) async {
    try {
      final db = await DatabaseHelper.instance.database;

      final results = await db.query(
        'platform_matches',
        columns: ['url'],
        where: 'album_id = ? AND platform = ?',
        whereArgs: [albumId, platform],
        limit: 1,
      );

      if (results.isNotEmpty) {
        Logging.info('Database hit for $platform match');
        return results.first['url'] as String?;
      } else {
        Logging.info('No database entry for $platform match');
      }
    } catch (e) {
      Logging.severe('Error loading $platform from database', e);
    }

    return null;
  }

  // Find match for a specific platform asynchronously
  Future<void> _findMatchForPlatform(String albumId, String platform) async {
    try {
      if (_platformFactory.isPlatformSupported(platform)) {
        final service = _platformFactory.getService(platform);

        // Clean artist name for better matching
        String artist = widget.album.artist;
        String cleanedArtist = artist.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '');
        final albumName = widget.album.name;

        // Log search attempt
        Logging.info('Searching for $albumName by $cleanedArtist on $platform');

        // Search for the platform
        final url = await service.findAlbumUrl(cleanedArtist, albumName);

        // Log search result
        if (url != null) {
          Logging.info('Found match on $platform: $url');
        } else {
          Logging.info('No match found on $platform');
        }

        // Verify the match before storing
        bool isValidMatch = false;
        if (url != null) {
          final albumDetails = await service.fetchAlbumDetails(url);

          if (albumDetails != null) {
            final matchScore = SearchService.calculateMatchScore(
                cleanedArtist,
                albumName,
                albumDetails['artistName'] ?? '',
                albumDetails['collectionName'] ?? '');

            // Use different thresholds for different platforms
            double threshold = platform == 'deezer' ? 0.7 : 0.5;
            isValidMatch = matchScore >= threshold;

            // Log match quality
            Logging.info(
                '$platform match quality: $matchScore (threshold: $threshold)');
          }
        }

        if (!mounted || _disposed) return;

        setState(() {
          if (url != null && isValidMatch) {
            _platformUrls[platform] = url;
            _updateCache(albumId, platform, url);
            _savePlatformMatch(albumId, platform, url);
            Logging.info('Saved valid $platform match');
          } else if (url != null) {
            Logging.info('Rejected low-quality $platform match');
          }
          _platformLoading[platform] = false;
        });
      } else {
        _updatePlatformLoadingState(platform, false);
      }
    } catch (e) {
      Logging.severe('Error finding match for $platform', e);
      _updatePlatformLoadingState(platform, false);
    }
  }

  // Save a single platform match to database
  Future<void> _savePlatformMatch(
      String albumId, String platform, String url) async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Ensure table exists
      await db.execute('''
        CREATE TABLE IF NOT EXISTS platform_matches (
          album_id TEXT,
          platform TEXT,
          url TEXT,
          verified INTEGER DEFAULT 0,
          timestamp TEXT,
          PRIMARY KEY (album_id, platform)
        )
      ''');

      await db.insert(
        'platform_matches',
        {
          'album_id': albumId,
          'platform': platform,
          'url': url,
          'verified': 1,
          'timestamp': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      Logging.severe('Error saving $platform match to database', e);
    }
  }

  /// Determine which platform a URL belongs to
  String _determinePlatformFromUrl(String url) {
    final lowerUrl = url.toLowerCase();

    // Improved Bandcamp URL detection
    if (lowerUrl.contains('bandcamp.com')) {
      Logging.severe('URL matched as Bandcamp: $url');
      return 'bandcamp';
    } else if (lowerUrl.contains('spotify.com') ||
        lowerUrl.contains('open.spotify')) {
      return 'spotify';
    } else if (lowerUrl.contains('music.apple.com') ||
        lowerUrl.contains('itunes.apple.com')) {
      return 'apple_music';
    } else if (lowerUrl.contains('deezer.com')) {
      return 'deezer';
    } else if (lowerUrl.contains('discogs.com')) {
      return 'discogs';
    }

    return '';
  }

  @override
  Widget build(BuildContext context) {
    // Get list of platforms that have valid URLs
    final availablePlatforms = _platformUrls.entries
        .where((entry) => entry.value != null && entry.value!.isNotEmpty)
        .map((entry) => entry.key)
        .toList();

    // Create a copy to avoid concurrent modification
    final supportedPlatformsCopy = List<String>.from(_supportedPlatforms);

    // Make sure 'bandcamp' is included when the URL contains 'bandcamp.com'
    if (widget.album.url.toLowerCase().contains('bandcamp.com') &&
        !availablePlatforms.contains('bandcamp')) {
      availablePlatforms.add('bandcamp');
      _platformUrls['bandcamp'] = widget.album.url;
      Logging.severe(
          'Added missing bandcamp to available platforms explicitly');
    }

    // Don't show anything if in initial loading state and no platforms are available yet
    if (_isInitialLoading && availablePlatforms.isEmpty) {
      return _buildSkeletonButtons();
    }

    // Remove iTunes if we also have Apple Music (they're the same service)
    if (availablePlatforms.contains('apple_music') &&
        availablePlatforms.contains('itunes')) {
      availablePlatforms.remove('itunes');
    }

    // Add all standard platforms to supported list if not already there
    for (final platform in [
      'bandcamp',
      'discogs',
      'spotify',
      'deezer',
      'apple_music'
    ]) {
      if (!supportedPlatformsCopy.contains(platform)) {
        supportedPlatformsCopy.add(platform);
        Logging.severe('Added $platform to supported platforms list');
      }
    }

    // Sort platforms in the correct order (Apple Music first, as it was originally)
    final platformOrder = [
      'apple_music',
      'spotify',
      'deezer',
      'discogs',
      'bandcamp'
    ];
    final sortedPlatforms = <String>[];

    // Add platforms in specified order
    for (final platform in platformOrder) {
      if (availablePlatforms.contains(platform)) {
        sortedPlatforms.add(platform);
      }
    }

    // Add any remaining platforms
    for (final platform in availablePlatforms) {
      if (!sortedPlatforms.contains(platform)) {
        sortedPlatforms.add(platform);
      }
    }

    // Update the _supportedPlatforms list safely
    if (mounted) {
      setState(() {
        // Create a new list with all needed platforms
        _supportedPlatforms.clear();
        _supportedPlatforms.addAll(supportedPlatformsCopy);
      });
    }

    // Log available platforms for debugging
    Logging.severe('Available platforms: ${availablePlatforms.join(", ")}');
    Logging.severe('Supported platforms: ${supportedPlatformsCopy.join(", ")}');
    Logging.severe('Sorted platforms: ${sortedPlatforms.join(", ")}');

    // Build UI with platforms
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Show all available platforms in our sorted order
              ...sortedPlatforms.map((platform) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _buildPlatformButton(platform),
                );
              }),
            ],
          ),

          // Refresh button
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: InkWell(
              onTap: _isInitialLoading ? null : _refreshPlatformMatches,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade800.withAlpha(128)
                      : Colors.grey.shade200.withAlpha(179),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.refresh,
                      size: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Refresh matches',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.shade300
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build skeleton loading buttons while waiting for platform matches
  Widget _buildSkeletonButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < _supportedPlatforms.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          PlatformButtonSkeleton(size: widget.buttonSize),
        ],
      ],
    );
  }

  Widget _buildPlatformButton(String platform) {
    // Get URL for this platform
    final platformUrl = _platformUrls[platform];
    final bool hasMatch = platformUrl != null && platformUrl.isNotEmpty;

    // FIXED approach for platform comparison
    final currentPlatform = widget.album.platform.toLowerCase().trim();
    final normalizedPlatform = platform.toLowerCase().trim();

    // Create debug info for this specific platform
    Logging.severe(
        'Building platform button: platform=$platform, currentPlatform=${widget.album.platform}');

    // Much simpler isSelected logic that handles all cases
    bool isSelected = false;

    // Case 1: Direct platform name match
    if (normalizedPlatform == currentPlatform) {
      isSelected = true;
      Logging.severe('Platform selected due to direct name match: $platform');
    }
    // Case 2: Bandcamp special case with URL check
    else if (normalizedPlatform == 'bandcamp' &&
        widget.album.url.toLowerCase().contains('bandcamp.com')) {
      isSelected = true;
      Logging.severe('Bandcamp selected due to URL match: ${widget.album.url}');
    }
    // Case 3: iTunes = apple_music normalization
    else if ((normalizedPlatform == 'apple_music' &&
            currentPlatform == 'itunes') ||
        (normalizedPlatform == 'itunes' && currentPlatform == 'apple_music')) {
      isSelected = true;
      Logging.severe('Apple Music selected due to iTunes normalization');
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
    final iconColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : (isDarkTheme ? Colors.white : Colors.black);

    // Log when Bandcamp is selected
    if (normalizedPlatform == 'bandcamp' && isSelected) {
      Logging.severe(
          'Bandcamp icon IS selected! Using primary color: ${Theme.of(context).colorScheme.primary}');
    }

    // Create button content
    final buttonContent = SizedBox(
      width: widget.buttonSize,
      height: widget.buttonSize,
      child: iconPath.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.all(4.0),
              child: SvgPicture.asset(
                iconPath,
                height: widget.buttonSize - 8,
                width: widget.buttonSize - 8,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
            )
          : Icon(
              Icons.music_note,
              size: widget.buttonSize - 8,
              color: iconColor,
            ),
    );

    return Opacity(
      opacity: hasMatch ? 1.0 : 0.5,
      child: Tooltip(
        message: hasMatch
            ? (isSelected
                ? _getPlatformName(platform)
                : _getPlatformName(platform))
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

    const double menuWidth = 200;
    final double centerX = position.dx + (buttonSize.width / 2);
    final double leftPosition = centerX - (menuWidth / 2);
    final RelativeRect rect = RelativeRect.fromLTRB(
      leftPosition,
      position.dy + buttonSize.height + 5,
      MediaQuery.of(context).size.width - leftPosition - menuWidth,
      0,
    );

    showMenu<String>(
      context: context,
      position: rect,
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          height: 26,
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
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.open_in_new, size: 26),
              const SizedBox(width: 6),
              Text(_getPlatformName(platform)),
            ],
          ),
        ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${_getPlatformName(platform)} URL copied to clipboard'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      Logging.severe('Error copying URL to clipboard', e);
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
    } catch (e) {
      Logging.severe('Error sharing URL', e);
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
    // Fix: Ensure consistent normalization for platform names
    switch (platform.toLowerCase()) {
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
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      Logging.severe('Error opening URL: $url', e);
    }
  }

  // Refresh platform matches method - optimized version
  Future<void> _refreshPlatformMatches() async {
    // Reset to loading state
    setState(() {
      _isInitialLoading = true;
      for (final platform in _supportedPlatforms) {
        _platformLoading[platform] = true;
      }
      _platformUrls.clear();
    });

    try {
      // Clear database entries
      final albumId = widget.album.id.toString();
      final db = await DatabaseHelper.instance.database;
      await db.delete(
        'platform_matches',
        where: 'album_id = ?',
        whereArgs: [albumId],
      );

      // Clear memory cache
      for (final platform in _supportedPlatforms) {
        final cacheKey = "${albumId}_$platform";
        _platformUrlCache.remove(cacheKey);
      }

      // Reload everything from scratch
      _addSourcePlatform();

      // Process each platform in parallel
      await Future.wait(_supportedPlatforms.map((platform) async {
        // Skip if this is already the source platform
        if (_platformUrls.containsKey(platform)) {
          _updatePlatformLoadingState(platform, false);
          return;
        }

        // Search for it
        await _findMatchForPlatform(albumId, platform);
      }));

      // Show feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Platform matches refreshed'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      Logging.severe('Error refreshing platform matches', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing platform matches: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      _markAllPlatformsLoaded();
    }
  }
}

// Define the extension outside the class
extension StringExtension on String {
  String capitalize() {
    return isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
  }
}
