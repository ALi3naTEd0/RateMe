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
  @override
  void initState() {
    super.initState();
    _loadSavedAlbums();
  }

  List<Map<String, dynamic>> savedAlbums = [];
  bool isLoading = true;

  void _loadSavedAlbums() async {
    try {
      List<Map<String, dynamic>> albums = await UserData.getSavedAlbums();
      
      // Process each album and add average rating
      for (var album in albums) {
        if (album != null) {
          // Support both new model (id) and legacy model (collectionId)
          var albumId = album['id'] ?? album['collectionId'];
          if (albumId != null) {
            try {
              // Convert ID to int regardless of format
              int intAlbumId = albumId is int ? albumId : int.parse(albumId.toString());
              List<Map<String, dynamic>> ratings = await UserData.getSavedAlbumRatings(intAlbumId);
              double averageRating = _calculateAverageRating(ratings);
              album['averageRating'] = averageRating;
              
              // Ensure collectionId exists for backward compatibility
              if (album['collectionId'] == null && album['id'] != null) {
                album['collectionId'] = album['id'];
              }
            } catch (e) {
              Logging.severe('Error loading ratings for album: $e');
              album['averageRating'] = 0.0;
            }
          } else {
            Logging.severe('Album has no ID field: ${album.toString()}');
            album['averageRating'] = 0.0;
          }
        }
      }
      
      // Filter out null entries
      albums = albums.where((album) => 
        album != null && 
        (album['collectionId'] != null || album['id'] != null)
      ).toList();
      
      if (mounted) {
        setState(() {
          savedAlbums = albums;
          isLoading = false;
        });
      }
    } catch (e) {
      Logging.severe('Error loading saved albums: $e');
      if (mounted) {
        setState(() {
          savedAlbums = [];
          isLoading = false;
        });
      }
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
        final album = savedAlbums[index];
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
      await UserData.deleteAlbum(savedAlbums[index]);
      if (mounted) {
        setState(() {
          savedAlbums.removeAt(index);
        });
      }
      await UserData.saveAlbumOrder(
        savedAlbums.map<String>((album) => album['collectionId'].toString()).toList()
      );
    }
  }

  void _openSavedAlbumDetails(int index) {
    final album = savedAlbums[index];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SavedAlbumPage(
          album: album,
          isBandcamp: album['url']?.toString().contains('bandcamp.com') ?? false,
        ),
      ),
    ).then((_) => _loadSavedAlbums());  // Reload when returning
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
      final album = savedAlbums.removeAt(oldIndex);
      savedAlbums.insert(newIndex, album);
    });

    List<String> albumIds = savedAlbums
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
          albums: savedAlbums,
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
                    setState(() => _loadSavedAlbums());
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
          : savedAlbums.isEmpty
              ? const Center(child: Text('No saved albums found'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  itemCount: savedAlbums.length,
                  onReorder: _onReorder,
                  itemBuilder: (context, index) {
                    // Null safety check
                    final album = savedAlbums[index];
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
