import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

class ShareWidget extends StatefulWidget {
  static final GlobalKey<ShareWidgetState> shareKey =
      GlobalKey<ShareWidgetState>();
  static final GlobalKey _boundaryKey = GlobalKey(); // Add static boundary key

  final Map<String, dynamic> album;
  final List<dynamic>? tracks;
  final Map<String, dynamic>? ratings;
  final double? averageRating;
  final String? title;
  final List<Map<String, dynamic>>? albums;

  const ShareWidget({
    super.key, // Convert to super parameter
    required this.album,
    this.tracks,
    this.ratings,
    this.averageRating,
    this.title,
    this.albums,
  });

  @override
  State<ShareWidget> createState() => ShareWidgetState();
}

class ShareWidgetState extends State<ShareWidget> {
  Future<String?> saveAsImage() async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));

      final boundary = ShareWidget._boundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception('Could not find boundary widget');
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('Could not generate image data');
      }

      final pngBytes = byteData.buffer.asUint8List();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'RateMe_album_$timestamp.png';

      if (Platform.isAndroid) {
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/$fileName';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(pngBytes);
        return tempPath;
      } else {
        // For desktop platforms, use file picker
        final String? savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save image as',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['png'],
          lockParentWindow: true,
        );

        if (savePath != null) {
          final file = File(savePath);
          await file.writeAsBytes(pngBytes);
          return savePath;
        }
        return null;
      }
    } catch (e) {
      debugPrint('Error saving image: $e');
      return null;
    }
  }

  String formatDuration(int millis) {
    int seconds = (millis ~/ 1000) % 60;
    int minutes = (millis ~/ 1000) ~/ 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: ShareWidget._boundaryKey, // Use the static boundary key
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.all(16),
        child:
            widget.albums != null ? _buildCollectionView() : _buildAlbumView(),
      ),
    );
  }

  Widget _buildCollectionView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.title != null)
          Text(
            widget.title!,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        const Divider(),
        if (widget.albums != null)
          ...widget.albums!.map((album) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Image.network(
                      album['artworkUrl100'] ?? '',
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.album, size: 60),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album['collectionName'] ?? 'Unknown Album',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(album['artistName'] ?? 'Unknown Artist'),
                          Text(
                            'Rating: ${(album['averageRating'] ?? 0.0).toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildAlbumView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Album header
        Row(
          children: [
            Image.network(
              widget.album['artworkUrl100'] ?? '',
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.album, size: 100),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.album['collectionName'] ?? 'Unknown Album',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    widget.album['artistName'] ?? 'Unknown Artist',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Average Rating: ${widget.averageRating?.toStringAsFixed(1) ?? 'N/A'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 32),

        // Track list with improved error handling
        ...widget.tracks?.map((track) {
              // Safely get the track ID as string for ratings lookup
              String trackIdStr = track.id.toString();

              // Debug the actual value in the ratings map
              var rawValue = widget.ratings?[trackIdStr];
              debugPrint(
                  "Raw rating value for track $trackIdStr: $rawValue (type: ${rawValue?.runtimeType})");

              // Try to extract the actual integer rating without any rounding
              int rating = 0;

              // Handle different possible formats of rating data
              if (rawValue is int) {
                rating = rawValue;
              } else if (rawValue is double) {
                // Use floor to avoid rounding up
                rating = rawValue.round();
              } else if (rawValue is String) {
                // Try parsing as a number if it's stored as a string
                rating = int.tryParse(rawValue) ?? 0;
              }

              debugPrint(
                  "Final displayed rating for track $trackIdStr: $rating");

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    // Track number
                    SizedBox(
                      width: 30,
                      child: Text(
                        track.position.toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    // Title
                    Expanded(
                      child: Text(
                        track.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Duration
                    SizedBox(
                      width: 70,
                      child: Text(
                        formatDuration(track.durationMs),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Rating
                    SizedBox(
                      width: 40,
                      child: Text(
                        rating.toString(), // Display rating as an integer
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: rating > 0
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          fontWeight:
                              rating > 0 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }) ??
            [],
      ],
    );
  }
}
