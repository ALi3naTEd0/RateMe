import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'album_details_page.dart'; // Import the album details page

class SearchPage extends StatefulWidget {
  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController searchController = TextEditingController();
  List<dynamic> searchResults = [];

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
                  onPressed: () {
                    _searchOrLoadFromURL(searchController.text);
                  },
                ),
              ),
              onChanged: _onSearchChanged,
              maxLength: 255, // Maximum characters for search input
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

  void _onSearchChanged(String query) async {
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

  void _searchOrLoadFromURL(String input) async {
    if (input.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    // Verify if input is a valid iTunes URL
    final Uri? parsedUrl = Uri.tryParse(input); // Use Uri? instead of Uri
    if (parsedUrl != null &&
        parsedUrl.scheme == 'http' &&
        parsedUrl.host.contains('itunes.apple.com')) {
      // The input is an iTunes URL
      // Perform logic to load data from the URL
      // For now, simply print the URL
      print('URL entered: $input');
      return;
    }

    // Input is not a URL, perform normal search
    final url = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(input)}&entity=album');
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
