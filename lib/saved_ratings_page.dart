import 'package:flutter/material.dart';
import 'dart:convert';
import 'user_data.dart';
import 'saved_album_page.dart';
import 'logging.dart';

class SavedRatingsPage extends StatefulWidget {
  const SavedRatingsPage({super.key});

  @override
  State<SavedRatingsPage> createState() => _SavedRatingsPageState();
}

class _SavedRatingsPageState extends State<SavedRatingsPage> {
  List<Map<String, dynamic>> albums = [];
  List<String> albumOrder = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    try {
      // First get all saved albums
      final List<Map<String, dynamic>> savedAlbums =
          await UserData.getSavedAlbums();

      // Log some debug info
      Logging.severe('Loading ${savedAlbums.length} saved albums');

      // Get album order
      List<String> order = await UserData.getAlbumOrder();
      if (order.isEmpty) {
        // If order is empty, create default order from album IDs
        order = savedAlbums.map((album) => album['id'].toString()).toList();
      }

      // Calculate ratings for display
      for (var album in savedAlbums) {
        try {
          // Ensure we have a valid ID
          final albumId = album['id'] ?? album['collectionId'];
          if (albumId == null) continue;

          Logging.severe('Processing album: ${jsonEncode({
                'id': albumId,
                'name': album['name'] ?? album['collectionName']
              })}');

          // Calculate average rating
          Logging.severe('Calculating rating for album ID: $albumId');

          final List<Map<String, dynamic>> ratings =
              await UserData.getSavedAlbumRatings(albumId);

          if (ratings.isNotEmpty) {
            // Only count non-zero ratings
            final nonZeroRatings =
                ratings.where((r) => r['rating'] > 0).toList();
            Logging.severe(
                'Found ${ratings.length} ratings for album $albumId');

            if (nonZeroRatings.isNotEmpty) {
              double sum = 0;
              for (var rating in nonZeroRatings) {
                sum += rating['rating'];
              }
              final averageRating = sum / nonZeroRatings.length;
              album['averageRating'] = averageRating;
              Logging.severe(
                  'Album $albumId average rating: $averageRating from ${nonZeroRatings.length} tracks');
            }
          } else {
            Logging.severe('No ratings found for album ID: $albumId');
          }

          // Ensure artwork URL is preserved and logged
          Logging.severe(
              'Album artwork URL: ${album['artworkUrl'] ?? album['artworkUrl100'] ?? 'missing'}');

          // Add to display list
          Logging.severe(
              'Added album to display list: ${album['name'] ?? album['collectionName']}');
        } catch (e, stack) {
          Logging.severe('Error processing album', e, stack);
        }
      }

      // Sort albums according to the order
      final Map<String, Map<String, dynamic>> albumMap = {};
      for (var album in savedAlbums) {
        final id = album['id']?.toString() ?? album['collectionId']?.toString();
        if (id != null) {
          albumMap[id] = album;
        }
      }

      // Create ordered list
      final orderedAlbums = <Map<String, dynamic>>[];
      for (var id in order) {
        if (albumMap.containsKey(id)) {
          orderedAlbums.add(albumMap[id]!);
        }
      }

      // Add any albums not in the order at the end
      for (var album in savedAlbums) {
        final id = album['id']?.toString() ?? album['collectionId']?.toString();
        if (id != null && !order.contains(id)) {
          orderedAlbums.add(album);
          order.add(id);
        }
      }

      Logging.severe('Loaded ${orderedAlbums.length} albums for display');

      if (mounted) {
        setState(() {
          albums = orderedAlbums;
          albumOrder = order;
          isLoading = false;
        });
      }
    } catch (e, stack) {
      Logging.severe('Error loading saved albums', e, stack);
      if (mounted) {
        setState(() {
          albums = [];
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate page width for consistency with other screens
    final pageWidth = MediaQuery.of(context).size.width * 0.85;
    final horizontalPadding =
        (MediaQuery.of(context).size.width - pageWidth) / 2;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              const Text('Saved Albums'),
            ],
          ),
        ),
      ),
      body: Center(
        child: isLoading
            ? const CircularProgressIndicator()
            : albums.isEmpty
                ? const Text('No saved albums')
                : SizedBox(
                    width: pageWidth,
                    child: ReorderableListView.builder(
                      itemCount: albums.length,
                      onReorder: (oldIndex, newIndex) async {
                        if (oldIndex < newIndex) {
                          newIndex -= 1;
                        }

                        setState(() {
                          final album = albums.removeAt(oldIndex);
                          albums.insert(newIndex, album);

                          // Update album order
                          albumOrder = albums
                              .map((a) =>
                                  a['id']?.toString() ??
                                  a['collectionId']?.toString() ??
                                  '')
                              .where((id) => id.isNotEmpty)
                              .toList();
                        });

                        // Save the new order
                        await UserData.saveAlbumOrder(albumOrder);
                      },
                      itemBuilder: (context, index) {
                        final album = albums[index];
                        return _buildCompactAlbumCard(album, index);
                      },
                    ),
                  ),
      ),
    );
  }

  Widget _buildCompactAlbumCard(Map<String, dynamic> album, int index) {
    // Ensure we handle both formats consistently
    final albumName =
        album['name'] ?? album['collectionName'] ?? 'Unknown Album';
    final artistName =
        album['artist'] ?? album['artistName'] ?? 'Unknown Artist';
    final artworkUrl = album['artworkUrl'] ?? album['artworkUrl100'] ?? '';
    final albumId = album['id'] ?? album['collectionId'] ?? '';
    final averageRating = album['averageRating'] ?? 0.0;

    // Check if this is a Bandcamp album
    final isBandcamp = album['platform'] == 'bandcamp' ||
        (album['url']?.toString().contains('bandcamp.com') ?? false);

    return Card(
      key: ValueKey(albumId),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Rating display in a prominent box
            Container(
              width: 48, // Rating box width
              height: 48, // Rating box height
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(
                    red: Theme.of(context).colorScheme.primary.r.toDouble(),
                    green: Theme.of(context).colorScheme.primary.g.toDouble(),
                    blue: Theme.of(context).colorScheme.primary.b.toDouble(),
                    alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  averageRating > 0 ? averageRating.toStringAsFixed(1) : '-',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Album artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: artworkUrl.isNotEmpty
                  ? Image.network(
                      artworkUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 48,
                          height: 48,
                          color: Colors.grey[300],
                          child: const Icon(Icons.album, size: 24),
                        );
                      },
                    )
                  : Container(
                      width: 48,
                      height: 48,
                      color: Colors.grey[300],
                      child: const Icon(Icons.album, size: 24),
                    ),
            ),
          ],
        ),
        title: Text(
          albumName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          artistName,
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyMedium?.color,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Delete button
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: () => _confirmDeleteAlbum(album, index),
              tooltip: 'Delete Album',
            ),
            // Drag handle
            const Icon(Icons.drag_handle),
          ],
        ),
        onTap: () {
          // Create a properly formatted album object before passing to SavedAlbumPage
          final normalizedAlbum = Map<String, dynamic>.from(album);

          // Ensure critical fields exist with proper names
          if (!normalizedAlbum.containsKey('collectionName') &&
              normalizedAlbum.containsKey('name')) {
            normalizedAlbum['collectionName'] = normalizedAlbum['name'];
          }

          if (!normalizedAlbum.containsKey('artistName') &&
              normalizedAlbum.containsKey('artist')) {
            normalizedAlbum['artistName'] = normalizedAlbum['artist'];
          }

          if (!normalizedAlbum.containsKey('artworkUrl100') &&
              normalizedAlbum.containsKey('artworkUrl')) {
            normalizedAlbum['artworkUrl100'] = normalizedAlbum['artworkUrl'];
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SavedAlbumPage(
                album: normalizedAlbum,
                isBandcamp: isBandcamp,
              ),
            ),
          ).then((_) => _loadAlbums());
        },
      ),
    );
  }

  Future<void> _confirmDeleteAlbum(
      Map<String, dynamic> album, int index) async {
    final albumName =
        album['name'] ?? album['collectionName'] ?? 'Unknown Album';
    final artistName =
        album['artist'] ?? album['artistName'] ?? 'Unknown Artist';

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Album'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete this album?'),
            const SizedBox(height: 16),
            Text(
              albumName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(artistName),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        final success = await UserData.deleteAlbum(album);
        if (success) {
          setState(() {
            albums.removeAt(index);
            // Also update the album order
            albumOrder = albums
                .map((a) =>
                    a['id']?.toString() ?? a['collectionId']?.toString() ?? '')
                .where((id) => id.isNotEmpty)
                .toList();
            UserData.saveAlbumOrder(albumOrder);
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Album deleted')),
            );
          }
        }
      } catch (e) {
        Logging.severe('Error deleting album', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting album: $e')),
          );
        }
      }
    }
  }
}
