import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'footer.dart';
import 'app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'user_data.dart';
import 'package:intl/intl.dart';
import 'logging.dart';

class SavedAlbumDetailsPage extends StatefulWidget {
  final dynamic album;

  const SavedAlbumDetailsPage({super.key, required this.album});

  @override
  _SavedAlbumDetailsPageState createState() => _SavedAlbumDetailsPageState();
}

class _SavedAlbumDetailsPageState extends State<SavedAlbumDetailsPage> {
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
        calculateAlbumDuration();
        _loadSavedRatings(); // Call _loadSavedRatings method here
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

  void _loadSavedRatings() async {
    // Implement loading saved ratings logic here
    List<Map<String, dynamic>> savedRatings =
        await UserData.getSavedAlbumRatings(widget.album['collectionId']);
    setState(() {
      for (var rating in savedRatings) {
        ratings[rating['trackId']] = rating['rating'];
      }
      calculateAverageRating(); // Calculate average rating after loading saved ratings
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
                                        label: (ratings[track['trackId']] ?? 0.0).toStringAsFixed(0), // Agregado
                                        onChanged: (newRating) {
                                          _updateRating(track['trackId'], newRating);
                                        },
                                      ),
                                    ),
                                    Text(
                                      (ratings[track['trackId']] ?? 0.0).toStringAsFixed(0),
                                      style: const TextStyle(fontSize: 16), // Opcional para mantener consistencia
                                    ),
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
              const SizedBox(height: 100),
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

  void _updateRating(int trackId, double newRating) async {
    if (mounted) {
      setState(() {
        ratings[trackId] = newRating;
        calculateAverageRating();
      });
    }

    int albumId =
        widget.album['collectionId'] ?? DateTime.now().millisecondsSinceEpoch;
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
