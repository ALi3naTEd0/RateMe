import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'logging.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'custom_lists_page.dart';  // Única importación necesaria para CustomList
import 'package:file_picker/file_picker.dart';  // Agregar esta importación

class UserData {
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
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      String albumJson = jsonEncode(album);

      if (!savedAlbums.contains(albumJson)) {
        savedAlbums.add(albumJson);
        await prefs.setStringList(_savedAlbumsKey, savedAlbums);
        
        String albumId = album['collectionId'].toString();
        List<String> albumOrder = prefs.getStringList(_savedAlbumOrderKey) ?? [];
        if (!albumOrder.contains(albumId)) {
          albumOrder.add(albumId);
          await prefs.setStringList(_savedAlbumOrderKey, albumOrder);
        }
      }
    } catch (e, stackTrace) {
      Logging.severe('Error saving album', e, stackTrace);
      rethrow;
    }
  }

  static Future<void> deleteAlbum(Map<String, dynamic> album) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Obtener y filtrar álbumes guardados
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      String albumId = album['collectionId'].toString();
      
      // Filtrar por collectionId en lugar de comparar el JSON completo
      savedAlbums.removeWhere((savedAlbumJson) {
        Map<String, dynamic> savedAlbum = jsonDecode(savedAlbumJson);
        return savedAlbum['collectionId'].toString() == albumId;
      });
      
      // Guardar la lista actualizada
      await prefs.setStringList(_savedAlbumsKey, savedAlbums);

      // Actualizar orden de álbumes
      List<String> albumOrder = prefs.getStringList(_savedAlbumOrderKey) ?? [];
      albumOrder.remove(albumId);
      await prefs.setStringList(_savedAlbumOrderKey, albumOrder);

      // Eliminar ratings
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
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedAlbumsJson = prefs.getStringList('saved_albums');

    if (savedAlbumsJson != null) {
      Map<int, List<Map<String, dynamic>>> ratingsMap = {};
      for (String json in savedAlbumsJson) {
        Map<String, dynamic> album = jsonDecode(json);
        int albumId = album['collectionId'];
        List<Map<String, dynamic>> ratings =
            await getSavedAlbumRatings(albumId);
        ratingsMap[albumId] = ratings;
      }

      // Write ratingsMap to file
      // Example implementation for writing to file omitted for brevity
    }
  }

  static Future<void> importRatings(String filePath) async {
    // Example implementation for importing ratings from file omitted for brevity
  }

  static Future<Map<int, double>?> getRatings(int albumId) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String key = '${_ratingsPrefix}$albumId';  // Usar el mismo prefijo que en saveRating
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
    if (Platform.isWindows) {
      // En Windows: C:\Users\<username>\Documents
      return path.join(Platform.environment['USERPROFILE'] ?? '', 'Documents');
    } else if (Platform.isMacOS) {
      // En MacOS: /Users/<username>/Documents
      return path.join(Platform.environment['HOME'] ?? '', 'Documents');
    } else {
      // En Linux y otros: /home/<username>/Documents
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
      // Si falla FilePicker (por ejemplo, por falta de zenity),
      // usar directamente Documents
      final documentsPath = await _getDocumentsPath();
      return path.join(documentsPath, fileName);
    }
  }

  static Future<void> exportData(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> data = prefs.getKeys().fold({}, (previousValue, key) {
        previousValue[key] = prefs.get(key);
        return previousValue;
      });

      String initialDirectory = await _getDocumentsPath();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final defaultFileName = 'rateme_backup_$timestamp.json';
      
      // Mostrar diálogo para seleccionar la ubicación
      String? selectedDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select folder to save backup',
        initialDirectory: initialDirectory,
      );

      if (selectedDir == null) {
        selectedDir = initialDirectory; // Usar Documents por defecto si no se selecciona nada
      }

      final filePath = path.join(selectedDir, defaultFileName);
      final file = File(filePath);
      
      await file.writeAsString(jsonEncode(data), flush: true);

      if (context.mounted) {
        // Mostrar SnackBar en lugar de diálogo
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
                      const Text('Backup created successfully!'),
                      Text(
                        filePath,
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
            width: MediaQuery.of(context).size.width * 0.9,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Error creating backup: $e'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static Future<bool> importData(BuildContext context) async {
    try {
      String initialDirectory = await _getDocumentsPath();
      final scaffoldContext = context;  // Guardar referencia al contexto

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select backup file to import',
        type: FileType.custom,
        allowedExtensions: ['json'],
        initialDirectory: initialDirectory,
      );

      if (result?.files.single.path == null) {
        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
          const SnackBar(content: Text('Import cancelled')),
        );
        return false;
      }

      final file = File(result!.files.single.path!);
      String jsonData = await file.readAsString();
      Map<String, dynamic> data = jsonDecode(jsonData);

      bool? confirm = await showDialog<bool>(
        context: scaffoldContext,
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

      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
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
      
      // Update existing or add new
      int index = lists.indexWhere((json) {
        CustomList existing = CustomList.fromJson(jsonDecode(json));
        return existing.id == list.id;
      });

      if (index != -1) {
        lists[index] = jsonEncode(list.toJson());
      } else {
        lists.add(jsonEncode(list.toJson()));
      }

      await prefs.setStringList(_customListsKey, lists);
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
}
