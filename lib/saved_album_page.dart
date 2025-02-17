import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:html/parser.dart' show parse;
import 'user_data.dart';
import 'logging.dart';
import 'main.dart';

class SavedAlbumPage extends StatefulWidget {
  final Map<String, dynamic> album;
  final bool isBandcamp;

  const SavedAlbumPage({
    super.key,
    required this.album,
    required this.isBandcamp,
  });

  @override
  State<SavedAlbumPage> createState() => _SavedAlbumPageState();
}

class _SavedAlbumPageState extends State<SavedAlbumPage> {
  List<dynamic> tracks = [];
  Map<int, double> ratings = {};
  double averageRating = 0.0;
  int albumDurationMillis = 0;
  bool isLoading = true;
  DateTime? releaseDate;

  @override
  void initState() {
    super.initState();
    _loadRatings().then((_) {
      widget.isBandcamp ? _fetchBandcampTracks() : _fetchItunesTracks();
    });
  }

  Future<void> _loadRatings() async {
    final List<Map<String, dynamic>> savedRatings = 
        await UserData.getSavedAlbumRatings(widget.album['collectionId']);
    
    if (mounted) {
      Map<int, double> ratingsMap = {};
      for (var rating in savedRatings) {
        ratingsMap[rating['trackId']] = rating['rating'].toDouble();
      }
      
      setState(() {
        ratings = ratingsMap;
        calculateAverageRating();
      });
    }
  }

  void calculateAverageRating() {
    var ratedTracks = ratings.values.where((rating) => rating > 0).toList();
    if (ratedTracks.isNotEmpty) {
      double total = ratedTracks.reduce((a, b) => a + b);
      if (mounted) {
        setState(() {
          averageRating = total / ratedTracks.length;
          averageRating = double.parse(averageRating.toStringAsFixed(2));
        });
      }
    } else {
      if (mounted) setState(() => averageRating = 0.0);
    }
  }

  void calculateAlbumDuration() {
    int totalDuration = 0;
    if (widget.isBandcamp) {
      for (var track in tracks) {
        totalDuration += track['duration'] as int;
      }
    } else {
      for (var track in tracks) {
        if (track['trackTimeMillis'] != null) {
          totalDuration += track['trackTimeMillis'] as int;
        }
      }
    }
    if (mounted) setState(() => albumDurationMillis = totalDuration);
  }

  Future<void> _fetchBandcampTracks() async {
    final url = widget.album['url'];
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = parse(response.body);
        final tracksData = BandcampService.extractTracks(document);
        final releaseDateData = BandcampService.extractReleaseDate(document);

        if (mounted) {
          setState(() {
            tracks = tracksData;
            releaseDate = releaseDateData;
            isLoading = false;
            calculateAlbumDuration();
          });
        }
      }
    } catch (error, stackTrace) {
      Logging.severe('Error fetching Bandcamp tracks', error, stackTrace);
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchItunesTracks() async {
    try {
      final url = Uri.parse(
          'https://itunes.apple.com/lookup?id=${widget.album['collectionId']}&entity=song');
      final response = await http.get(url);
      final data = jsonDecode(response.body);
      var trackList = data['results']
          .where((track) => track['wrapperType'] == 'track')
          .toList();
      
      if (mounted) {
        setState(() {
          tracks = trackList;
          releaseDate = DateTime.parse(widget.album['releaseDate']);
          isLoading = false;
          calculateAlbumDuration();
        });
      }
    } catch (error, stackTrace) {
      Logging.severe('Error fetching iTunes tracks', error, stackTrace);
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _updateRating(int trackId, double newRating) async {
    setState(() {
      ratings[trackId] = newRating;
      calculateAverageRating();
    });

    int albumId = widget.album['collectionId'];
    await UserData.saveRating(albumId, trackId, newRating);
  }

  Future<void> _launchRateYourMusic() async {
    final artistName = widget.album['artistName'];
    final albumName = widget.album['collectionName'];
    final url = 'https://rateyourmusic.com/search?searchterm=${Uri.encodeComponent(artistName)}+${Uri.encodeComponent(albumName)}&searchtype=l';
    
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

  String formatDuration(int millis) {
    int seconds = (millis ~/ 1000) % 60;
    int minutes = (millis ~/ 1000) ~/ 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  double _calculateTitleWidth() {
    if (tracks.isEmpty) return 0.4;
    return (0.5 - (tracks.length / 100).clamp(0.0, 0.4)).toDouble().clamp(0.2, 0.5);
  }

  Widget _buildTrackSlider(int trackId) {
    return SizedBox(
      width: 150,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              min: 0,
              max: 10,
              divisions: 10,
              value: ratings[trackId] ?? 0.0,
              label: (ratings[trackId] ?? 0.0).toStringAsFixed(0),
              onChanged: (newRating) => _updateRating(trackId, newRating),
            ),
          ),
          Text(
            (ratings[trackId] ?? 0.0).toStringAsFixed(0),
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double titleWidthFactor = _calculateTitleWidth();
    String formattedDate = widget.isBandcamp
        ? releaseDate != null
            ? DateFormat('d MMMM yyyy').format(releaseDate!)
            : 'Unknown Date'
        : DateFormat('d MMMM yyyy').format(DateTime.parse(widget.album['releaseDate']));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album['collectionName'] ?? 'Unknown Album'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Image.network(
                      widget.album['artworkUrl100']?.replaceAll('100x100', '600x600') ?? '',
                      width: 300,
                      height: 300,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.album, size: 300),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildInfoRow("Artist", widget.album['artistName'] ?? 'Unknown Artist'),
                        _buildInfoRow("Album", widget.album['collectionName'] ?? 'Unknown Album'),
                        _buildInfoRow("Release Date", formattedDate),
                        _buildInfoRow("Duration", formatDuration(albumDurationMillis)),
                        const SizedBox(height: 8),
                        _buildInfoRow("Rating", averageRating.toStringAsFixed(2), fontSize: 20),
                      ],
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
                        DataColumn(label: Text('Rating')),
                      ],
                      rows: tracks.map((track) {
                        final trackId = track['trackId'] ?? 0;
                        final duration = widget.isBandcamp 
                            ? track['duration'] ?? 0
                            : track['trackTimeMillis'] ?? 0;
                        
                        return DataRow(
                          cells: [
                            DataCell(Text(track['trackNumber']?.toString() ?? '')),
                            DataCell(
                              Tooltip(
                                message: widget.isBandcamp ? track['title'] : track['trackName'],
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * titleWidthFactor,
                                  ),
                                  child: Text(
                                    widget.isBandcamp ? track['title'] : track['trackName'],
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text(formatDuration(duration))),
                            DataCell(_buildTrackSlider(trackId)),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _launchRateYourMusic,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    child: const Text(
                      'Rate on RateYourMusic',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, String value, {double fontSize = 16}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: label == "Rating" ? 8.0 : 2.0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "$label: ",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize),
          ),
          Text(
            value,
            style: TextStyle(fontSize: fontSize),
          ),
        ],
      ),
    );
  }
}
