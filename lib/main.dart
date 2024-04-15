import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() => runApp(MusicRatingApp());

class MusicRatingApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rate Me!',
      home: SearchPage(),
    );
  }
}

class SearchPage extends StatefulWidget {
  @override
  _SearchPageState createState() => _SearchPageState();
}

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
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                labelText: 'Search Albums',
                suffixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearchChanged,
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
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(Icons.album); // Icono por defecto si la imagen no carga
                    },
                  ),
                  title: Text(searchResults[index]['collectionName']),
                  subtitle: Text(searchResults[index]['artistName']),
                  onTap: () => _showAlbumDetails(searchResults[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String query) async {
    if (query.isEmpty) {
      setState(() {
        searchResults = [];
      });
      return;
    }
    final url = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=album');
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    setState(() {
      searchResults = data['results'];
    });
  }

  void _showAlbumDetails(dynamic album) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AlbumDetailsPage(album: album)),
    );
  }
}

class AlbumDetailsPage extends StatefulWidget {
  final dynamic album;

  AlbumDetailsPage({Key? key, required this.album}) : super(key: key);

  @override
  _AlbumDetailsPageState createState() => _AlbumDetailsPageState();
}

class _AlbumDetailsPageState extends State<AlbumDetailsPage> {
  List<dynamic> tracks = [];
  Map<int, double> ratings = {};  // Mapa para guardar las calificaciones de las canciones

  @override
  void initState() {
    super.initState();
    _fetchTracks();
  }

  void _fetchTracks() async {
    final url = Uri.parse('https://itunes.apple.com/lookup?id=${widget.album['collectionId']}&entity=song');
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    var trackList = data['results'].where((track) => track['wrapperType'] == 'track').toList();
    setState(() {
      tracks = trackList;
      trackList.forEach((track) {
        ratings[track['trackId']] = 0.0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album['collectionName']),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Image.network(
                    widget.album['artworkUrl100'].replaceAll('100x100', '600x600'), // Aumenta la resolución de la imagen
                    width: 300,
                    height: 300,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(Icons.album, size: 300); // Icono por defecto si la imagen no carga
                    },
                  ),
                  Text(widget.album['collectionName'], style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(widget.album['artistName'], style: TextStyle(fontSize: 18)),
                  Text(DateTime.parse(widget.album['releaseDate']).toString().substring(0,10).split('-').reversed.join('-'), style: TextStyle(fontSize: 16)), // Formato de fecha
                ],
              ),
            ),
            Divider(),
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                var track = tracks[index];
                return ListTile(
                  title: Text(track['trackName']),
                  subtitle: Text('Track No: ${track['trackNumber']}'),
                  trailing: SizedBox(
                    width: 200,
                    child: Slider(
                      min: 0,
                      max: 10,
                      divisions: 10,
                      value: ratings[track['trackId']] ?? 0.0,
                      label: (ratings[track['trackId']] ?? 0.0).toStringAsFixed(1),
                      onChanged: (newRating) {
                        setState(() {
                          ratings[track['trackId']] = newRating;
                        });
                      },
                    ),
                  ),
                );
              },
            ),
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Average Rating: ${_calculateAverageRating().toStringAsFixed(1)}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            )
          ],
        ),
      ),
    );
  }

  double _calculateAverageRating() {
    var filteredRatings = ratings.values.where((rating) => rating > 0).toList();
    if (filteredRatings.isEmpty) return 0.0;
    var total = filteredRatings.reduce((a, b) => a + b);
    return total / filteredRatings.length;
  }
}
