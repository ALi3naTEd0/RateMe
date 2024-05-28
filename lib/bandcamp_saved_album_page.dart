import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'footer.dart';
import 'app_theme.dart';
import 'user_data.dart';

class BandcampSavedAlbumPage extends StatefulWidget {
  final dynamic album;

  BandcampSavedAlbumPage({Key? key, required this.album}) : super(key: key);

  @override
  _BandcampSavedAlbumPageState createState() => _BandcampSavedAlbumPageState();
}

class _BandcampSavedAlbumPageState extends State<BandcampSavedAlbumPage> {
  List<Map<String, String>> tracks = [];
  Map<int, double> ratings = {};
  double averageRating = 0.0;
  int albumDurationMillis = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTracksFromBandcamp();
  }

  void _fetchTracksFromBandcamp() async {
    final url = widget.album['url'];
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = parse(response.body);
        final trackElements = document.querySelectorAll('tbody > tr');

        List<Map<String, String>> trackList = trackElements.map((element) {
          final trackNumber = element.querySelector('td.track-number-col')?.text?.trim() ?? '';
          final title = element.querySelector('td.title-col')?.text?.trim() ?? '';
          final duration = element.querySelector('span.time.secondaryText')?.text?.trim() ?? '';

          if (trackNumber.isNotEmpty && title.isNotEmpty && duration.isNotEmpty) {
            return {
              'trackNumber': trackNumber,
              'title': title,
              'duration': duration,
            };
          }
          return null;
        }).where((track) => track != null).cast<Map<String, String>>().toList();

        setState(() {
          tracks = trackList;
          isLoading = false;
          calculateAlbumDuration();
        });
      } else {
        throw Exception('Failed to load album page');
      }
    } catch (error) {
      print('Error fetching tracks: $error');
      setState(() {
        isLoading = false;
      });
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
      final durationParts = track['duration']?.split(':');
      if (durationParts != null && durationParts.length == 2) {
        final minutes = int.parse(durationParts[0]);
        final seconds = int.parse(durationParts[1]);
        totalDuration += (minutes * 60 + seconds) * 1000;
      }
    });
    setState(() {
      albumDurationMillis = totalDuration;
    });
  }

  void _updateRating(int trackIndex, double newRating) async {
    setState(() {
      ratings[trackIndex] = newRating;
      calculateAverageRating();
    });

    // Save the new rating automatically
    await UserData.saveRating(widget.album['collectionId'], trackIndex, newRating);
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

  String formatDuration(int millis) {
    int seconds = (millis ~/ 1000) % 60;
    int minutes = (millis ~/ 1000) ~/ 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album['collectionName'] ?? 'Unknown Album'),
      ),
      body: Center(
        child: isLoading
            ? CircularProgressIndicator()
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.network(
                        widget.album['artworkUrl100']
                                ?.replaceAll('100x100', '600x600') ??
                            '',
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
                              Text(widget.album['artistName'] ?? 'Unknown Artist'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Album: ",
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(widget.album['collectionName'] ?? 'Unknown Album'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Release Date: ",
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(widget.album['releaseDate'] != null
                                  ? DateTime.parse(widget.album['releaseDate'])
                                      .toString()
                                      .substring(0, 10)
                                      .split('-')
                                      .reversed
                                      .join('-')
                                  : 'Unknown Date'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Duration: ",
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(formatDuration(albumDurationMillis)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Rating: ",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 20)),
                              Text(averageRating.toStringAsFixed(2),
                                  style: TextStyle(fontSize: 20)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    Divider(),
                    if (tracks.isNotEmpty) ...[
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
                          rows: tracks.asMap().entries.map((entry) {
                            int index = entry.key;
                            var track = entry.value;
                            return DataRow(cells: [
                              DataCell(Text(track['trackNumber'] ?? '')),
                              DataCell(Text(track['title'] ?? 'Unknown Track')),
                              DataCell(Text(track['duration'] ?? '')),
                              DataCell(Container(
                                width: 150,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Slider(
                                        value: ratings[index] ?? 0.0,
                                        onChanged: (newRating) {
                                          _updateRating(index, newRating);
                                        },
                                        min: 0,
                                        max: 10,
                                        divisions: 10,
                                        label: (ratings[index] ?? 0.0).toStringAsFixed(0),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      (ratings[index] ?? 0.0).toStringAsFixed(0),
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ),
                              )),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ],
                    SizedBox(height: 16),
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
                    SizedBox(height: 16),
                    Footer(),
                  ],
                ),
              ),
      ),
    );
  }
}
