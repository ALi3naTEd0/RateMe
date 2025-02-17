import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'logging.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class UserData {
  static const String _savedAlbumsKey = 'saved_albums';
  static const String _savedAlbumOrderKey = 'saved_album_order';
  static const String _ratingsPrefix = 'saved_ratings_';

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

  static Future<void> exportData(BuildContext context) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> data = prefs.getKeys().fold({}, (previousValue, key) {
        previousValue[key] = prefs.get(key);
        return previousValue;
      });

      String jsonData = jsonEncode(data);
      
      // Obtener el directorio Documents del usuario
      String homeDirectory = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      String documentsPath = path.join(homeDirectory, 'Documents');
      Directory documentsDir = Directory(documentsPath);
      if (!documentsDir.existsSync()) {
        documentsDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File(path.join(documentsPath, 'rateme_backup_$timestamp.json'));
      
      await file.writeAsString(jsonData, flush: true);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup saved to: ${file.path}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating backup: $e')),
        );
      }
    }
  }

  static Future<bool> importData(BuildContext context) async {
    try {
      String homeDirectory = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      String documentsPath = path.join(homeDirectory, 'Documents');
      Directory documentsDir = Directory(documentsPath);
      
      if (!documentsDir.existsSync()) {
        throw Exception('Documents directory not found');
      }

      final backupFiles = documentsDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('rateme_backup_') && file.path.endsWith('.json'))
          .toList();

      if (backupFiles.isEmpty) {
        throw Exception('No backup files found in Documents folder');
      }

      final latestBackup = backupFiles.reduce((a, b) => 
        a.lastModifiedSync().isAfter(b.lastModifiedSync()) ? a : b);
      
      String jsonData = await latestBackup.readAsString();
      Map<String, dynamic> data = jsonDecode(jsonData);
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

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data restored from: ${latestBackup.path}')),
        );
      }
      return true;

    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing data: $e')),
        );
      }
      return false;
    }
  }
}
