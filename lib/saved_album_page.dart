import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:html/parser.dart' show parse;
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'user_data.dart';
import 'logging.dart';
import 'share_widget.dart';
import 'custom_lists_page.dart';

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
    // Initialize in sequence
    _initialize();
  }

  Future<void> _initialize() async {
    // 1. Load ratings first 
    await _loadRatings();
    // 2. Then load tracks based on source
    if (widget.isBandcamp) {
      await _fetchBandcampTracks();
    } else {
      await _fetchItunesTracks();
    }
  }

  Future<void> _loadRatings() async {
    try {
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
    } catch (e) {
      Logging.severe('Error loading ratings', e);
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
        var ldJsonScript = document.querySelector('script[type="application/ld+json"]');
        
        if (ldJsonScript != null) {
          final ldJson = jsonDecode(ldJsonScript.text);
          
          if (ldJson != null && ldJson['track'] != null && ldJson['track']['itemListElement'] != null) {
            List<Map<String, dynamic>> tracksData = [];
            var trackItems = ldJson['track']['itemListElement'] as List;

            final albumId = widget.album['collectionId'];
            final savedRatings = await UserData.getSavedAlbumRatings(albumId);
            
            for (int i = 0; i < trackItems.length; i++) {
              var item = trackItems[i];
              var track = item['item'];

              var props = track['additionalProperty'] as List;
              var trackIdProp = props.firstWhere(
                (p) => p['name'] == 'track_id',
                orElse: () => {'value': 0}
              );
              int trackId = trackIdProp['value'];

              String duration = track['duration'] ?? '';
              int durationMillis = _parseDuration(duration);

              tracksData.add({
                'trackId': trackId,
                'trackNumber': i + 1,
                'title': track['name'],
                'duration': durationMillis,
              });

              var savedRating = savedRatings.firstWhere(
                (r) => r['trackId'] == trackId,
                orElse: () => {'rating': 0.0},
              );
              
              if (savedRating != null) {
                ratings[trackId] = savedRating['rating'].toDouble();
              }
            }

            if (mounted) {
              setState(() {
                tracks = tracksData;
                try {
                  String dateStr = ldJson['datePublished'];
                  releaseDate = DateFormat("d MMMM yyyy HH:mm:ss 'GMT'").parse(dateStr);
                } catch (e) {
                  try {
                    releaseDate = DateTime.parse(ldJson['datePublished'].replaceAll(' GMT', 'Z'));
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
      if (mounted) setState(() => isLoading = false);
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
      // Use external application to show browser chooser
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error, stackTrace) {
      Logging.severe('Error launching RateYourMusic', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open RateYourMusic')),
        );
      }
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
          SizedBox(
            width: 25, // Fixed width for rating number
            child: Text(
              (ratings[trackId] ?? 0).toStringAsFixed(0), // Remove decimal places
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.end,
            ),
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
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.playlist_add, color: Colors.white),
                              label: const Text('Manage Lists', style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                minimumSize: const Size(150, 45),
                              ),
                              onPressed: () => _showAddToListDialog(context),
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
                      columnSpacing: 12,  // Reduce spacing between columns
                      headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
                      columns: [
                        DataColumn(
                          label: SizedBox(
                            width: 35,  // Reducido de 40
                            child: Center(child: Text('No.')),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text('Title'),
                          // Default alignment (left)
                        ),
                        DataColumn(
                          label: Container(
                            width: 70,
                            alignment: Alignment.center,  // Asegura alineación central
                            child: Text('Length', textAlign: TextAlign.center),
                          ),
                        ),
                        DataColumn(
                          label: Container(
                            width: 175,
                            alignment: Alignment.center,  // Asegura alineación central
                            child: Text('Rating', textAlign: TextAlign.center),
                          ),
                        ),
                      ],
                      rows: tracks.map((track) {
                        final trackId = track['trackId'] ?? 0;
                        final duration = widget.isBandcamp 
                            ? track['duration'] ?? 0
                            : track['trackTimeMillis'] ?? 0;
                        return DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 35,  // Reducido de 40
                                child: Center(
                                  child: Text(track['trackNumber']?.toString() ?? ''),
                                ),
                              ),
                            ),
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
                            DataCell(
                              SizedBox(
                                width: 70,
                                child: Text(
                                  formatDuration(duration),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
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

  Future<void> _showAddToListDialog(BuildContext context) async {
    // Key to force FutureBuilder update
    var refreshKey = ValueKey(DateTime.now());
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(  // Wrap in StatefulBuilder
        builder: (context, setState) => AlertDialog(
          title: const Text('Manage Lists'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Create New List'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showCreateListDialog();
                },
              ),
              const Divider(),
              FutureBuilder<List<CustomList>>(
                key: refreshKey,  // Use key to force rebuild
                future: UserData.getCustomLists(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  final lists = snapshot.data!;
                  return SizedBox(
                    height: 300,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: lists.map((CustomList list) {
                          final isInList = list.albumIds.contains(widget.album['collectionId'].toString());
                          return CheckboxListTile(
                            title: Text(list.name),
                            subtitle: Text('${list.albumIds.length} albums'),
                            value: isInList,
                            onChanged: (bool? value) async {
                              if (value == true) {
                                list.albumIds.add(widget.album['collectionId'].toString());
                              } else {
                                list.albumIds.remove(widget.album['collectionId'].toString());
                              }
                              await UserData.saveCustomList(list);
                              
                              // Update UI immediately
                              setState(() {
                                refreshKey = ValueKey(DateTime.now());
                              });

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(value == true 
                                      ? 'Added to "${list.name}"' 
                                      : 'Removed from "${list.name}"'
                                    ),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateListDialog() async {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to new list')),
        );
      }
    }
  }

  Future<void> _addToExistingList(String listId) async {
    final lists = await UserData.getCustomLists();
    final selectedList = lists.firstWhere((list) => list.id == listId);
    if (!selectedList.albumIds.contains(widget.album['collectionId'].toString())) {
      selectedList.albumIds.add(widget.album['collectionId'].toString());
      await UserData.saveCustomList(selectedList);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added to "${selectedList.name}"')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Already in "${selectedList.name}"')),
        );
      }
    }
  }

  void _showOptionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Album Options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('Import Album'),
              onTap: () async {
                Navigator.pop(context);
                final album = await UserData.importAlbum(context);
                if (album != null && mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SavedAlbumPage(
                        album: album,
                        isBandcamp: album['url']?.toString().contains('bandcamp.com') ?? false,
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('Export Album'),
              onTap: () async {
                Navigator.pop(context);
                await UserData.exportAlbum(context, widget.album);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share as Image'),
              onTap: () => _showShareDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showShareDialog(BuildContext context) {
    Navigator.pop(context);  // Close options dialog
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
          content: SingleChildScrollView(child: shareWidget),
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
                    if (!mounted) return;
                    
                    if (Platform.isAndroid) {
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
                                      // Copy from temp to Downloads
                                      await File(path).copy(newPath);
                                      
                                      // Scan file with MediaScanner
                                      const platform = MethodChannel('com.example.rateme/media_scanner');
                                      try {
                                        await platform.invokeMethod('scanFile', {'path': newPath});
                                      } catch (e) {
                                        print('MediaScanner error: $e');
                                      }
                                      
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
                                    try {
                                      await Share.shareXFiles([XFile(path)]);
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error sharing: $e')),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Image saved to: $path')),
                      );
                    }
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
              child: Text(Platform.isAndroid ? 'Save & Share' : 'Save Image'),
            ),
          ],
        );
      },
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
