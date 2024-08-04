import 'package:flutter/material.dart';
import 'user_data.dart';

class SavedPreferencesPage extends StatefulWidget {
  const SavedPreferencesPage({super.key});

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
        title: const Text('Saved Preferences'),
      ),
      body: savedAlbums.isEmpty
          ? const Center(child: Text('No albums saved'))
          : ListView.builder(
              itemCount: savedAlbums.length,
              itemBuilder: (context, index) {
                final album = savedAlbums[index];
                return ListTile(
                  title: Text(album['collectionName']),
                  subtitle: Text(album['artistName']),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text('Confirm Delete'),
                            content: const Text('Are you sure you want to delete this album?'),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  _deleteAlbum(album);
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Delete'),
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
