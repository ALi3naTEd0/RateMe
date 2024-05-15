// saved_ratings_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_data.dart';
import 'saved_album_details_page.dart';
import 'footer.dart';

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
    List<String> albumOrder = await UserData.getSavedAlbumOrder();
    setState(() {
      savedAlbums = albums;
      _reorderAlbums(albumOrder);
    });
  }

  void _reorderAlbums(List<String> albumOrder) {
    if (albumOrder.isNotEmpty) {
      savedAlbums.sort((a, b) => albumOrder.indexOf(a['collectionId'].toString())
          .compareTo(albumOrder.indexOf(b['collectionId'].toString())));
    }
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
                _loadSavedAlbums(); // Reload list after deleting album
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

    // Guardar el nuevo orden en SharedPreferences
    _saveAlbumOrder();
  }

  Future<void> _saveAlbumOrder() async {
    List<String> albumIds = savedAlbums.map<String>((album) => album['collectionId'].toString()).toList();
    await UserData.saveAlbumOrder(albumIds);
  }

  @override
  Widget build(BuildContext context) {
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
                  leading: Image.network(
                    album['artworkUrl100'],
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(Icons.album),
                  ),
                  title: Text(album['collectionName']),
                  subtitle: Text(album['artistName']),
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => _deleteAlbum(savedAlbums.indexWhere((a) => a['collectionId'] == album['collectionId'])),
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
