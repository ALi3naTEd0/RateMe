import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'footer.dart';
import 'app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'user_data.dart'; // Importa la clase UserData

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
  int albumDurationMillis = 0;

  @override
  void initState() {
    super.initState();
    _fetchTracks();
  }

  void _fetchTracks() async {
    final url = Uri.parse(
        'https://itunes.apple.com/lookup?id=${widget.album['collectionId']}&entity=song');
    try {
      final response = await http.get(url);
      final data = jsonDecode(response.body);
      var trackList =
          data['results'].where((track) => track['wrapperType'] == 'track').toList();
      setState(() {
        tracks = trackList;
        trackList.forEach((track) => ratings[track['trackId']] = 0.0);
        calculateAverageRating();
        calculateAlbumDuration();
      });
    } catch (error) {
      print('Error fetching tracks: $error');
    }
  }

  void calculateAverageRating() {
    var ratedTracks = ratings.values.where((rating) => rating > 0).toList();
    if (ratedTracks.isNotEmpty) {
      double total = ratedTracks.reduce((a, b) => a + b);
      setState(() {
        averageRating = total / ratedTracks.length;
        averageRating = double.parse(averageRating.toStringAsFixed(2));
      });
    } else {
      setState(() => averageRating = 0.0);
    }
  }

  void calculateAlbumDuration() {
    int totalDuration = 0;
    tracks.forEach((track) {
      if (track['trackTimeMillis'] != null) {
        totalDuration += (track['trackTimeMillis'] ?? 0) as int; // Conversión a entero
      }
    });
    setState(() {
      albumDurationMillis = totalDuration;
    });
  }

  void _launchRateYourMusic() async {
    final artistName = widget.album['artistName'];
    final albumName = widget.album['collectionName'];
    final url =
        'https://rateyourmusic.com/search?searchterm=${Uri.encodeComponent(artistName)}+${Uri.encodeComponent(albumName)}&searchtype=l';
    try {
      if (await canLaunch(url)) {
        await launch(url);
      } else {
        throw 'Could not launch $url';
      }
    } catch (error) {
      print('Error launching RateYourMusic: $error');
    }
  }

  void _saveInHistory() {
    UserData.saveAlbum(widget.album);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Album saved in history'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _updateRating(int trackId, double newRating) async {
    setState(() {
      ratings[trackId] = newRating;
      calculateAverageRating();
    });

    // Guardar el nuevo rating automáticamente
    await UserData.saveRating(widget.album['collectionId'], trackId, newRating);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album['collectionName']),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Image.network(
                  widget.album['artworkUrl100']
                      .replaceAll('100x100', '600x600'),
                  width: 300,
                  height: 300,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Icon(Icons.album, size: 300),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Artist: ",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text("${widget.album['artistName']}"),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Album: ",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text("${widget.album['collectionName']}"),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Release Date: ",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                            "${DateTime.parse(widget.album['releaseDate']).toString().substring(0, 10).split('-').reversed.join('-')}"),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Rating: ${averageRating.toStringAsFixed(2)}",
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveInHistory,
                child: Text(
                  'Save Album', // Cambio de texto
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                      ? AppTheme.darkTheme.colorScheme.primary
                      : AppTheme.lightTheme.colorScheme.primary,
                ),
              ),
              Divider(),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Track No.')),
                    DataColumn(label: Text('Title')),
                    DataColumn(label: Text('Length')),
                    DataColumn(
                        label: Text('Rating', textAlign: TextAlign.center)),
                  ],
                  rows: tracks.map((track) => DataRow(
                    cells: [
                      DataCell(Text(track['trackNumber'].toString())),
                      DataCell(Text(track['trackName'])),
                      DataCell(Text(formatDuration(track['trackTimeMillis']))),
                      DataCell(Container(
                        width: 150,
                        child: Row(
                          children: [
                            Expanded(
                              child: Slider(
                                min: 0,
                                max: 10,
                                divisions: 10,
                                value: ratings[track['trackId']] ?? 0.0,
                                onChanged: (newRating) {
                                  _updateRating(track['trackId'], newRating);
                                },
                              ),
                            ),
                            Text((ratings[track['trackId']] ?? 0.0)
                                .toStringAsFixed(0)),
                          ],
                        ),
                      )),
                    ],
                  )).toList(),
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _launchRateYourMusic,
                child: Text(
                  'RateYourMusic.com',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                      ? AppTheme.darkTheme.colorScheme.primary
                      : AppTheme.lightTheme.colorScheme.primary,
                ),
              ),
              SizedBox(height: 20),
              SizedBox(height: 100), // Add additional space to prevent overflow
            ],
          ),
        ),
      ),
      bottomNavigationBar: Footer(),
    );
  }

  String formatDuration(int millis) {
    int seconds = (millis ~/ 1000) % 60;
    int minutes = (millis ~/ 1000) ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}