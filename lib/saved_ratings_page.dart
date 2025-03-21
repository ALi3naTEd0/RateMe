import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'user_data.dart';
import 'saved_album_page.dart';
import 'share_widget.dart';
import 'logging.dart';  // Add this import

class SavedRatingsPage extends StatefulWidget {
  const SavedRatingsPage({super.key});

  @override
  _SavedRatingsPageState createState() => _SavedRatingsPageState();
}

class _SavedRatingsPageState extends State<SavedRatingsPage> {
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
      
      for (var album in savedAlbums) {
        try {
          final metadata = album['metadata']?['metadata'] ?? album['metadata'];
          
          final albumMap = {
            'collectionId': metadata?['id'] ?? 
                           metadata?['collectionId'] ?? 
                           album['id'] ?? 
                           album['collectionId'],
            'collectionName': metadata?['collectionName'] ?? 
                            metadata?['name'] ?? 
                            album['name'] ?? 
                            album['collectionName'],
            'artistName': metadata?['artistName'] ?? 
                         metadata?['artist'] ?? 
                         album['artist'] ?? 
                         album['artistName'],
            'artworkUrl100': metadata?['artworkUrl100'] ?? 
                            metadata?['artworkUrl'] ?? 
                            album['artworkUrl'] ?? 
                            album['artworkUrl100'],
            'platform': metadata?['platform'] ?? album['platform'] ?? 'unknown',
            'url': metadata?['url'] ?? album['url'],
            'averageRating': await _calculateAlbumRating(
              metadata?['id'] ?? metadata?['collectionId'] ?? album['id'] ?? album['collectionId']
            ),
            'metadata': metadata,
          };
          
          loadedAlbums.add(albumMap);
        } catch (e) {
          continue;
        }
      }

      if (mounted) {
        setState(() {
          albums = loadedAlbums;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  /// Calculate average rating for an album
  Future<double> _calculateAlbumRating(int albumId) async {
    try {
      final ratings = await UserData.getRatings(albumId);
      if (ratings == null || ratings.isEmpty) return 0.0;
      
      var ratedTracks = ratings.values.where((rating) => rating > 0).toList();
      if (ratedTracks.isEmpty) return 0.0;
      
      double total = ratedTracks.reduce((a, b) => a + b);
      return double.parse((total / ratedTracks.length).toStringAsFixed(2));
    } catch (e) {
      Logging.severe('Error calculating album rating', e);
      return 0.0;
    }
  }

  double _calculateAverageRating(List<Map<String, dynamic>> ratings) {
    if (ratings.isEmpty) return 0.0;
    var uniqueRatings = <int, double>{};

    for (var rating in ratings.reversed) {
      if (!uniqueRatings.containsKey(rating['trackId'])) {
        uniqueRatings[rating['trackId']] = rating['rating'];
      }
    }

    if (uniqueRatings.isEmpty) return 0.0;

    double totalRating = uniqueRatings.values.reduce((a, b) => a + b);
    return totalRating / uniqueRatings.length;
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
      await UserData.saveAlbumOrder(
        albums.map<String>((album) => album['collectionId'].toString()).toList()
      );
    }
  }

  void _openSavedAlbumDetails(int index) {
    final album = albums[index];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SavedAlbumPage(
          album: album,
          isBandcamp: album['url']?.toString().contains('bandcamp.com') ?? false,
        ),
      ),
    ).then((_) => _loadAlbums());  // Reload when returning
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
        .map<String>((album) => (album['id'] ?? album['collectionId']).toString())
        .toList();
    UserData.saveAlbumOrder(albumIds);
  }

  void _handleImageShare(String imagePath) async {
    try {
      await Share.shareXFiles([XFile(imagePath)]);  // Replace ShareExtend.share
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing: $e')),
        );
      }
    }
  }

  void _showShareDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final shareWidget = ShareWidget(
          key: ShareWidget.shareKey,
          title: 'Saved Albums',
          albums: albums,
        );
        return AlertDialog(
          content: SingleChildScrollView(
            child: shareWidget,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  final path = await ShareWidget.shareKey.currentState?.saveAsImage();
                  if (mounted && path != null) {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: context,
                      builder: (BuildContext context) {
                        return SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              ListTile(
                                leading: const Icon(Icons.download),
                                title: const Text('Save to Downloads'),
                                onTap: () async {
                                  Navigator.pop(context);
                                  try {
                                    final downloadDir = Directory('/storage/emulated/0/Download');
                                    final fileName = 'RateMe_${DateTime.now().millisecondsSinceEpoch}.png';
                                    final newPath = '${downloadDir.path}/$fileName';
                                    await File(path).copy(newPath);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Saved to Downloads: $fileName')),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error saving file: $e')),
                                      );
                                    }
                                  }
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.share),
                                title: const Text('Share Image'),
                                onTap: () async {
                                  Navigator.pop(context);
                                  _handleImageShare(path);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error saving image: $e')),
                    );
                  }
                }
              },
              child: const Text('Save & Share'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Ratings'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            onSelected: (value) async {
              switch (value) {
                case 'import':
                  final success = await UserData.importData(context);
                  if (success && mounted) {
                    setState(() => _loadAlbums());
                  }
                  break;
                case 'export':
                  await UserData.exportData(context);
                  break;
                case 'share':
                  _showShareDialog(context);
                  break;
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.file_download),
                    SizedBox(width: 8),
                    Text('Import Data'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_upload),
                    SizedBox(width: 8),
                    Text('Export Data'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share),
                    SizedBox(width: 8),
                    Text('Share as Image'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: isLoading
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
                    if (album == null || (album['collectionId'] == null && album['id'] == null)) {
                      return ListTile(
                        key: Key("error_$index"),
                        title: const Text("Error: Invalid album data"),
                      );
                    }
                    
                    // Support both ID formats
                    final albumId = (album['id'] ?? album['collectionId']).toString();
                    final artistName = album['artist'] ?? album['artistName'] ?? 'Unknown Artist';
                    final albumName = album['name'] ?? album['collectionName'] ?? 'Unknown Album';
                    final artworkUrl = album['artworkUrl'] ?? album['artworkUrl100'] ?? '';
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
                                  color: isDarkTheme ? Colors.white : Colors.black),
                            ),
                            child: Center(
                              child: Text(
                                rating.toStringAsFixed(2),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDarkTheme ? Colors.white : Colors.black,
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
    );
  }
}
