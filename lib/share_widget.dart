import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';

class ShareWidget extends StatefulWidget {
  final Map<String, dynamic>? album;  // Make optional
  final List<dynamic>? tracks;
  final Map<int, double>? ratings;
  final double? averageRating;
  final String? title;  // New: for custom title
  final List<Map<String, dynamic>>? albums;  // New: for collections

  static final GlobalKey<_ShareWidgetState> shareKey = GlobalKey();

  const ShareWidget({
    super.key,
    this.album,
    this.tracks,
    this.ratings,
    this.averageRating,
    this.title,
    this.albums,
  }) : assert(
          (album != null && tracks != null && ratings != null && averageRating != null) ||
          (title != null && albums != null),
          'Must provide either album details or collection details'
        );

  @override
  State<ShareWidget> createState() => _ShareWidgetState();
}

class _ShareWidgetState extends State<ShareWidget> {
  final _boundaryKey = GlobalKey();

  // Method to be called from outside
  Future<String> saveAsImage() async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = widget.album?['collectionName']
          ?.toString()
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_') ?? 'album';
      final fileName = 'RateMe_${safeName}_$timestamp.png';

      // On Android, save directly to Downloads
      if (Platform.isAndroid) {
        final downloadPath = '/storage/emulated/0/Download';
        final filePath = '$downloadPath/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(pngBytes);
        
        // Force MediaStore update to make it visible immediately
        await File(filePath).setLastModified(DateTime.now());
        
        return filePath;
      } else {
        // For desktop and other platforms, use FilePicker
        final String? savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save image as',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['png'],
        );

        if (savePath != null) {
          final file = File(savePath);
          await file.writeAsBytes(pngBytes);
          return file.path;
        }
      }
      
      throw Exception('Failed to save image');
    } catch (e) {
      rethrow;
    }
  }

  Future<String> _getDocumentsPath() async {
    if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();
      return directory?.path ?? (await getApplicationDocumentsDirectory()).path;
    } else if (Platform.isWindows) {
      return path.join(Platform.environment['USERPROFILE'] ?? '', 'Documents');
    } else if (Platform.isMacOS) {
      return path.join(Platform.environment['HOME'] ?? '', 'Documents');
    } else {
      return path.join(Platform.environment['HOME'] ?? '', 'Documents');
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
      key: _boundaryKey,
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.all(16),
        child: widget.albums != null 
            ? _buildCollectionView() 
            : _buildAlbumView(),
      ),
    );
  }

  Widget _buildCollectionView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.title!,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Divider(),
        ...widget.albums!.map((album) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Image.network(
                album['artworkUrl100'],
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
        )).toList(),
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
              widget.album!['artworkUrl100'],
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
                    widget.album!['collectionName'],
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    widget.album!['artistName'],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Average Rating: ${widget.averageRating!.toStringAsFixed(1)}',
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
        // Track list
        ...widget.tracks!.map((track) {
          final trackId = track['trackId'];
          final rating = widget.ratings![trackId] ?? 0.0;
          final duration = track['duration'] ?? track['trackTimeMillis'] ?? 0;
          
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                // Track number
                SizedBox(
                  width: 30,
                  child: Text(
                    track['trackNumber'].toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                // Title
                Expanded(
                  child: Text(
                    track['title'] ?? track['trackName'] ?? 'Unknown Track',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Duration
                SizedBox(
                  width: 70, // Fixed width for duration to align ratings
                  child: Text(
                    formatDuration(duration),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 16),
                // Rating
                SizedBox(
                  width: 40,
                  child: Text(
                    rating.toStringAsFixed(1),
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
        }),
      ],
    );
  }
}
