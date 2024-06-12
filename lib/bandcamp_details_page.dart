import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'bandcamp_parser.dart';
import 'footer.dart';
import 'app_theme.dart';
import 'user_data.dart';
import 'id_generator.dart';

class BandcampDetailsPage extends StatefulWidget {
  final dynamic album;

  BandcampDetailsPage({Key? key, required this.album}) : super(key: key);

  @override
  _BandcampDetailsPageState createState() => _BandcampDetailsPageState();
}

class _BandcampDetailsPageState extends State<BandcampDetailsPage> {
  List<Map<String, dynamic>> tracks = [];
  Map<int, double> ratings = {};
  double averageRating = 0.0;
  int albumDurationMillis = 0;
  bool isLoading = true;
  DateTime? releaseDate;

  @override
  void initState() {
    super.initState();
    _fetchTracksFromBandcamp();
    _loadRatings();
  }

  void _fetchTracksFromBandcamp() async {
    final url = widget.album['url'];
    final collectionId =
        widget.album['collectionId'] ?? UniqueIdGenerator.generateUniqueCollectionId();

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = parse(response.body);
        final tracksData = BandcampParser.extractTracks(document, collectionId);
        final releaseDateData = BandcampParser.extractReleaseDate(document);

        tracksData.forEach((track) {
          final trackId = track['trackId'];
          if (trackId != null) {
            ratings[trackId] = 0.0;
          }
        });

        setState(() {
          tracks = tracksData;
          releaseDate = releaseDateData;
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

  void _loadRatings() async {
    int albumId = widget.album['collectionId'] ?? UniqueIdGenerator.generateUniqueCollectionId();
    List<Map<String, dynamic>> savedRatings = await UserData.getSavedAlbumRatings(albumId);
    Map<int, double> ratingsMap = {};
    savedRatings.forEach((rating) {
      int trackId = rating['trackId'];
      double ratingValue = rating['rating'];
      ratingsMap[trackId] = ratingValue;
    });

    setState(() {
      ratings = ratingsMap;
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

  void calculateAlbumDuration() {
    int totalDuration = 0;
    tracks.forEach((track) {
      totalDuration += track['duration'] as int;
    });
    setState(() {
      albumDurationMillis = totalDuration;
    });
  }

  void _updateRating(int trackId, double newRating) async {
    setState(() {
      ratings[trackId] = newRating;
      calculateAverageRating();
    });

    int albumId = widget.album['collectionId'] ?? UniqueIdGenerator.generateUniqueCollectionId();
    await UserData.saveRating(albumId, trackId, newRating);
    print('Updated rating for trackId $trackId: $newRating');
  }

  void _printSavedIds(int collectionId, List<int> trackIds) {
    print('Saved album information:');
    print('CollectionId: $collectionId');
    print('TrackIds: $trackIds');
  }

  void _saveAlbum() async {
    await UserData.saveAlbum(widget.album);  // Espera a que el álbum se guarde
    List<int> trackIds = tracks.map((track) => track['trackId'] ?? 0).cast<int>().toList();
    _printSavedIds(widget.album['collectionId'] ?? UniqueIdGenerator.generateUniqueCollectionId(), trackIds);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Album saved in history'),
        duration: Duration(seconds: 2),
      ),
    );
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
                              Text(releaseDate != null
                                  ? DateFormat('dd-MM-yyyy').format(releaseDate!)
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
                    ElevatedButton(
                      onPressed: _saveAlbum,
                      child: Text(
                        'Save Album',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).brightness ==
                                Brightness.dark
                            ? AppTheme.darkTheme.colorScheme.primary
                            : AppTheme.lightTheme.colorScheme.primary,
                      ),
                    ),
                    Divider(),
                    DataTable(
                      columns: const [
                        DataColumn(label: Text('Track No.', textAlign: TextAlign.center)),
                        DataColumn(label: Text('Title', textAlign: TextAlign.left)), // Alineación a la izquierda
                        DataColumn(label: Text('Length', textAlign: TextAlign.center)),
                        DataColumn(label: Text('Rating', textAlign: TextAlign.center)),
                      ],
                      rows: tracks.map((track) {
                        final trackId = track['trackId'] ?? 0;
                        return DataRow(
                          cells: [
                            DataCell(Center(child: Text(track['trackNumber'].toString()))),
                            DataCell(Text(track['title'] ?? '')), // Alineación a la izquierda
                            DataCell(Center(child: Text(formatDuration(track['duration'] ?? 0)))),
                            DataCell(
                              Center(
                                child: SizedBox(
                                  width: 150,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Slider(
                                          value: ratings[trackId] ?? 0.0,
                                          min: 0,
                                          max: 10,
                                          divisions: 10,
                                          label: ratings[trackId]?.toStringAsFixed(0),
                                          onChanged: (newRating) {
                                            _updateRating(trackId, newRating);
                                          },
                                        ),
                                      ),
                                      Text(
                                        ratings[trackId]?.toStringAsFixed(0) ?? '0',
                                        style: TextStyle(fontSize: 16),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _launchRateYourMusic,
                      child: Text(
                        'Rate on RateYourMusic',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).brightness ==
                                Brightness.dark
                            ? AppTheme.darkTheme.colorScheme.primary
                            : AppTheme.lightTheme.colorScheme.primary,
                      ),
                    ),
                    SizedBox(height: 20),
                    Footer(),
                  ],
                ),
              ),
      ),
    );
  }
}
