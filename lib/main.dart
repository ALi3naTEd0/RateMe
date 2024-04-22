import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() => runApp(MusicRatingApp());

class MusicRatingApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rate Me!',
      debugShowCheckedModeBanner: false,
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
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: 'Search Albums',
                  suffixIcon: Icon(Icons.search),
                ),
                onChanged: _onSearchChanged,
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
                  onTap: () => _showAlbumDetails(searchResults[index]),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        height: 20,
        alignment: Alignment.center,
        child: Text('Version 0.0.3', style: TextStyle(color: Colors.grey)),
      ),
    );
  }

  void _onSearchChanged(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }
    final url = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=album');
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    setState(() => searchResults = data['results']);
  }

  void _showAlbumDetails(dynamic album) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => AlbumDetailsPage(album: album)));
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
  Map<int, double> ratings = {};
  double averageRating = 0.0;

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
      trackList.forEach((track) => ratings[track['trackId']] = 0.0);
      calculateAverageRating();
    });
  }

  void calculateAverageRating() {
    var ratedTracks = ratings.values.where((rating) => rating > 0).toList();
    if (ratedTracks.isNotEmpty) {
      double total = ratedTracks.reduce((a, b) => a + b);
      setState(() => averageRating = total / ratedTracks.length);
    } else {
      setState(() => averageRating = 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album['collectionName']),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Image.network(
                  widget.album['artworkUrl100'].replaceAll('100x100', '600x600'),
                  width: 300,
                  height: 300,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(Icons.album, size: 300),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Artist: ${widget.album['artistName']}"),
                    Text("Album: ${widget.album['collectionName']}"),
                    Text("Release Date: ${DateTime.parse(widget.album['releaseDate']).toString().substring(0,10).split('-').reversed.join('-')}"),
                  ],
                ),
              ),
              SizedBox(height: 20),
              Text("Rating: ${averageRating.toStringAsFixed(1)}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Divider(),
              DataTable(
                columns: const [
                  DataColumn(label: Text('Track No.')),
                  DataColumn(label: Text('Title')),
                  DataColumn(label: Text('Length')),
                  DataColumn(label: Text('Rating')),
                ],
                rows: tracks.map((track) => DataRow(
                  cells: [
                    DataCell(Text(track['trackNumber'].toString())),
                    DataCell(Text(track['trackName'])),
                    DataCell(Text(formatDuration(track['trackTimeMillis']))),
                    DataCell(Slider(
                      min: 0,
                      max: 10,
                      divisions: 10,
                      value: ratings[track['trackId']] ?? 0.0,
                      label: ratings[track['trackId']]?.toStringAsFixed(0) ?? '0',
                      onChanged: (newRating) {
                        setState(() {
                          ratings[track['trackId']] = newRating;
                          calculateAverageRating();
                        });
                      },
                    )),
                  ],
                )).toList(),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        height: 20,
        alignment: Alignment.center,
        child: Text('Version 0.0.3', style: TextStyle(color: Colors.grey)),
      ),
    );
  }

  String formatDuration(int millis) {
    int seconds = (millis ~/ 1000) % 60;
    int minutes = (millis ~/ 1000) ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
