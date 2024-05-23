import 'package:flutter/material.dart';
import 'user_data.dart';

class SavedPreferencesPage extends StatefulWidget {
  @override
  _SavedPreferencesPageState createState() => _SavedPreferencesPageState();
}

class _SavedPreferencesPageState extends State<SavedPreferencesPage> {
  List<Map<String, dynamic>> savedAlbums = [];

  @override
  void initState() {
    super.initState();
    _loadSavedAlbums();
  }

  Future<void> _loadSavedAlbums() async {
    List<Map<String, dynamic>> albums = await UserData.getSavedAlbums();
    setState(() {
      savedAlbums = albums;
    });
  }

  Future<void> _deleteAlbum(Map<String, dynamic> album) async {
    await UserData.deleteAlbum(album);
    _loadSavedAlbums();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Preferences'),
      ),
      body: savedAlbums.isEmpty
          ? Center(child: Text('No albums saved'))
          : ListView.builder(
              itemCount: savedAlbums.length,
              itemBuilder: (context, index) {
                final album = savedAlbums[index];
                return ListTile(
                  title: Text(album['collectionName']),
                  subtitle: Text(album['artistName']),
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: Text('Confirm Delete'),
                            content: Text('Are you sure you want to delete this album?'),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  _deleteAlbum(album);
                                  Navigator.of(context).pop();
                                },
                                child: Text('Delete'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}