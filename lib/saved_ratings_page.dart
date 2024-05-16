import 'package:flutter/material.dart';
import 'user_data.dart';
import 'saved_album_details_page.dart';
import 'footer.dart';
import 'app_theme.dart';

class SavedRatingsPage extends StatefulWidget {
  @override
  _SavedRatingsPageState createState() => _SavedRatingsPageState();
}

class _SavedRatingsPageState extends State<SavedRatingsPage> {
  List<Map<String, dynamic>> savedAlbums = [];

  @override
  void initState() {
    super.initState();
    _loadSavedAlbums();
  }

  void _loadSavedAlbums() async {
    List<Map<String, dynamic>> albums = await UserData.getSavedAlbums();
    for (var album in albums) {
      List<Map<String, dynamic>> ratings = await UserData.getSavedAlbumRatings(album['collectionId']);
      double averageRating = _calculateAverageRating(ratings);
      album['averageRating'] = averageRating;
    }
    setState(() {
      savedAlbums = albums;
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

  void _deleteAlbum(int index) {
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
              onPressed: () {
                UserData.deleteAlbum(savedAlbums[index]);
                _loadSavedAlbums();
                Navigator.of(context).pop();
              },
              child: Text("Delete"),
            ),
          ],
        );
      },
    );
  }

  void _openSavedAlbumDetails(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SavedAlbumDetailsPage(album: savedAlbums[index])),
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

    List<String> albumIds = savedAlbums.map<String>((album) => album['collectionId'].toString()).toList();
    UserData.saveAlbumOrder(albumIds);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Ratings'),
      ),
      body: savedAlbums.isEmpty
          ? Center(
              child: Text('No saved albums yet.'),
            )
          : ReorderableListView(
              onReorder: _onReorder,
              children: savedAlbums.map((album) {
                return ListTile(
                  key: Key(album['collectionId'].toString()),
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 50, // Tamaño fijo para hacerlo cuadrado
                        height: 50, // Tamaño fijo para hacerlo cuadrado
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: isDarkTheme ? Colors.white : Colors.black), // Color del borde
                        ),
                        child: Center(
                          child: Text(
                            album['averageRating']?.toStringAsFixed(2) ?? 'N/A',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDarkTheme ? Colors.white : Colors.black, // Color del texto
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
      bottomNavigationBar: Footer(),
    );
  }
}
