import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'logging.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'custom_lists_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';  // Add this import for MethodChannel

class UserData {
  // Storage keys for SharedPreferences
  static const String _savedAlbumsKey = 'saved_albums';
  static const String _savedAlbumOrderKey = 'saved_album_order';
  static const String _ratingsPrefix = 'saved_ratings_';
  static const String _customListsKey = 'custom_lists';

  static Future<List<Map<String, dynamic>>> getSavedAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> albumOrder = prefs.getStringList(_savedAlbumOrderKey) ?? [];
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      
      List<Map<String, dynamic>> albums = savedAlbums
          .map((albumJson) => jsonDecode(albumJson) as Map<String, dynamic>)
          .toList();

      albums.sort((a, b) {
        int indexA = albumOrder.indexOf(a['collectionId'].toString());
        int indexB = albumOrder.indexOf(b['collectionId'].toString());
        return indexA.compareTo(indexB);
      });

      return albums;
    } catch (e, stackTrace) {
      Logging.severe('Error getting saved albums', e, stackTrace);
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getSavedAlbumRatings(
      int albumId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String key = '${_ratingsPrefix}$albumId';
      List<String> ratings = prefs.getStringList(key) ?? [];
      return ratings.map((r) => jsonDecode(r) as Map<String, dynamic>).toList();
    } catch (e, stackTrace) {
      Logging.severe('Error getting saved ratings for album $albumId', e, stackTrace);
      return [];
    }
  }

  static Future<void> saveAlbum(Map<String, dynamic> album) async {
    final prefs = await SharedPreferences.getInstance();
    final String albumKey = 'album_${album['collectionId']}';
    
    // Filter and save only audio tracks
    if (album['tracks'] != null) {
      var audioTracks = (album['tracks'] as List).where((track) =>
        track['wrapperType'] == 'track' && track['kind'] == 'song'
      ).toList();
      album['tracks'] = audioTracks;
    }
    
    await prefs.setString(albumKey, jsonEncode(album));
  }

  static Future<void> addToSavedAlbums(Map<String, dynamic> album) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
    List<String> albumOrder = prefs.getStringList(_savedAlbumOrderKey) ?? [];
    
    // Check if album already exists
    bool exists = savedAlbums.any((savedAlbumJson) {
      Map<String, dynamic> savedAlbum = jsonDecode(savedAlbumJson);
      return savedAlbum['collectionId'] == album['collectionId'];
    });

    if (!exists) {
      savedAlbums.add(jsonEncode(album));
      albumOrder.add(album['collectionId'].toString());
      
      await prefs.setStringList(_savedAlbumsKey, savedAlbums);
      await prefs.setStringList(_savedAlbumOrderKey, albumOrder);
    }
  }

  static Future<void> deleteAlbum(Map<String, dynamic> album) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      String albumId = album['collectionId'].toString();
      
      savedAlbums.removeWhere((savedAlbumJson) {
        Map<String, dynamic> savedAlbum = jsonDecode(savedAlbumJson);
        return savedAlbum['collectionId'].toString() == albumId;
      });
      
      await prefs.setStringList(_savedAlbumsKey, savedAlbums);

      List<String> albumOrder = prefs.getStringList(_savedAlbumOrderKey) ?? [];
      albumOrder.remove(albumId);
      await prefs.setStringList(_savedAlbumOrderKey, albumOrder);

      await prefs.remove('${_ratingsPrefix}$albumId');
    } catch (e, stackTrace) {
      Logging.severe('Error deleting album', e, stackTrace);
      rethrow;
    }
  }

  static Future<void> _deleteRatings(int collectionId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_ratings_$collectionId');
  }

  static Future<void> saveAlbumOrder(List<String> albumIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_savedAlbumOrderKey, albumIds);
    } catch (e, stackTrace) {
      Logging.severe('Error saving album order', e, stackTrace);
      rethrow;
    }
  }

  static Future<List<String>> getSavedAlbumOrder() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? albumIds = prefs.getStringList('savedAlbumsOrder');
    return albumIds ?? [];
  }

  static Future<void> saveRating(
      int albumId, int trackId, double rating) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String key = '${_ratingsPrefix}$albumId';
      List<String> ratings = prefs.getStringList(key) ?? [];
      
      Map<String, dynamic> ratingData = {
        'trackId': trackId,
        'rating': rating,
        'timestamp': DateTime.now().toIso8601String(),
      };

      int index = ratings.indexWhere((r) {
        Map<String, dynamic> saved = jsonDecode(r);
        return saved['trackId'] == trackId;
      });

      if (index != -1) {
        ratings[index] = jsonEncode(ratingData);
      } else {
        ratings.add(jsonEncode(ratingData));
      }

      await prefs.setStringList(key, ratings);
    } catch (e, stackTrace) {
      Logging.severe('Error saving rating', e, stackTrace);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> getSavedAlbumById(int albumId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');

    if (savedAlbumsJson != null) {
      for (String json in savedAlbumsJson) {
        Map<String, dynamic> album = jsonDecode(json);

        if (album['collectionId'] == albumId) {
          return album;
        }
      }
    }

    return null;
  }

  static Future<List<int>> getSavedAlbumTrackIds(int collectionId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String key = 'album_track_ids_$collectionId';
    List<String>? trackIdsStr = prefs.getStringList(key);
    return trackIdsStr?.map((id) => int.tryParse(id) ?? 0).toList() ?? [];
  }

  static Future<void> saveAlbumTrackIds(
      int collectionId, List<int> trackIds) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String key = 'album_track_ids_$collectionId';
    List<String> trackIdsStr = trackIds.map((id) => id.toString()).toList();
    await prefs.setStringList(key, trackIdsStr);
  }

  static Future<void> exportRatings(String filePath) async {
    // TODO: Implement export ratings functionality
  }

  static Future<void> importRatings(String filePath) async {
    // TODO: Implement import ratings functionality
  }

  static Future<Map<int, double>?> getRatings(int albumId) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String key = '${_ratingsPrefix}$albumId';
      List<String>? savedRatings = prefs.getStringList(key);

      if (savedRatings != null && savedRatings.isNotEmpty) {
        Map<int, double> ratingsMap = {};
        
        for (String ratingJson in savedRatings) {
          Map<String, dynamic> rating = jsonDecode(ratingJson);
          int trackId = rating['trackId'];
          double ratingValue = rating['rating'].toDouble();
          ratingsMap[trackId] = ratingValue;
        }

        return ratingsMap;
      }
    } catch (e, stackTrace) {
      Logging.severe('Error getting ratings for album $albumId', e, stackTrace);
    }
    return null;
  }

  static Future<void> clearAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e, stackTrace) {
      Logging.severe('Error clearing all data', e, stackTrace);
      rethrow;
    }
  }

  static Future<String> _getDocumentsPath() async {
    if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();
      return directory?.path ?? (await getApplicationDocumentsDirectory()).path;
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        final documentsDir = Directory('$home/Documents');
        if (await documentsDir.exists()) {
          return documentsDir.path;
        }
      }
      return Platform.environment['HOME'] ?? '/home/${Platform.environment['USER']}';
    } else if (Platform.isWindows) {
      return path.join(Platform.environment['USERPROFILE'] ?? '', 'Documents');
    } else if (Platform.isMacOS) {
      return path.join(Platform.environment['HOME'] ?? '', 'Documents');
    } else {
      return path.join(Platform.environment['HOME'] ?? '', 'Documents');
    }
  }

  static Future<String?> _showFilePicker({
    required String dialogTitle,
    required String fileName,
    required String initialDirectory,
    bool isSave = true,
  }) async {
    try {
      if (isSave) {
        return await FilePicker.platform.saveFile(
          dialogTitle: dialogTitle,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          initialDirectory: initialDirectory,
        );
      } else {
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: dialogTitle,
          type: FileType.custom,
          allowedExtensions: ['json'],
          initialDirectory: initialDirectory,
        );
        return result?.files.single.path;
      }
    } catch (e) {
      final documentsPath = await _getDocumentsPath();
      return path.join(documentsPath, fileName);
    }
  }

  static Future<void> exportData(BuildContext context) async {
    try {
      final data = await _getAllData();
      final jsonData = jsonEncode(data);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileName = 'rateme_backup_$timestamp.json';

      if (Platform.isAndroid) {
        final downloadDir = await getDownloadsDirectory();
        final filePath = '${downloadDir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsString(jsonData);

        // Scan file with MediaScanner
        const platform = MethodChannel('com.example.rateme/media_scanner');
        try {
          await platform.invokeMethod('scanFile', {'path': filePath});
        } catch (e) {
          print('MediaScanner error: $e');
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Backup saved successfully'),
                  Text(fileName, style: const TextStyle(fontSize: 12)),
                  Text('Path: $filePath', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        }
      } else {
        // Use file_picker to save on desktop
        final String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save backup as',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
        );

        if (outputFile != null) {
          await File(outputFile).writeAsString(jsonData);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Backup saved successfully!')),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting data: $e')),
        );
      }
    }
  }

  static Future<bool> importData(BuildContext context) async {
    try {
      FilePickerResult? result;
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        result = await FilePicker.platform.pickFiles(
          dialogTitle: 'Select backup file to import',
          type: FileType.custom,
          allowedExtensions: ['json'],
          lockParentWindow: true,
          withData: false,
        );
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
      }

      if (result?.files.single.path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import cancelled')),
        );
        return false;
      }

      final file = File(result!.files.single.path!);
      String jsonData = await file.readAsString();
      Map<String, dynamic> data = jsonDecode(jsonData);

      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Import'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This will replace all your current data.'),
              const SizedBox(height: 8),
              Text('File: ${file.path}', style: const TextStyle(fontSize: 12)),
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
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (confirm != true) {
        return false;
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await Future.forEach(data.entries, (MapEntry<String, dynamic> entry) async {
        final key = entry.key;
        final value = entry.value;
        
        if (value is int) await prefs.setInt(key, value);
        else if (value is double) await prefs.setDouble(key, value);
        else if (value is bool) await prefs.setBool(key, value);
        else if (value is String) await prefs.setString(key, value);
        else if (value is List) {
          if (value.every((item) => item is String)) {
            await prefs.setStringList(key, List<String>.from(value));
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Data restored successfully!'),
                    Text(
                      file.path,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      return true;

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Error importing data: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
  }

  static Future<void> exportAlbum(BuildContext context, Map<String, dynamic> album) async {
    try {
      final albumId = album['collectionId'];
      final ratings = await getSavedAlbumRatings(albumId);
      final exportData = {
        'album': album,
        'ratings': ratings,
        'exportDate': DateTime.now().toIso8601String(),
        'version': '1.0',
      };

      final safeName = album['collectionName']
          .toString()
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final fileName = 'album_$safeName.json';

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
                        final downloadDir = await getDownloadsDirectory();
                        final filePath = '${downloadDir.path}/$fileName';
                        final file = File(filePath);
                        await file.writeAsString(jsonEncode(exportData));

                        // Scan file with MediaScanner
                        const platform = MethodChannel('com.example.rateme/media_scanner');
                        try {
                          await platform.invokeMethod('scanFile', {'path': filePath});
                        } catch (e) {
                          print('MediaScanner error: $e');
                        }
                        
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Saved to Downloads'),
                                  Text(fileName, style: const TextStyle(fontSize: 12)),
                                  Text('Path: $filePath', style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error saving file: $e')),
                          );
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.share),
                    title: const Text('Share JSON'),
                    onTap: () async {
                      Navigator.pop(context);
                      try {
                        final tempDir = await getTemporaryDirectory();
                        final tempFile = File('${tempDir.path}/$fileName');
                        await tempFile.writeAsString(jsonEncode(exportData));
                        await Share.shareXFiles([XFile(tempFile.path)]);
                      } catch (e) {
                        if (context.mounted) {
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
        // Use file_picker to save on desktop
        final String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save album as',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
        );

        if (outputFile != null) {
          await File(outputFile).writeAsString(jsonEncode(exportData));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Album exported successfully!')),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting album: $e')),
        );
      }
    }
  }

  static Future<Map<String, dynamic>?> importAlbum(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select album file to import',
      );

      if (result?.files.single.path != null) {
        final file = File(result!.files.single.path!);
        final jsonData = await file.readAsString();
        final data = jsonDecode(jsonData);

        if (!data.containsKey('version') || !data.containsKey('album')) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid album file format')),
            );
          }
          return null;
        }

        final album = data['album'];
        if (!album.containsKey('collectionId') || 
            !album.containsKey('collectionName') || 
            !album.containsKey('artistName')) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid album data format')),
            );
          }
          return null;
        }

        if (data['ratings'] != null) {
          final albumId = album['collectionId'];
          for (var rating in data['ratings']) {
            if (rating.containsKey('trackId') && rating.containsKey('rating')) {
              await saveRating(
                albumId,
                rating['trackId'],
                rating['rating'].toDouble(),
              );
            }
          }
        }

        return data['album'];
      }
    } catch (error) {
      Logging.severe('Error importing album', error);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing album: $error')),
        );
      }
    }
    return null;
  }

  static Future<List<CustomList>> getCustomLists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> lists = prefs.getStringList(_customListsKey) ?? [];
      return lists.map((json) => CustomList.fromJson(jsonDecode(json))).toList();
    } catch (e, stackTrace) {
      Logging.severe('Error getting custom lists', e, stackTrace);
      return [];
    }
  }

  static Future<void> saveCustomList(CustomList list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> lists = prefs.getStringList(_customListsKey) ?? [];
      
      int index = lists.indexWhere((json) {
        CustomList existing = CustomList.fromJson(jsonDecode(json));
        return existing.id == list.id;
      });

      if (index != -1) {
        lists[index] = jsonEncode(list.toJson());
      } else {
        lists.add(jsonEncode(list.toJson()));
      }

      // Save entire lists array
      await prefs.setStringList(_customListsKey, lists);  // Remove the unnecessary map
    } catch (e, stackTrace) {
      Logging.severe('Error saving custom list', e, stackTrace);
      rethrow;
    }
  }

  static Future<void> deleteCustomList(String listId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> lists = prefs.getStringList(_customListsKey) ?? [];
      
      lists.removeWhere((json) {
        CustomList list = CustomList.fromJson(jsonDecode(json));
        return list.id == listId;
      });

      await prefs.setStringList(_customListsKey, lists);
    } catch (e, stackTrace) {
      Logging.severe('Error deleting custom list', e, stackTrace);
      rethrow;
    }
  }

  static Future<String?> saveImage(BuildContext context, String defaultFileName) async {
    try {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        return await FilePicker.platform.saveFile(
          dialogTitle: 'Save image as',
          fileName: defaultFileName,
          type: FileType.custom,
          allowedExtensions: ['png'],
          lockParentWindow: true,
        );
      } else {
        final downloadDir = await getDownloadsDirectory();
        return path.join(downloadDir.path, defaultFileName);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting save location: $e')),
        );
      }
      return null;
    }
  }

  static Future<void> migrateRatings(int albumId, List<Map<String, dynamic>> tracks) async {
    final prefs = await SharedPreferences.getInstance();
    final oldRatingsKey = '${_ratingsPrefix}$albumId';
    final oldRatings = prefs.getStringList(oldRatingsKey) ?? [];

    if (oldRatings.isEmpty) return;

    // Create new ratings with correct track IDs
    List<Map<String, dynamic>> newRatings = [];
    for (var track in tracks) {
      final position = track['position'];
      final trackId = track['trackId'];
      
      // Find old rating by position
      final oldRating = oldRatings.map((r) => jsonDecode(r)).firstWhere(
        (r) => r['position'] == position,
        orElse: () => null,
      );

      if (oldRating != null) {
        newRatings.add({
          'trackId': trackId,
          'rating': oldRating['rating'],
          'timestamp': oldRating['timestamp'],
        });
      }
    }

    // Save new ratings
    await prefs.setStringList(
      oldRatingsKey,
      newRatings.map((r) => jsonEncode(r)).toList(),
    );
  }

  static Future<Map<int, Map<String, dynamic>>> migrateAlbumRatings(int albumId) async {
    final prefs = await SharedPreferences.getInstance();
    final ratingsKey = 'saved_ratings_$albumId';
    Map<int, Map<String, dynamic>> ratingsByPosition = {};
    
    final oldRatingsJson = prefs.getStringList(ratingsKey) ?? [];
    if (oldRatingsJson.isEmpty) return ratingsByPosition;

    final oldRatings = oldRatingsJson.map((r) => jsonDecode(r)).toList();
    
    for (var rating in oldRatings) {
      if (rating['position'] != null) {
        ratingsByPosition[rating['position'] as int] = rating as Map<String, dynamic>;
      }
    }

    return ratingsByPosition;
  }

  static Future<void> saveNewRating(
    int albumId, 
    int trackId, 
    int position,
    double rating,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final ratingsKey = 'saved_ratings_$albumId';
    
    final ratingData = {
      'trackId': trackId,
      'position': position,
      'rating': rating,
      'timestamp': DateTime.now().toIso8601String(),
    };

    List<String> ratings = prefs.getStringList(ratingsKey) ?? [];
    
    // Update or add new rating
    int index = ratings.indexWhere((r) {
      Map<String, dynamic> saved = jsonDecode(r);
      return saved['trackId'] == trackId || saved['position'] == position;
    });

    if (index != -1) {
      ratings[index] = jsonEncode(ratingData);
    } else {
      ratings.add(jsonEncode(ratingData));
    }

    await prefs.setStringList(ratingsKey, ratings);
  }

  static Future<Map<String, dynamic>> _getAllData() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data = {};
    
    for (String key in prefs.getKeys()) {
      dynamic value = prefs.get(key);
      if (value != null) {
        data[key] = value;
      }
    }
    
    return data;
  }

  static Future<Directory> getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      // Use public Downloads directory directly
      return Directory('/storage/emulated/0/Download');
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      return Directory('${directory.path}/Downloads');
    } else if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      return Directory('$home/Downloads');
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      return Directory('$userProfile\\Downloads');
    }
    return getApplicationDocumentsDirectory();
  }
}
