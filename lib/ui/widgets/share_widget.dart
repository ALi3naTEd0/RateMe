import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

class ShareWidget extends StatefulWidget {
  final Map<String, dynamic> album;
  final List<dynamic>? tracks;
  final Map<String, dynamic>? ratings;
  final double? averageRating;
  final String? title;
  final List<Map<String, dynamic>>? albums;
  final Color? selectedDominantColor;

  const ShareWidget({
    super.key,
    required this.album,
    this.tracks,
    this.ratings,
    this.averageRating,
    this.title,
    this.albums,
    this.selectedDominantColor,
  });

  @override
  State<ShareWidget> createState() => ShareWidgetState();
}

class ShareWidgetState extends State<ShareWidget> {
  final GlobalKey _boundaryKey = GlobalKey();

  Future<String?> saveAsImage() async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
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

      String? savedPath;
      if (Platform.isAndroid) {
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/$fileName';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(pngBytes);
        savedPath = tempPath;
      } else {
        final String? savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save image as',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['png'],
        );
        if (savePath != null) {
          final file = File(savePath);
          await file.writeAsBytes(pngBytes);
          savedPath = savePath;
        }
      }

      if (mounted && savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image saved to: $savedPath')),
        );
      }
      return savedPath;
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black;

    return RepaintBoundary(
      key: _boundaryKey,
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.all(16),
        child: widget.albums != null ? _buildCollectionView(textColor) : _buildAlbumView(textColor),
      ),
    );
  }

  Widget _buildCollectionView(Color textColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.title != null)
          Text(
            widget.title!,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: textColor),
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
                            style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                          ),
                          Text(album['artistName'] ?? 'Unknown Artist', style: TextStyle(color: textColor)),
                          Text(
                            'Rating: ${(album['averageRating'] ?? 0.0).toStringAsFixed(2)}',
                            style: TextStyle(
                              color: widget.selectedDominantColor ??
                                  Theme.of(context).colorScheme.primary,
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

  Widget _buildAlbumView(Color textColor) {
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
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: textColor),
                  ),
                  Text(
                    widget.album['artistName'] ?? 'Unknown Artist',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: textColor),
                  ),
                  Text(
                    'Rating: ${widget.averageRating?.toStringAsFixed(1) ?? 'N/A'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: widget.selectedDominantColor ??
                              Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 32),

        // Track list - use selectedDominantColor for rating colors
        ...widget.tracks?.map((track) {
              double rating = 0.0;
              if (track.metadata != null && track.metadata.containsKey('rating')) {
                var metaRating = track.metadata['rating'];
                if (metaRating is num) {
                  rating = metaRating.toDouble();
                }
              } else if (widget.ratings != null) {
                String trackIdStr = track.id.toString();
                var rawValue = widget.ratings![trackIdStr];
                if (rawValue is num) {
                  rating = rawValue.toDouble();
                }
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(
                        track.position.toString(),
                        style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        track.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textColor),
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      child: Text(
                        formatDuration(track.durationMs),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: textColor),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 40,
                      child: Text(
                        rating.toStringAsFixed(0),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: widget.selectedDominantColor ??
                              Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
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