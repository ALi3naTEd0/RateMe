import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import 'user_data.dart';
import 'logging.dart';
import 'main.dart';
import 'custom_lists_page.dart';
import 'share_widget.dart';
import 'package:share_plus/share_plus.dart';

class DetailsPage extends StatefulWidget {
  final dynamic album;
  final bool isBandcamp;
  final Map<int, double>? initialRatings;

  const DetailsPage({
    super.key, 
    required this.album,
    this.isBandcamp = true,
    this.initialRatings,
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
    _initialize();
  }

  Future<void> _initialize() async {
    // Load ratings first
    if (widget.initialRatings != null) {
      ratings = Map.from(widget.initialRatings!);
      calculateAverageRating();
    } else {
      await _loadRatings();
    }

    // Then load tracks
    if (widget.isBandcamp) {
      await _fetchBandcampTracks();
    } else {
      await _fetchItunesTracks();
    }

    // Final update
    if (mounted) {
      setState(() {
        isLoading = false;
        calculateAverageRating();
        calculateAlbumDuration();
      });
    }
  }

  Future<void> _loadRatings() async {
    try {
      int albumId = widget.album['collectionId'] ?? DateTime.now().millisecondsSinceEpoch;
      List<Map<String, dynamic>> savedRatings = await UserData.getSavedAlbumRatings(albumId);
      
      Map<int, double> ratingsMap = {};
      for (var rating in savedRatings) {
        ratingsMap[rating['trackId']] = rating['rating'].toDouble();
      }

      if (mounted) {
        setState(() {
          ratings = ratingsMap;
          calculateAverageRating();
        });
      }
    } catch (e) {
      Logging.severe('Error loading ratings', e);
    }
  }

  Future<void> _fetchBandcampTracks() async {
    final url = widget.album['url'];
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = parse(response.body);
        var ldJsonScript = document.querySelector('script[type="application/ld+json"]');
        
        if (ldJsonScript != null) {
          final ldJson = jsonDecode(ldJsonScript.text);
          
          if (ldJson != null && ldJson['track'] != null) {
            var trackItems = ldJson['track']['itemListElement'] as List;
            List<Map<String, dynamic>> tracksData = [];

            final albumId = widget.album['collectionId'];
            final oldRatingsByPosition = await UserData.migrateAlbumRatings(albumId);
            
            for (int i = 0; i < trackItems.length; i++) {
              var item = trackItems[i];
              var track = item['item'];
              var props = track['additionalProperty'] as List;
              
              var trackIdProp = props.firstWhere(
                (p) => p['name'] == 'track_id',
                orElse: () => {'value': null}
              );
              int trackId = trackIdProp['value'];
              int position = i + 1;

              if (oldRatingsByPosition.containsKey(position)) {
                final oldRating = oldRatingsByPosition[position];
                if (oldRating != null) {
                  double rating = (oldRating['rating'] as num).toDouble();
                  await UserData.saveNewRating(albumId, trackId, position, rating);
                  ratings[trackId] = rating;
                }
              }

              tracksData.add({
                'trackId': trackId,
                'trackNumber': position,
                'title': track['name'],
                'duration': _parseDuration(track['duration']),
                'position': position,
              });
            }

            if (mounted) {
              setState(() {
                tracks = tracksData;
                try {
                  releaseDate = DateFormat("d MMMM yyyy HH:mm:ss 'GMT'")
                      .parse(ldJson['datePublished']);
                } catch (e) {
                  try {
                    releaseDate = DateTime.parse(ldJson['datePublished']);
                  } catch (e) {
                    releaseDate = DateTime.now();
                  }
                }
                isLoading = false;
                calculateAlbumDuration();
                calculateAverageRating();
              });
            }
          }
        }
      }
    } catch (error, stackTrace) {
      Logging.severe('Error fetching Bandcamp tracks', error, stackTrace);
    }
  }

  int _parseDuration(String isoDuration) {
    try {
      if (isoDuration.isEmpty) return 0;

      // Extract numbers between letters using regex
      final regex = RegExp(r'(\d+)(?=[HMS])');
      final matches = regex.allMatches(isoDuration);
      final parts = matches.map((m) => int.parse(m.group(1)!)).toList();

      int totalMillis = 0;
      if (parts.length >= 3) {  // H:M:S
        totalMillis = ((parts[0] * 3600) + (parts[1] * 60) + parts[2]) * 1000;
      } else if (parts.length == 2) {  // M:S
        totalMillis = ((parts[0] * 60) + parts[1]) * 1000;
      } else if (parts.length == 1) {  // S
        totalMillis = parts[0] * 1000;
      }
      return totalMillis;
    } catch (e) {
      Logging.severe('Error parsing duration: $isoDuration - $e');
      return 0;
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

  Widget _buildTrackTitle(String title, double maxWidth) {
    return Tooltip(
      message: title,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          title,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<bool> _verifyAlbumImport(Map<String, dynamic> importedAlbum) async {
    // Normalize strings for comparison
    String currentArtist = widget.album['artistName'].toString().toLowerCase();
    String currentAlbum = widget.album['collectionName'].toString().toLowerCase();
    String importArtist = importedAlbum['artistName'].toString().toLowerCase();
    String importAlbum = importedAlbum['collectionName'].toString().toLowerCase();

    // Check if albums match (case insensitive)
    if (currentArtist == importArtist && currentAlbum == importAlbum) {
      return true;
    }

    // Show warning dialog for different albums
    bool? proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Different Album'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The imported album is different from the current one:'),
            const SizedBox(height: 8),
            Text('Current: ${widget.album['artistName']} - ${widget.album['collectionName']}'),
            Text('Import: ${importedAlbum['artistName']} - ${importedAlbum['collectionName']}'),
            const SizedBox(height: 16),
            const Text('Do you want to switch to the imported album?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Switch Album'),
          ),
        ],
      ),
    );

    return proceed ?? false;
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
                        _buildInfoRow("Release Date", _formatReleaseDate()),
                        _buildInfoRow("Duration", formatDuration(albumDurationMillis)),
                        const SizedBox(height: 8),
                        _buildInfoRow("Rating", averageRating.toStringAsFixed(2), fontSize: 20),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: () async {
                                await UserData.saveAlbum(widget.album);
                                
                                if (!mounted) return;
                                _showAddToListDialog(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                minimumSize: const Size(150, 45),
                              ),
                              child: const Text('Save Album', style: TextStyle(color: Colors.white)),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.more_vert, color: Colors.white),
                              label: const Text('Options', style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                minimumSize: const Size(150, 45),
                              ),
                              onPressed: () => _showOptionsDialog(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
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
                            DataCell(Text(track['trackNumber'].toString())),
                            DataCell(_buildTrackTitle(
                              widget.isBandcamp ? track['title'] : track['trackName'],
                              MediaQuery.of(context).size.width * titleWidthFactor,
                            )),
                            DataCell(Text(formatDuration(duration))),
                            DataCell(_buildRatingSlider(trackId)),
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

  void _showOptionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Album Options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('Import Album'),
              onTap: () async {
                Navigator.pop(dialogContext);
                
                if (!mounted) return;
                final navigationContext = context;
                
                final album = await UserData.importAlbum(context);
                if (album != null && mounted) {
                  // Verify album before importing
                  final shouldProceed = await _verifyAlbumImport(album);
                  if (!shouldProceed) return;

                  final albumId = album['collectionId'];
                  final savedRatings = await UserData.getSavedAlbumRatings(albumId);
                  
                  Map<int, double> ratingsMap = {};
                  for (var rating in savedRatings) {
                    ratingsMap[rating['trackId']] = rating['rating'].toDouble();
                  }
                  
                  if (mounted) {
                    await Navigator.of(navigationContext).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => DetailsPage(
                          album: album,
                          isBandcamp: album['url']?.toString().contains('bandcamp.com') ?? false,
                          initialRatings: ratingsMap,
                        ),
                      ),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('Export Album'),
              onTap: () async {
                Navigator.pop(dialogContext);
                if (!mounted) return;
                await UserData.exportAlbum(context, widget.album);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share as Image'),
              onTap: () => _showShareDialog(dialogContext),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddToListDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to List'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Create New List'),
              onTap: () => Navigator.pop(context, 'new'),
            ),
            const Divider(),
            FutureBuilder<List<CustomList>>(
              future: UserData.getCustomLists(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }
                final lists = snapshot.data!;
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: lists.map((CustomList list) => ListTile(
                      title: Text(list.name),
                      onTap: () => Navigator.pop(context, list.id),
                    )).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ).then((result) async {
      if (result == 'new') {
        final nameController = TextEditingController();
        final descController = TextEditingController();

        final createResult = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Create New List'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'List Name',
                    hintText: 'e.g. Progressive Rock',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'e.g. My favorite prog rock albums',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create'),
              ),
            ],
          ),
        );

        if (createResult == true && nameController.text.isNotEmpty) {
          final newList = CustomList(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: nameController.text,
            description: descController.text,
            albumIds: [widget.album['collectionId'].toString()],
          );
          await UserData.saveCustomList(newList);
        }
      } else if (result != null) {
        final lists = await UserData.getCustomLists();
        final selectedList = lists.firstWhere((list) => list.id == result);
        if (!selectedList.albumIds.contains(widget.album['collectionId'].toString())) {
          selectedList.albumIds.add(widget.album['collectionId'].toString());
          await UserData.saveCustomList(selectedList);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Album added to list successfully')),
        );
      }
    });
  }

  void _handleImageShare(String imagePath) async {
    try {
      await Share.shareXFiles([XFile(imagePath)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing: $e')),
        );
      }
    }
  }

  void _showShareDialog(BuildContext context) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) {
        final shareWidget = ShareWidget(
          key: ShareWidget.shareKey,
          album: widget.album,
          tracks: tracks,
          ratings: ratings,
          averageRating: averageRating,
        );
        return AlertDialog(
          content: SingleChildScrollView(
            child: shareWidget,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  final path = await ShareWidget.shareKey.currentState?.saveAsImage();
                  if (mounted && path != null) {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: context,
                      builder: (BuildContext context) {
                        return SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              ListTile(
                                leading: const Icon(Icons.download),
                                title: const Text('Save to Downloads'),
                                onTap: () async {
                                  Navigator.pop(context);
                                  try {
                                    final downloadDir = Directory('/storage/emulated/0/Download');
                                    final fileName = 'RateMe_${DateTime.now().millisecondsSinceEpoch}.png';
                                    final newPath = '${downloadDir.path}/$fileName';
                                    await File(path).copy(newPath);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Saved to Downloads: $fileName')),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error saving file: $e')),
                                      );
                                    }
                                  }
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.share),
                                title: const Text('Share Image'),
                                onTap: () async {
                                  Navigator.pop(context);
                                  _handleImageShare(path);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error saving image: $e')),
                    );
                  }
                }
              },
              child: const Text('Save & Share'),
            ),
          ],
        );
      },
    );
  }
}
