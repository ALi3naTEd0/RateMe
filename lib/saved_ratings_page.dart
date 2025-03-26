import 'package:flutter/material.dart';
import 'dart:convert'; // Add this import for json
import 'user_data.dart';
import 'saved_album_page.dart';
import 'logging.dart';

class SavedRatingsPage extends StatefulWidget {
  const SavedRatingsPage({super.key});

  @override
  State<SavedRatingsPage> createState() => _SavedRatingsPageState();
}

class _SavedRatingsPageState extends State<SavedRatingsPage> {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  List<Map<String, dynamic>> albums = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    try {
      final savedAlbums = await UserData.getSavedAlbums();
      List<Map<String, dynamic>> loadedAlbums = [];

      Logging.severe('Loading ${savedAlbums.length} saved albums');

      for (var album in savedAlbums) {
        try {
          // Log the raw data to help with debugging
          Logging.severe('Processing album: ${json.encode({
                'id': album['id'] ?? album['collectionId'],
                'name': album['name'] ?? album['collectionName'],
              })}');

          // Extract both ID formats to ensure we get something
          final albumId = album['id'] ?? album['collectionId'];
          if (albumId == null) {
            Logging.severe('Album has no ID, skipping');
            continue;
          }

          // Normalize album to consistent format
          final albumMap = {
            'id': albumId,
            'collectionId': albumId,
            'name': album['name'] ?? album['collectionName'] ?? 'Unknown Album',
            'collectionName':
                album['name'] ?? album['collectionName'] ?? 'Unknown Album',
            'artist':
                album['artist'] ?? album['artistName'] ?? 'Unknown Artist',
            'artistName':
                album['artist'] ?? album['artistName'] ?? 'Unknown Artist',
            'artworkUrl': album['artworkUrl'] ?? album['artworkUrl100'] ?? '',
            'artworkUrl100':
                album['artworkUrl'] ?? album['artworkUrl100'] ?? '',
            'platform': album['platform'] ?? 'unknown',
            'url': album['url'] ?? '',
            'tracks': album['tracks'] ?? [],
            'averageRating': await _calculateAlbumRating(albumId),
          };

