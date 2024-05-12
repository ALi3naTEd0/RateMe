import 'package:flutter/material.dart';
import 'user_data.dart'; // Importa la clase UserData
import 'album_details_page.dart'; // Import AlbumDetailsPage
import 'saved_album_details_page.dart'; // Import SavedAlbumDetailsPage
import 'footer.dart'; // Importa el widget Footer

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

  void _deleteAlbum(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Confirm Delete"),
          content: Text("Are you sure you want to delete this item from the database?"),
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
                _loadSavedAlbums(); // Recargar la lista después de eliminar el álbum
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
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => _deleteAlbum(index),
                  ),
                  onTap: () {
                    // Abre la página de detalles del álbum guardado
                    _openSavedAlbumDetails(index);
                  },
                );
              },
            ),
      bottomNavigationBar: Footer(), // Agrega el footer
    );
  }
}
