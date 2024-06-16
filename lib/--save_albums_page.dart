import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Saved Albums',
      home: SavedAlbumsPage(),
    );
  }
}

class SavedAlbumsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Albums'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _getSavedAlbums(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            List<Map<String, dynamic>> savedAlbums = snapshot.data ?? [];
            _printSavedAlbums(savedAlbums); // Imprimir los álbumes guardados en la consola
            return Center(
              child: Text('Los álbumes guardados se imprimieron en la consola'),
            );
          }
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getSavedAlbums() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedAlbumsString = prefs.getString('savedAlbums');
    List<Map<String, dynamic>> savedAlbums = [];
    if (savedAlbumsString != null && savedAlbumsString.isNotEmpty) {
      savedAlbums = jsonDecode(savedAlbumsString).cast<Map<String, dynamic>>();
    }
    return savedAlbums;
  }

  void _printSavedAlbums(List<Map<String, dynamic>> savedAlbums) {
    print('Álbumes guardados:');
    for (int i = 0; i < savedAlbums.length; i++) {
      print('$i: ${savedAlbums[i]}');
    }
  }
}