          Logging.severe('Added album to display list: ${albumMap['name']}');
          loadedAlbums.add(albumMap);
        } catch (e, stack) {
          Logging.severe('Error processing album', e, stack);
          continue;
        }
      }

      Logging.severe('Loaded ${loadedAlbums.length} albums for display');

      if (mounted) {
        setState(() {
          albums = loadedAlbums;
          isLoading = false;
        });
      }
    } catch (e, stack) {
      Logging.severe('Error loading albums in saved_ratings_page', e, stack);
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  /// Calculate average rating for an album
  Future<double> _calculateAlbumRating(dynamic albumId) async {
    try {
      // Handle both string and int IDs consistently
      final normalizedId = albumId.toString();
      Logging.severe('Calculating rating for album ID: $normalizedId');

      // Get ratings from UserData
      final List<Map<String, dynamic>> savedRatings =
          await UserData.getSavedAlbumRatings(normalizedId);

      if (savedRatings.isEmpty) {
        Logging.severe('No ratings found for album ID: $normalizedId');
        return 0.0;
      }

      Logging.severe(
          'Found ${savedRatings.length} ratings for album $normalizedId');

      // Filter non-zero ratings
      var validRatings = savedRatings
          .where((r) => r['rating'] != null && r['rating'] > 0)
          .map((r) => r['rating'].toDouble())
          .toList();

      if (validRatings.isEmpty) {
        Logging.severe('No valid ratings found for album ID: $normalizedId');
        return 0.0;
      }

      // Calculate average
      double total = validRatings.reduce((a, b) => a + b);
      double average = total / validRatings.length;

      Logging.severe(
          'Album $normalizedId average rating: $average from ${validRatings.length} tracks');

      return double.parse(average.toStringAsFixed(2));
    } catch (e, stack) {
      Logging.severe(
          'Error calculating album rating for ID: $albumId', e, stack);
      return 0.0;
    }
  }

  void _deleteAlbum(int index) async {
    // Add confirmation dialog
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final album = albums[index];
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Are you sure you want to delete this album?'),
              const SizedBox(height: 16),
              Text(
                album['artistName'] ?? 'Unknown Artist',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(album['collectionName'] ?? 'Unknown Album'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    // Only delete if user confirmed
    if (result == true) {
      await UserData.deleteAlbum(albums[index]);
      if (mounted) {
        setState(() {
          albums.removeAt(index);
        });
      }
      await UserData.saveAlbumOrder(albums
          .map<String>((album) => album['collectionId'].toString())
          .toList());
    }
  }

  void _openSavedAlbumDetails(int index) {
    final album = albums[index];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SavedAlbumPage(
          album: album,
          isBandcamp:
              album['url']?.toString().contains('bandcamp.com') ?? false,
        ),
      ),
    ).then((_) => _loadAlbums()); // Reload when returning
  }

  Widget _buildAlbumActions(int index) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          onPressed: () => _deleteAlbum(index),
        ),
        const Icon(Icons.drag_handle),
      ],
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final album = albums.removeAt(oldIndex);
      albums.insert(newIndex, album);
    });

    List<String> albumIds = albums
        .map<String>(
            (album) => (album['id'] ?? album['collectionId']).toString())
        .toList();
    UserData.saveAlbumOrder(albumIds);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    // Calculate page width consistently with main page (85% of screen width)
    final pageWidth = MediaQuery.of(context).size.width * 0.85;
    final horizontalPadding =
        (MediaQuery.of(context).size.width - pageWidth) / 2;

    return Scaffold(
      key: scaffoldMessengerKey,
      appBar: AppBar(
        centerTitle: false,
        automaticallyImplyLeading: false, // Disable default back button
        title: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                padding: EdgeInsets.zero, // Remove padding from icon button
                visualDensity: VisualDensity.compact, // Make it more compact
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              const Text('Saved Ratings'),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: horizontalPadding),
            child: IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.settings),
              onPressed: () => showMenu(
                context: context,
                position: const RelativeRect.fromLTRB(
                    100, 50, 0, 0), // Back to original position
                items: const [
                  PopupMenuItem<String>(
                    value: 'import',
                    child: Row(
                      children: [
                        Icon(Icons.file_download),
                        SizedBox(width: 8),
                        Text('Import Data'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(Icons.file_upload),
                        SizedBox(width: 8),
                        Text('Export Data'),
                      ],
                    ),
                  ),
                ],
              ).then((value) async {
                switch (value) {
                  case 'import':
                    final success =
                        await UserData.importData(); // Remove context parameter
                    if (success && mounted) {
                      setState(() => _loadAlbums());
                    }
                    break;
                  case 'export':
                    await UserData.exportData(); // Remove context parameter
                    break;
                }
              }),
            ),
          ),
        ],
      ),
      body: Center(
        // Add this Center widget
        child: SizedBox(
          // Add this SizedBox for width constraint
          width: pageWidth,
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : albums.isEmpty
                  ? const Center(child: Text('No saved albums found'))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      itemCount: albums.length,
                      onReorder: _onReorder,
                      itemBuilder: (context, index) {
                        // Null safety check
                        final album = albums[index];
                        if ((album['collectionId'] == null &&
                            album['id'] == null)) {
                          return ListTile(
                            key: Key("error_$index"),
                            title: const Text("Error: Invalid album data"),
                          );
                        }

                        // Support both ID formats
                        final albumId =
                            (album['id'] ?? album['collectionId']).toString();
                        final artistName = album['artist'] ??
                            album['artistName'] ??
                            'Unknown Artist';
                        final albumName = album['name'] ??
                            album['collectionName'] ??
                            'Unknown Album';
                        final artworkUrl =
                            album['artworkUrl'] ?? album['artworkUrl100'] ?? '';
                        final rating = album['averageRating'] ?? 0.0;

                        return ListTile(
                          key: Key(albumId),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: isDarkTheme
                                          ? Colors.white
                                          : Colors.black),
                                ),
                                child: Center(
                                  child: Text(
                                    rating == 10
                                        ? '10.0'
                                        : rating.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkTheme
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Image.network(
                                artworkUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.album),
                              ),
                            ],
                          ),
                          title: Text(albumName),
                          subtitle: Text(artistName),
                          trailing: _buildAlbumActions(index),
                          onTap: () => _openSavedAlbumDetails(index),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}
