import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'album_details_page.dart';

class SearchPage extends StatefulWidget {
  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController searchController = TextEditingController();
  List<dynamic> searchResults = [];
  Timer? _debounce; // Timer to delay the search

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                labelText: 'Search Albums or Paste URL',
                suffixIcon: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: () {}, // Remove the onPressed handler from here
                ),
              ),
              onChanged: _onSearchChanged,
              maxLength: 255, // Maximum characters for search entry
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
                  errorBuilder: (context, error, stackTrace) =>
                      Icon(Icons.album),
                ),
                title: Text(searchResults[index]['collectionName']),
                subtitle: Text(searchResults[index]['artistName']),
                onTap: () =>
                    _showAlbumDetails(searchResults[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  void _onSearchChanged(String query) {
    // Cancel the previous timer if it exists
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    // Set a new timer to search after 500 milliseconds
    _debounce = Timer(Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  void _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }
    final url = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=album');
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    setState(() => searchResults = data['results']);
  }

  void _showAlbumDetails(dynamic album) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => AlbumDetailsPage(album: album)));
  }
}
