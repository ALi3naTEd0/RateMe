import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'bandcamp_parser.dart';
import 'footer.dart';
import 'app_theme.dart';
import 'user_data.dart';

class BandcampDetailsPage extends StatefulWidget {
  final dynamic album;

  const BandcampDetailsPage({super.key, required this.album});

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

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = parse(response.body);
        final tracksData = BandcampParser.extractTracks(document);
        final releaseDateData = BandcampParser.extractReleaseDate(document);

        for (var track in tracksData) {
          final trackId = track['trackId'];
          if (trackId != null) {
            ratings[trackId] = 0.0;
          }
        }

        setState(() {
          tracks = tracksData;
          releaseDate = releaseDateData;
          isLoading = false;
          calculateAlbumDuration();
        });
      } else {
        throw Exception('Failed to load album page');
      }
    } catch (error, st) {
      print('Error fetching tracks: $error $st');
      setState(() {
        isLoading = false;
      });
    }
  }

  void _loadRatings() async {
    int albumId =
        widget.album['collectionId'] ?? DateTime.now().millisecondsSinceEpoch;
    List<Map<String, dynamic>> savedRatings =
        await UserData.getSavedAlbumRatings(albumId);
    Map<int, double> ratingsMap = {};
    for (var rating in savedRatings) {
      int trackId = rating['trackId'];
      double ratingValue = rating['rating'];
      ratingsMap[trackId] = ratingValue;
    }

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
    for (var track in tracks) {
      totalDuration += track['duration'] as int;
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

  void _updateRating(int trackId, double newRating) async {
    setState(() {
      ratings[trackId] = newRating;
      calculateAverageRating();
    });

    int albumId =
        widget.album['collectionId'] ?? DateTime.now().millisecondsSinceEpoch;
    await UserData.saveRating(albumId, trackId, newRating);
    print('Updated rating for trackId $trackId: $newRating');
  }

  void _printSavedIds(int collectionId, List<int> trackIds) {
    print('Saved album information:');
    print('CollectionId: $collectionId');
    print('TrackIds: $trackIds');
  }

  void _saveAlbum() async {
    await UserData.saveAlbum(widget.album); // Wait for album to be saved
    List<int> trackIds =
        tracks.map((track) => track['trackId'] ?? 0).cast<int>().toList();
    _printSavedIds(
        widget.album['collectionId'] ?? DateTime.now().millisecondsSinceEpoch,
        trackIds);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
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
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
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

  String _formatReleaseDate(DateTime? date) {
    if (date == null) return 'Unknown Date';
    return DateFormat('d MMMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    double titleWidthFactor = _calculateTitleWidth();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album['collectionName'] ?? 'Unknown Album'),
      ),
      body: Center(
        child: isLoading
            ? const CircularProgressIndicator()
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),
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
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Text(widget.album['artistName'] ??
                                  'Unknown Artist'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Album: ",
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Text(widget.album['collectionName'] ??
                                  'Unknown Album'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Release Date: ",
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Text(_formatReleaseDate(releaseDate)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Duration: ",
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Text(formatDuration(albumDurationMillis)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Rating: ",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20)),
                              Text(averageRating.toStringAsFixed(2),
                                  style: const TextStyle(fontSize: 20)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _saveAlbum,
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
                          DataColumn(
                            label:
                                Text('Track No.', textAlign: TextAlign.center),
                          ),
                          DataColumn(
                            label: Text('Title', textAlign: TextAlign.center),
                          ),
                          DataColumn(
                            label: Text('Length', textAlign: TextAlign.center),
                          ),
                          DataColumn(
                            label: Text('Rating', textAlign: TextAlign.center),
                          ),
                        ],
                        rows: tracks.map((track) {
                          final trackId = track['trackId'] ?? 0;
                          return DataRow(
                            cells: [
                              DataCell(
                                Center(
                                  child: Text(track['trackNumber'].toString()),
                                ),
                              ),
                              DataCell(
                                Tooltip(
                                  message: track['title'] ?? '',
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                              titleWidthFactor,
                                    ),
                                    child: Text(
                                      track['title'] ?? '',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Center(
                                  child: Text(
                                      formatDuration(track['duration'] ?? 0)),
                                ),
                              ),
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
                                            label: ratings[trackId]
                                                ?.toStringAsFixed(0),
                                            onChanged: (newRating) {
                                              _updateRating(trackId, newRating);
                                            },
                                          ),
                                        ),
                                        Text(
                                          ratings[trackId]
                                                  ?.toStringAsFixed(0) ??
                                              '0',
                                          style: const TextStyle(fontSize: 16),
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
                        'Rate on RateYourMusic',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Footer(),
                  ],
                ),
              ),
      ),
    );
  }
}
