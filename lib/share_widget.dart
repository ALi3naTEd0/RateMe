import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;  // Agregar esta importación

class ShareWidget extends StatefulWidget {
  final Map<String, dynamic> album;
  final List<dynamic> tracks;
  final Map<int, double> ratings;
  final double averageRating;

  // Crear una key estática para poder acceder desde fuera
  static final GlobalKey<_ShareWidgetState> shareKey = GlobalKey<_ShareWidgetState>();

  const ShareWidget({
    super.key,
    required this.album,
    required this.tracks,
    required this.ratings,
    required this.averageRating,
  });

  @override
  State<ShareWidget> createState() => _ShareWidgetState();
}

class _ShareWidgetState extends State<ShareWidget> {
  final _boundaryKey = GlobalKey();

  // Método para ser llamado desde fuera
  Future<String> saveAsImage() async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final documentsPath = await _getDocumentsPath();
      final safeName = widget.album['collectionName']
          .toString()
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Corregir el nombre del archivo removiendo el guion bajo extra
      final file = File(path.join(documentsPath, 'RateMe_${safeName}_${timestamp}.png'));
      await file.writeAsBytes(pngBytes);

      return file.path;
    } catch (e) {
      rethrow;
    }
  }

  Future<String> _getDocumentsPath() async {
    if (Platform.isWindows) {
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabecera del álbum
            Row(
              children: [
                Image.network(
                  widget.album['artworkUrl100'],
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
                        widget.album['collectionName'],
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        widget.album['artistName'],
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Average Rating: ${widget.averageRating.toStringAsFixed(1)}',
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
            // Lista de tracks
            ...widget.tracks.map((track) {
              final trackId = track['trackId'];
              final rating = widget.ratings[trackId] ?? 0.0;
              final duration = track['duration'] ?? track['trackTimeMillis'] ?? 0;
              
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    // Número de track
                    SizedBox(
                      width: 30,
                      child: Text(
                        track['trackNumber'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    // Título
                    Expanded(
                      child: Text(
                        track['title'] ?? track['trackName'] ?? 'Unknown Track',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Duración
                    SizedBox(
                      width:
                          70, // Ancho fijo para la duración para alinear los ratings
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
        ),
      ),
    );
  }
}
