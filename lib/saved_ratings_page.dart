// saved_ratings_page.dart
import 'package:flutter/material.dart';
import 'user_data.dart';
import 'saved_album_details_page.dart';
import 'bandcamp_details_page.dart';
import 'bandcamp_saved_album_page.dart';
import 'footer.dart';
import 'app_theme.dart';

class SavedRatingsPage extends StatefulWidget {
  @override
  _SavedRatingsPageState createState() => _SavedRatingsPageState();
}

class _SavedRatingsPageState extends State<SavedRatingsPage> {
  List<Map<String, dynamic>> savedAlbums = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedAlbums();
  }

  void _loadSavedAlbums() async {
    List<Map<String, dynamic>> albums = await UserData.getSavedAlbums();
    for (var album in albums) {
      int? collectionId = int.tryParse(album['collectionId'].toString());
      if (collectionId != null) {
        List<Map<String, dynamic>> ratings = await UserData.getSavedAlbumRatings(collectionId);
        double averageRating = _calculateAverageRating(ratings);
        album['averageRating'] = averageRating;
      }
    }
    setState(() {
      savedAlbums = albums;
      isLoading = false;
    });
  }

  double _calculateAverageRating(List<Map<String, dynamic>> ratings) {
    if (ratings.isEmpty) return 0.0;
    var uniqueRatings = Map<int, double>();

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
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Confirm Delete"),
          content: Text("Are you sure you want to delete this item from Saved Ratings?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                await UserData.deleteAlbum(savedAlbums[index]);
                // Remove the album from the list
                setState(() {
                  savedAlbums.removeAt(index);
                });
                Navigator.of(context).pop();
              },
              child: Text("Delete"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateAlbumRatings() async {
    // Iterate through saved albums and update ratings
    for (int i = 0; i < savedAlbums.length; i++) {
      List<Map<String, dynamic>> ratings = await UserData.getSavedAlbumRatings(savedAlbums[i]['collectionId']);
      double averageRating = _calculateAverageRating(ratings);
      setState(() {
        savedAlbums[i]['averageRating'] = averageRating;
      });
    }
  }

  void _openSavedAlbumDetails(int index) {
    final album = savedAlbums[index];
    final url = album['url'];

    if (url != null && url.contains('bandcamp.com')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => BandcampSavedAlbumPage(album: album)),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => SavedAlbumDetailsPage(album: album)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Ratings'),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : savedAlbums.isEmpty
              ? Center(child: Text('No saved albums found'))
              : ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width),
                  child: SingleChildScrollView(
                    child: Container( // Wrap the ReorderableListView with a Container
                      height: MediaQuery.of(context).size.height, // Set a specific height
                      child: ReorderableListView(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        physics: AlwaysScrollableScrollPhysics(),
                        onReorder: (oldIndex, newIndex) async {
                          setState(() {
                            if (newIndex > oldIndex) {
                              newIndex -= 1;
                            }
                            final album = savedAlbums.removeAt(oldIndex);
                            savedAlbums.insert(newIndex, album);
                          });

                          // Update the order of albums in local storage
                          List<String> albumIds = savedAlbums.map<String>((album) => album['collectionId'].toString()).toList();
                          await UserData.saveAlbumOrder(albumIds);
                        },
                        children: savedAlbums.map((album) {
                          return ListTile(
                            key: Key(album['collectionId'].toString()),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: isDarkTheme ? Colors.white : Colors.black),
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
                                SizedBox(width: 8),
                                Image.network(
                                  album['artworkUrl100'],
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Icon(Icons.album),
                                ),
                              ],
                            ),
                            title: Text(album['collectionName'] ?? 'N/A'),
                            subtitle: Text(album['artistName'] ?? 'N/A'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => _deleteAlbum(savedAlbums.indexOf(album)),
                                  child: Icon(Icons.delete),
                                ),
                                SizedBox(width: 16),
                              ],
                            ),
                            onTap: () {
                              _openSavedAlbumDetails(savedAlbums.indexWhere((a) => a['collectionId'] == album['collectionId']));
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
      bottomNavigationBar: Footer(),
    );
  }
}
