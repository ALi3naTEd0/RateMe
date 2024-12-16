import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'footer.dart';
import 'app_theme.dart';
import 'user_data.dart';
import 'package:intl/intl.dart';
import 'logging.dart';

class AlbumDetailsPage extends StatefulWidget {
  final dynamic album;

  const AlbumDetailsPage({super.key, required this.album});

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
      var trackList = data['results']
          .where((track) => track['wrapperType'] == 'track')
          .toList();
      setState(() {
        tracks = trackList;
        trackList.forEach((track) => ratings[track['trackId']] = 0.0);
        calculateAverageRating();
        calculateAlbumDuration();
      });
    } catch (error, stackTrace) {
      Logging.severe('Error fetching tracks', error, stackTrace);
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
    for (var track in tracks) {
      if (track['trackTimeMillis'] != null) {
        totalDuration += (track['trackTimeMillis'] ?? 0) as int;
      }
    }
    setState(() {
      albumDurationMillis = totalDuration;
    });
  }

  double _calculateTitleWidth() {
    if (tracks.isEmpty) return 0.4; // Default value if no tracks

    // Adjust the width between 0.2 and 0.5 based on the size of the trackList
    double calculatedWidth =
        (0.5 - (tracks.length / 100).clamp(0.0, 0.4)).toDouble();
    return calculatedWidth.clamp(0.2, 0.5);
  }

  String _formatReleaseDate(String releaseDate) {
    DateTime date = DateTime.parse(releaseDate);
    return DateFormat('d MMMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    double titleWidthFactor = _calculateTitleWidth();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album['collectionName']),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Image.network(
                  widget.album['artworkUrl100']
                      .replaceAll('100x100', '600x600'),
                  width: 300,
                  height: 300,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.album, size: 300),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Artist: ",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text("${widget.album['artistName']}"),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Album: ",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text("${widget.album['collectionName']}"),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Release Date: ",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(_formatReleaseDate(widget.album['releaseDate'])),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Duration: ",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(formatDuration(albumDurationMillis)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Rating: ",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 20)),
                        Text(averageRating.toStringAsFixed(2),
                            style: const TextStyle(fontSize: 20)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveRatings,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkTheme.colorScheme.primary
                          : AppTheme.lightTheme.colorScheme.primary,
                ),
                child: const Text(
                  'Save Album',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const Divider(),
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
                  rows: tracks
                      .map((track) => DataRow(
                            cells: [
                              DataCell(Text(track['trackNumber'].toString())),
                              DataCell(
                                Tooltip(
                                  message: track['trackName'],
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                              titleWidthFactor,
                                    ),
                                    child: Text(
                                      track['trackName'],
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(Text(
                                  formatDuration(track['trackTimeMillis']))),
                              DataCell(SizedBox(
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
                                          _updateRating(
                                              track['trackId'], newRating);
                                        },
                                      ),
                                    ),
                                    Text((ratings[track['trackId']] ?? 0.0)
                                        .toStringAsFixed(0)),
                                  ],
                                ),
                              )),
                            ],
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _launchRateYourMusic,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkTheme.colorScheme.primary
                          : AppTheme.lightTheme.colorScheme.primary,
                ),
                child: const Text(
                  'RateYourMusic.com',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                  height: 100), // Add additional space to prevent overflow
            ],
          ),
        ),
      ),
      bottomNavigationBar: const Footer(),
    );
  }

  String formatDuration(int millis) {
    int seconds = (millis ~/ 1000) % 60;
    int minutes = (millis ~/ 1000) ~/ 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _saveRatings() {
    UserData.saveAlbum(widget.album);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Album saved in history'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _updateRating(int trackId, double newRating) async {
    int albumId =
        widget.album['collectionId'] ?? DateTime.now().millisecondsSinceEpoch;

    setState(() {
      ratings[trackId] = newRating;
      calculateAverageRating();
    });

    await UserData.saveRating(albumId, trackId, newRating);
    Logging.info('Updated rating for trackId $trackId', null, null);
  }

  void _printSavedIds(int collectionId, List<int> trackIds) {
    Logging.info('Saved album information', null, null);
    Logging.info('CollectionId: $collectionId', null, null);
    Logging.info('TrackIds: $trackIds', null, null);
  }

  void _launchRateYourMusic() async {
    final artistName = widget.album['artistName'];
    final albumName = widget.album['collectionName'];
    final url =
        'https://rateyourmusic.com/search?searchterm=${Uri.encodeComponent(artistName)}+${Uri.encodeComponent(albumName)}&searchtype=l';
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        throw 'Could not launch $url';
      }
    } catch (error, stackTrace) {
      Logging.severe('Error launching RateYourMusic', error, stackTrace);
    }
  }
}
