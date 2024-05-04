import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'footer.dart';

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
    final url = Uri.parse('https://itunes.apple.com/lookup?id=${widget.album['collectionId']}&entity=song');
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    var trackList = data['results'].where((track) => track['wrapperType'] == 'track').toList();
    setState(() {
      tracks = trackList;
      trackList.forEach((track) => ratings[track['trackId']] = 0.0);
      calculateAverageRating();
      calculateAlbumDuration();
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
                    Text("Duration: ${formatDuration(albumDurationMillis)}"),
                  ],
                ),
              ),
              SizedBox(height: 20),
              Text("Rating: ${averageRating.toStringAsFixed(1)}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Divider(),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Track No.')),
                    DataColumn(label: Text('Title')),
                    DataColumn(label: Text('Length')),
                    DataColumn(label: Text('Rating', textAlign: TextAlign.center)), // Centra el encabezado
                  ],
                  rows: tracks.map((track) => DataRow(
                    cells: [
                      DataCell(Text(track['trackNumber'].toString())),
                      DataCell(Text(track['trackName'])),
                      DataCell(Text(formatDuration(track['trackTimeMillis']))),
                      DataCell(Container( // Contenedor para personalizar la posición del slider y el valor de la calificación
                        width: 150, // Ancho del contenedor para evitar que el texto se desborde
                        child: Row(
                          children: [
                            Expanded( // Ajusta el slider para ocupar el espacio restante
                              child: Slider(
                                min: 0,
                                max: 10,
                                divisions: 10,
                                value: ratings[track['trackId']] ?? 0.0,
                                onChanged: (newRating) {
                                  setState(() {
                                    ratings[track['trackId']] = newRating;
                                    calculateAverageRating();
                                  });
                                },
                              ),
                            ),
                            Text((ratings[track['trackId']] ?? 0.0).toStringAsFixed(0)), // Valor de la calificación a la derecha del slider
                          ],
                        ),
                      )),
                    ],
                  )).toList(),
                ),
              ),
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