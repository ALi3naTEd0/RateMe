import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'user_data.dart';

class ExportService {
  static Future<void> exportData() async {
    // Request storage permissions
    final status = await Permission.storage.request();

    if (!status.isGranted) {
      throw Exception('Storage permission not granted');
    }

    // Fetch saved albums and ratings
    List<Map<String, dynamic>> savedAlbums = await UserData.getSavedAlbums();
    List<List<dynamic>> rows = [];

    // Add headers
    rows.add(['Collection ID', 'Collection Name', 'Artist Name', 'Average Rating']);

    for (var album in savedAlbums) {
      List<Map<String, dynamic>> ratings = await UserData.getSavedAlbumRatings(album['collectionId']);
      double averageRating = ratings.isNotEmpty
          ? ratings.map((rating) => rating['rating']).reduce((a, b) => a + b) / ratings.length
          : 0.0;
      rows.add([
        album['collectionId'],
        album['collectionName'],
        album['artistName'],
        averageRating.toStringAsFixed(2),
      ]);
    }

    // Convert rows to CSV
    String csvData = const ListToCsvConverter().convert(rows);
    final directory = await getExternalStorageDirectory();
    final path = '${directory?.path}/saved_album_ratings.csv';

    // Write CSV data to file
    final file = File(path);
    await file.writeAsString(csvData);

    print('Data exported to $path');
  }
}