import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'album_details_page.dart'; // Import album_details_page.dart

// Main widget for the search page
class SearchPage extends StatefulWidget {
  @override
  _SearchPageState createState() => _SearchPageState();
}

// Corresponding state for the SearchPage widget
class _SearchPageState extends State<SearchPage> {
  final TextEditingController searchController = TextEditingController();
  List<dynamic> searchResults = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Rate Me!'),
        centerTitle: true,
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: 'Search Albums',
                  suffixIcon: Icon(Icons.search),
                ),
                onChanged: _onSearchChanged, // Call _onSearchChanged function when text changes
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: searchResults.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: Image.network(
                    searchResults[index]['artworkUrl100'],
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Icon(Icons.album),
                  ),
                  title: Text(searchResults[index]['collectionName']),
                  subtitle: Text(searchResults[index]['artistName']),
                  onTap: () => _showAlbumDetails(searchResults[index]), // Call _showAlbumDetails function when list item is tapped
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        height: 20,
        alignment: Alignment.center,
        child: Text('Version 0.0.4', style: TextStyle(color: Colors.grey)),
      ),
    );
  }

  // Function to handle changes in search text
  void _onSearchChanged(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []); // If search is empty, clear results
      return;
    }
    final url = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=album');
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    setState(() => searchResults = data['results']); // Update search results
  }

  // Function to show album details
  void _showAlbumDetails(dynamic album) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => AlbumDetailsPage(album: album))); // Navigate to album details page
  }
}
