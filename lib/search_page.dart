import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'album_details_page.dart';
import 'bandcamp_details_page.dart';
import 'bandcamp_service.dart';

class SearchPage extends StatefulWidget {
  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController searchController = TextEditingController();
  List<dynamic> searchResults = [];
  Timer? _debounce;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Search Albums'),
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
                  labelText: 'Search Albums or Paste URL',
                  suffixIcon: IconButton(
                    icon: Icon(Icons.search),
                    onPressed: () {
                      _performSearch(searchController.text);
                    },
                  ),
                ),
                onChanged: _onSearchChanged,
                maxLength: 255,
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
                  onTap: () => _showAlbumDetails(context, searchResults[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  void _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    if (query.contains('bandcamp.com')) {
      _fetchBandcampAlbumInfo(query);
    } else {
      _fetchiTunesAlbums(query);
    }
  }

  void _fetchiTunesAlbums(String query) async {
    final url = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=album');
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    setState(() => searchResults = data['results']);
  }

  void _fetchBandcampAlbumInfo(String url) async {
    try {
      final albumInfo = await BandcampService.saveAlbum(url);
      setState(() => searchResults = [albumInfo]);
    } catch (e) {
      setState(() => searchResults = []);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to load Bandcamp album: $e'),
      ));
    }
  }

  void _showAlbumDetails(BuildContext context, dynamic album) {
    // Check if the album URL contains "bandcamp.com"
    if (album['url'].toString().contains('bandcamp.com')) {
      // If the URL is from Bandcamp, open the Bandcamp details page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) {
            return BandcampDetailsPage(album: album);
          },
        ),
      );
    } else {
      // If not from Bandcamp, open the standard album details page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) {
            return AlbumDetailsPage(album: album);
          },
        ),
      );
    }
  }
}
