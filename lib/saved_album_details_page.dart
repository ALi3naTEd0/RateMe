import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'footer.dart';
import 'app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'user_data.dart';

class SavedAlbumDetailsPage extends StatefulWidget {
  final dynamic album;

  SavedAlbumDetailsPage({Key? key, required this.album}) : super(key: key);

  @override
  _SavedAlbumDetailsPageState createState() => _SavedAlbumDetailsPageState();
}

class _SavedAlbumDetailsPageState extends State<SavedAlbumDetailsPage> {
  List<dynamic> tracks = [];
  double averageRating = 0.0;
  int albumDurationMillis = 0;
  late Map<int, double> ratings;

  @override
  void initState() {
    super.initState();
    _fetchTracks();
    ratings = {};
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
        calculateAlbumDuration();
      });
      _loadSavedRatings(); // Cargar las calificaciones después de establecer las pistas
    } catch (error) {
      print('Error fetching tracks: $error');
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

  void _loadSavedRatings() async {
    List<Map<String, dynamic>> savedRatings =
        await UserData.getSavedAlbumRatings(widget.album['collectionId']);
    print('Saved Ratings: $savedRatings');
    setState(() {
      for (var rating in savedRatings) {
        ratings[rating['trackId']] = rating['rating'];
      }
      calculateAverageRating();
    });
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

  void _updateRating(int trackId, double newRating) async {
    await UserData.saveRating(widget.album['collectionId'], trackId, newRating);
    // Recargar las calificaciones después de actualizar
    _loadSavedRatings();
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
                                value: _getRating(track['trackId']),
                                onChanged: (newRating) {
                                  _updateRating(track['trackId'], newRating);
                                },
                              ),
                            ),
                            Text(_getRating(track['trackId'])
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
                onPressed: () {},
                child: Text(
                  'Update Rating',
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

  double _getRating(int trackId) {
    // Obtener la calificación del trackId de las calificaciones cargadas
    var savedRating = ratings[trackId] ?? 0.0;
    return savedRating.toDouble();
  }

  String formatDuration(int? milliseconds) {
    if (milliseconds == null || milliseconds == 0) return '';
    int seconds = (milliseconds / 1000).truncate();
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
