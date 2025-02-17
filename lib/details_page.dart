import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'user_data.dart';
import 'logging.dart';
import 'main.dart';  // Agregamos import para usar BandcampService

class DetailsPage extends StatefulWidget {
  final dynamic album;
  final bool isBandcamp;

  const DetailsPage({
    super.key, 
    required this.album,
    this.isBandcamp = true,
  });

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  List<dynamic> tracks = [];
  Map<int, double> ratings = {};
  double averageRating = 0.0;
  int albumDurationMillis = 0;
  bool isLoading = true;
  DateTime? releaseDate;

  @override
  void initState() {
    super.initState();
    widget.isBandcamp ? _fetchBandcampTracks() : _fetchItunesTracks();
    _loadRatings();
  }

  Future<void> _loadRatings() async {
    int albumId = widget.album['collectionId'] ?? DateTime.now().millisecondsSinceEpoch;
    List<Map<String, dynamic>> savedRatings = await UserData.getSavedAlbumRatings(albumId);
    Map<int, double> ratingsMap = {};
    for (var rating in savedRatings) {
      ratingsMap[rating['trackId']] = rating['rating'];
    }

    if (mounted) {
      setState(() {
        ratings = ratingsMap;
        calculateAverageRating();
      });
    }
  }

  Future<void> _fetchBandcampTracks() async {
    final url = widget.album['url'];
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = parse(response.body);
        final tracksData = BandcampService.extractTracks(document);
        final releaseDateData = BandcampService.extractReleaseDate(document);

        for (var track in tracksData) {
          final trackId = track['trackId'];
          if (trackId != null) {
            ratings[trackId] = 0.0;
          }
        }

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
          trackList.forEach((track) => ratings[track['trackId']] = 0.0);
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

  void _updateRating(int trackId, double newRating) async {
    setState(() {
      ratings[trackId] = newRating;
      calculateAverageRating();
    });

    int albumId = widget.album['collectionId'] ?? DateTime.now().millisecondsSinceEpoch;
    await UserData.saveRating(albumId, trackId, newRating);
    Logging.info('Updated rating for trackId $trackId', null, null);
  }

  void _saveAlbum() async {
    await UserData.saveAlbum(widget.album);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Album saved successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    }
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

  String _formatReleaseDate() {
    if (widget.isBandcamp) {
      if (releaseDate == null) return 'Unknown Date';
      return DateFormat('d MMMM yyyy').format(releaseDate!);
    } else {
      return DateFormat('d MMMM yyyy').format(DateTime.parse(widget.album['releaseDate']));
    }
  }

  @override
  Widget build(BuildContext context) {
    double titleWidthFactor = _calculateTitleWidth();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album['collectionName'] ?? 'Unknown Album'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.only(bottom: 40.0, top: 16.0),
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - 
                           AppBar().preferredSize.height -
                           MediaQuery.of(context).padding.top,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Album Artwork
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

                    // Album Info
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildInfoRow("Artist", widget.album['artistName'] ?? 'Unknown Artist'),
                          _buildInfoRow("Album", widget.album['collectionName'] ?? 'Unknown Album'),
                          _buildInfoRow("Release Date", _formatReleaseDate()),
                          _buildInfoRow("Duration", formatDuration(albumDurationMillis)),
                          _buildInfoRow("Rating", averageRating.toStringAsFixed(2), fontSize: 20),
                        ],
                      ),
                    ),

                    // Save Button
                    ElevatedButton(
                      onPressed: _saveAlbum,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: const Text('Save Album', style: TextStyle(color: Colors.white)),
                    ),

                    const Divider(height: 40),

                    // Tracks Table
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
                              DataCell(Text(track['trackNumber'].toString())),
                              DataCell(
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * titleWidthFactor,
                                  ),
                                  child: Text(
                                    widget.isBandcamp ? track['title'] : track['trackName'],
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text(formatDuration(duration))),
                              DataCell(_buildRatingSlider(trackId)),
                            ],
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // RateYourMusic Button
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

                    const SizedBox(height: 40), // Consistent bottom padding
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, String value, {double fontSize = 16}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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

  Widget _buildRatingSlider(int trackId) {
    return SizedBox(
      width: 150,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: ratings[trackId] ?? 0.0,
              min: 0,
              max: 10,
              divisions: 10,
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
}
