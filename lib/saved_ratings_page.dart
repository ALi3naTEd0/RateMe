import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'album_details_page.dart'; // Importa la página AlbumDetailsPage
import 'user_data.dart'; // Importa la clase UserData

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

  void _saveRatedAlbum(Map<String, dynamic> album) {
    UserData.saveAlbum(album);
    setState(() {
      savedAlbums.add(album);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Album saved successfully!'),
        duration: Duration(seconds: 2),
      ),
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
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AlbumDetailsPage(album: album),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
