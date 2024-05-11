import 'package:flutter/material.dart';
import 'user_data.dart'; // Importa la clase UserData
import 'album_details_page.dart'; // Import AlbumDetailsPage

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
    setState(() {
      savedAlbums = albums;
    });
  }

  void _editAlbum(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AlbumDetailsPage(album: savedAlbums[index])),
    );
  }

  void _deleteAlbum(int index) {
    UserData.deleteAlbum(savedAlbums[index]);
    _loadSavedAlbums(); // Recargar la lista después de eliminar el álbum
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
          : ListView.builder(
              itemCount: savedAlbums.length,
              itemBuilder: (context, index) {
                final album = savedAlbums[index];
                return ListTile(
                  leading: Image.network(album['artworkUrl100']),
                  title: Text(album['collectionName']),
                  subtitle: Text(album['artistName']),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit),
                        onPressed: () => _editAlbum(index),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete),
                        onPressed: () => _deleteAlbum(index),
                      ),
                    ],
                  ),
                  onTap: () {
                    // Navegar a la página de detalles del álbum
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => AlbumDetailsPage(album: album)),
                    );
                  },
                );
              },
            ),
    );
  }
}
