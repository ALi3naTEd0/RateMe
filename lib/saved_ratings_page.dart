import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';  // Reemplazar share_extend
import 'dart:io';
import 'user_data.dart';
import 'saved_album_page.dart';
import 'share_widget.dart';

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
    List<Map<String, dynamic>> albums = await UserData.getSavedAlbums();
    for (var album in albums) {
      int? collectionId = int.tryParse(album['collectionId'].toString());
      if (collectionId != null) {
        List<Map<String, dynamic>> ratings =
            await UserData.getSavedAlbumRatings(collectionId);
        double averageRating = _calculateAverageRating(ratings);
        album['averageRating'] = averageRating;
      }
    }
    if (mounted) {
      setState(() {
        savedAlbums = albums;
        isLoading = false;
      });
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
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Delete"),
          content: const Text(
              "Are you sure you want to delete this item from Saved Ratings?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      await UserData.deleteAlbum(savedAlbums[index]);
      if (mounted) {
        setState(() {
          savedAlbums.removeAt(index);
        });
      }
      // Update the list of albums saved in persistent memory
      await UserData.saveAlbumOrder(savedAlbums
          .map<String>((album) => album['collectionId'].toString())
          .toList());
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
        .map<String>((album) => album['collectionId'].toString())
        .toList();
    UserData.saveAlbumOrder(albumIds);
  }

  void _handleImageShare(String imagePath) async {
    try {
      await Share.shareXFiles([XFile(imagePath)]);  // Reemplazar ShareExtend.share
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
                    final album = savedAlbums[index];
                    return ListTile(
                      key: Key(album['collectionId'].toString()),
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
                                album['averageRating']?.toStringAsFixed(2) ?? 'N/A',
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
                            album['artworkUrl100'],
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.album),
                          ),
                        ],
                      ),
                      title: Text(album['collectionName'] ?? 'N/A'),
                      subtitle: Text(album['artistName'] ?? 'N/A'),
                      trailing: _buildAlbumActions(index),
                      onTap: () => _openSavedAlbumDetails(index),
                    );
                  },
                ),
    );
  }
}
