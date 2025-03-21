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
import 'package:flutter/services.dart';
import 'album_model.dart';
import 'model_mapping_service.dart';
import 'platform_data_analyzer.dart';

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
      
      List<Map<String, dynamic>> albums = [];
      for (String albumJson in savedAlbums) {
        try {
          Map<String, dynamic> album = jsonDecode(albumJson);
          albums.add(album);
        } catch (e) {
          Logging.severe('Error parsing album JSON', e);
        }
      }

      // Sort albums based on the album order
      albums.sort((a, b) {
        // Convert IDs to string for safe comparison (both new and legacy IDs)
        String idA = (a['id'] ?? a['collectionId'])?.toString() ?? '';
        String idB = (b['id'] ?? b['collectionId'])?.toString() ?? '';
        
        int indexA = albumOrder.indexOf(idA);
        int indexB = albumOrder.indexOf(idB);
        
        // Handle case where ID is not in the order list
        if (indexA == -1) indexA = albumOrder.length;
        if (indexB == -1) indexB = albumOrder.length;
        
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
      final String albumKey = 'album_${album['collectionId']}';
      
      // Filter and save only audio tracks
      if (album['tracks'] != null) {
        var audioTracks = (album['tracks'] as List).where((track) =>
          track['wrapperType'] == 'track' && track['kind'] == 'song'
        ).toList();
        album['tracks'] = audioTracks;
      }
      await prefs.setString(albumKey, jsonEncode(album));
    } catch (e, stackTrace) {
      Logging.severe('Error saving album', e, stackTrace);
      rethrow;
    }
  }

  static Future<void> addToSavedAlbums(dynamic albumData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      List<String> albumOrder = prefs.getStringList(_savedAlbumOrderKey) ?? [];
      
      // ALWAYS convert to unified Album model first
      Album album;
      if (albumData is Album) {
        album = albumData;
      } else {
        album = Album.fromLegacy(albumData);
      }
      
      // Save in unified format
      final albumJson = jsonEncode(album.toJson());
      String albumId = album.id.toString();
      
      // Check if exists
      bool exists = false;
      for (String savedAlbumJson in savedAlbums) {
        final saved = jsonDecode(savedAlbumJson);
        if (saved['id']?.toString() == albumId) {
          exists = true;
          break; 
        }
      }
      
      if (!exists) {
        savedAlbums.add(albumJson);
        albumOrder.add(albumId);
        await prefs.setStringList(_savedAlbumsKey, savedAlbums);
        await prefs.setStringList(_savedAlbumOrderKey, albumOrder);
      }
    } catch (e) {
      Logging.severe('Error saving album', e);
      rethrow;
    }
  }

  static Future<void> deleteAlbum(Map<String, dynamic> album) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      List<String> albumOrder = prefs.getStringList(_savedAlbumOrderKey) ?? [];
      
      String albumId = (album['id'] ?? album['collectionId']).toString();
      
      // Remove from albums list
      savedAlbums.removeWhere((albumJson) {
        try {
          Map<String, dynamic> savedAlbum = jsonDecode(albumJson);
          String savedId = (savedAlbum['id'] ?? savedAlbum['collectionId']).toString();
          return savedId == albumId;
        } catch (e) {
          return false;
        }
      });
      
      // Remove from order list
      albumOrder.remove(albumId);
      
      // Also delete ratings
      await _deleteRatings(int.parse(albumId));
      
      // Save updated lists
      await prefs.setStringList(_savedAlbumsKey, savedAlbums);
      await prefs.setStringList(_savedAlbumOrderKey, albumOrder);
    } catch (e, stackTrace) {
      Logging.severe('Error deleting album', e, stackTrace);
      rethrow;
    }
  }

  static Future<void> _deleteRatings(int collectionId) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_ratings_$collectionId');
    } catch (e) {
      Logging.severe('Error deleting ratings', e);
    }
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
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String>? albumIds = prefs.getStringList(_savedAlbumOrderKey);
      return albumIds ?? [];
    } catch (e) {
      Logging.severe('Error getting saved album order', e);
      return [];
    }
  }

  static Future<void> saveRating(
      int albumId, int trackId, double rating) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String key = '${_ratingsPrefix}$albumId';
      List<String> ratings = prefs.getStringList(key) ?? [];
      
      // Create new rating data
      final ratingData = {
        'trackId': trackId,
        'rating': rating,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Find and update existing rating or add new one
      bool found = false;
      for (int i = 0; i < ratings.length; i++) {
        try {
          Map<String, dynamic> existingRating = jsonDecode(ratings[i]);
          if (existingRating['trackId'] == trackId) {
            ratings[i] = jsonEncode(ratingData);
            found = true;
            break;
          }
        } catch (e) {
          // Skip invalid rating
        }
      }
      
      if (!found) {
        ratings.add(jsonEncode(ratingData));
      }
      
      await prefs.setStringList(key, ratings);
    } catch (e, stackTrace) {
      Logging.severe('Error saving rating', e, stackTrace);
      rethrow;
    }
  }

  static Future<Album?> getSavedAlbumById(int albumId) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String>? savedAlbumsJson = prefs.getStringList(_savedAlbumsKey);

      if (savedAlbumsJson != null) {
        for (String json in savedAlbumsJson) {
          try {
            Map<String, dynamic> albumData = jsonDecode(json);
            
            // Check for ID match using either legacy or new format
            bool isMatch = false;
            if (albumData.containsKey('collectionId')) {
              final id = albumData['collectionId'];
              isMatch = (id is int && id == albumId) || 
                       (id is String && id == albumId.toString());
            }
            if (!isMatch && albumData.containsKey('id')) {
              final id = albumData['id'];
              isMatch = (id is int && id == albumId) || 
                       (id is String && id == albumId.toString());
            }
            
            if (isMatch) {
              // Convert to unified model
              if (albumData.containsKey('modelVersion')) {
                // Already in unified format
                return Album.fromJson(albumData);
              } else {
                // Legacy format - convert using fromLegacy
                return Album.fromLegacy(albumData);
              }
            }
          } catch (e) {
            Logging.severe('Error parsing album JSON when getting by ID', e);
            continue;
          }
        }
      }
      return null;
    } catch (e, stack) {
      Logging.severe('Error in getSavedAlbumById', e, stack);
      return null;
    }
  }

  static Future<List<int>> getSavedAlbumTrackIds(int collectionId) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String key = 'album_track_ids_$collectionId';
      List<String>? trackIdsStr = prefs.getStringList(key);
      return trackIdsStr?.map((id) => int.tryParse(id) ?? 0).toList() ?? [];
    } catch (e) {
      Logging.severe('Error getting saved album track IDs', e);
      return [];
    }
  }

  static Future<void> saveAlbumTrackIds(
      int collectionId, List<int> trackIds) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String key = 'album_track_ids_$collectionId';
      List<String> trackIdsStr = trackIds.map((id) => id.toString()).toList();
      await prefs.setStringList(key, trackIdsStr);
    } catch (e) {
      Logging.severe('Error saving album track IDs', e);
    }
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
      
      if (savedRatings == null || savedRatings.isEmpty) {
        return null;
      }
      
      Map<int, double> result = {};
      for (String ratingJson in savedRatings) {
        Map<String, dynamic> rating = jsonDecode(ratingJson);
        int trackId = rating['trackId'];
        double ratingValue = rating['rating'].toDouble();
        result[trackId] = ratingValue;
      }
      
      return result;
    } catch (e) {
      Logging.severe('Error getting ratings', e);
      return null;
    }
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
    try {
      if (Platform.isAndroid) {
        final directory = await getExternalStorageDirectory();
        return directory?.path ?? (await getApplicationDocumentsDirectory()).path;
      } else if (Platform.isIOS) {
        return (await getApplicationDocumentsDirectory()).path;
      } else if (Platform.isLinux) {
        final home = Platform.environment['HOME'];
        return '$home/Documents';
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        return path.join(userProfile ?? '', 'Documents');
      } else if (Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        return '$home/Documents';
      } else {
        return (await getApplicationDocumentsDirectory()).path;
      }
    } catch (e) {
      return (await getApplicationDocumentsDirectory()).path;
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
        final documentsPath = await _getDocumentsPath();
        // Clean up filename to make it safe across platforms
        fileName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        return path.join(documentsPath, fileName);
      } else {
        final result = await FilePicker.platform.pickFiles();
        if (result != null) {
          return result.files.single.path;
        }
      }
    } catch (e) {
      Logging.severe('Error showing file picker', e);
    }
    return null;
  }

  static Future<void> exportData(BuildContext context) async {
    try {
      final timestamp = DateTime.now().toString().replaceAll(':', '-');
      final fileName = 'rateme_backup_$timestamp.json';
      
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save backup as',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      
      if (outputFile == null) {
        return;  // User cancelled
      }
      
      final data = await _getAllData();
      final jsonData = jsonEncode(data);
      
      final file = File(outputFile);
      await file.writeAsString(jsonData);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Data exported to: $outputFile'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      Logging.severe('Error exporting data', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting data: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static Future<bool> importData(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select backup file',
      );
      
      if (result == null || result.files.isEmpty) {
        return false;  // User cancelled
      }
      
      final file = File(result.files.first.path!);
      final jsonData = await file.readAsString();
      final data = jsonDecode(jsonData);
      
      // Show conversion dialog
      final shouldConvert = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Convert Backup'),
          content: const Text(
            'Would you like to convert this backup to the new album format? '
            'This is recommended for better compatibility.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Import As Is'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Convert'),
            ),
          ],
        ),
      );

      if (shouldConvert == true) {
        // Convert albums to new format
        if (data['saved_albums'] != null) {
          List<String> savedAlbums = List<String>.from(data['saved_albums']);
          List<String> convertedAlbums = [];
          
          for (String albumJson in savedAlbums) {
            try {
              Map<String, dynamic> albumData = jsonDecode(albumJson);
              Album album = Album.fromLegacy(albumData);
              convertedAlbums.add(jsonEncode(album.toJson()));
            } catch (e) {
              Logging.severe('Error converting album during import', e);
              convertedAlbums.add(albumJson); // Keep original on error
            }
          }
          
          data['saved_albums'] = convertedAlbums;
        }
      }
      
      // Clear existing data and import
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      for (String key in data.keys) {
        dynamic value = data[key];
        if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value is String) {
          await prefs.setString(key, value);
        } else if (value is List) {
          if (value.every((item) => item is String)) {
            await prefs.setStringList(key, List<String>.from(value));
          }
        }
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(shouldConvert == true 
              ? 'Data converted and imported successfully'
              : 'Data imported successfully'),
          ),
        );
      }
      
      return true;
    } catch (e) {
      Logging.severe('Error importing data', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing data: $e')),
        );
      }
      return false;
    }
  }

  static Future<void> exportAlbum(BuildContext context, Map<String, dynamic> album) async {
    try {
      final String artistName = album['artistName'] ?? 'Unknown';
      final String albumName = album['collectionName'] ?? 'Unknown';
      
      String fileName = '${artistName}_${albumName}.json';
      // Clean filename
      fileName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save album as',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      
      if (outputFile == null) {
        return;  // User cancelled
      }
      
      // Get album ratings
      int albumId = album['collectionId'];
      final ratings = await getSavedAlbumRatings(albumId);
      
      // Create export data
      final exportData = {
        'album': album,
        'ratings': ratings,
        'exportDate': DateTime.now().toIso8601String(),
      };
      
      final jsonData = jsonEncode(exportData);
      
      final file = File(outputFile);
      await file.writeAsString(jsonData);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Album exported to: $outputFile'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      Logging.severe('Error exporting album', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting album: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static Future<Map<String, dynamic>?> importAlbum(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select album file',
      );
      
      if (result == null || result.files.isEmpty) {
        return null;  // User cancelled
      }
      
      final file = File(result.files.first.path!);
      final jsonData = await file.readAsString();
      final data = jsonDecode(jsonData);
      
      if (!data.containsKey('album')) {
        throw Exception('Invalid album file format');
      }
      
      final album = data['album'];
      final ratings = data['ratings'];
      
      // Import album ratings if available
      if (ratings != null && album.containsKey('collectionId')) {
        int albumId = album['collectionId'];
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
      
      return album;
    } catch (e) {
      Logging.severe('Error importing album', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing album: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    }
  }

  static Future<List<CustomList>> getCustomLists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> listsJson = prefs.getStringList(_customListsKey) ?? [];
      
      // Safe parsing of each list
      List<CustomList> result = [];
      for (String json in listsJson) {
        try {
          Map<String, dynamic> data = jsonDecode(json);
          CustomList list = CustomList.fromJson(data);
          result.add(list);
        } catch (e) {
          Logging.severe('Error parsing custom list', e);
          // Skip invalid entries
        }
      }
      
      return result;
    } catch (e, stackTrace) {
      Logging.severe('Error getting custom lists', e, stackTrace);
      return [];
    }
  }

  static Future<void> saveCustomList(CustomList list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> listsJson = prefs.getStringList(_customListsKey) ?? [];
      
      // Update or add the list
      bool found = false;
      for (int i = 0; i < listsJson.length; i++) {
        try {
          Map<String, dynamic> data = jsonDecode(listsJson[i]);
          if (data['id'] == list.id) {
            list.updatedAt = DateTime.now();
            listsJson[i] = jsonEncode(list.toJson());
            found = true;
            break;
          }
        } catch (e) {
          // Skip invalid entries
        }
      }
      
      if (!found) {
        listsJson.add(jsonEncode(list.toJson()));
      }
      
      await prefs.setStringList(_customListsKey, listsJson);
    } catch (e, stackTrace) {
      Logging.severe('Error saving custom list', e, stackTrace);
      rethrow;
    }
  }

  static Future<void> deleteCustomList(String listId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> listsJson = prefs.getStringList(_customListsKey) ?? [];
      
      listsJson.removeWhere((json) {
        try {
          Map<String, dynamic> data = jsonDecode(json);
          return data['id'] == listId;
        } catch (e) {
          return false;
        }
      });
      
      await prefs.setStringList(_customListsKey, listsJson);
    } catch (e, stackTrace) {
      Logging.severe('Error deleting custom list', e, stackTrace);
      rethrow;
    }
  }

  static Future<String?> saveImage(BuildContext context, String defaultFileName) async {
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final fileName = defaultFileName.isEmpty 
          ? 'rateme_image_$timestamp.png' 
          : defaultFileName;
      
      final filePath = '${dir.path}/$fileName';
      return filePath;
    } catch (e) {
      Logging.severe('Error saving image', e);
      return null;
    }
  }

  static Future<void> migrateRatings(int albumId, List<Map<String, dynamic>> tracks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final oldRatingsKey = '${_ratingsPrefix}$albumId';
      final oldRatings = prefs.getStringList(oldRatingsKey) ?? [];

      if (oldRatings.isEmpty) return;

      // Create new ratings with correct track IDs
      List<Map<String, dynamic>> newRatings = [];
      for (var track in tracks) {
        final position = track['position'] ?? track['trackNumber'] ?? 0;
        final trackId = track['trackId'];
        
        // Find ratings by position
        for (var ratingJson in oldRatings) {
          try {
            final rating = jsonDecode(ratingJson);
            final ratingPosition = rating['position'] ?? rating['trackNumber'] ?? 0;
            
            if (ratingPosition == position) {
              final newRating = {
                'trackId': trackId,
                'rating': rating['rating'],
                'position': position,
                'timestamp': rating['timestamp'] ?? DateTime.now().toIso8601String(),
              };
              
              newRatings.add(newRating);
              break;
            }
          } catch (e) {
            // Skip invalid ratings
          }
        }
      }

      // Save new ratings
      await prefs.setStringList(
        oldRatingsKey, 
        newRatings.map((r) => jsonEncode(r)).toList(),
      );
    } catch (e) {
      Logging.severe('Error migrating ratings', e);
    }
  }

  static Future<Map<int, Map<String, dynamic>>> migrateAlbumRatings(int albumId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ratingsKey = 'saved_ratings_$albumId';
      Map<int, Map<String, dynamic>> ratingsByPosition = {};
      
      final oldRatingsJson = prefs.getStringList(ratingsKey) ?? [];
      if (oldRatingsJson.isEmpty) return ratingsByPosition;

      final oldRatings = oldRatingsJson.map((r) => jsonDecode(r) as Map<String, dynamic>).toList();
      
      for (var rating in oldRatings) {
        final position = rating['position'] ?? rating['trackNumber'] ?? 0;
        if (position > 0) {
          ratingsByPosition[position] = rating;
        }
      }

      return ratingsByPosition;
    } catch (e) {
      Logging.severe('Error migrating album ratings', e);
      return {};
    }
  }

  static Future<void> saveNewRating(
    int albumId, 
    int trackId, 
    int position,
    double rating,
  ) async {
    try {
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
        try {
          final saved = jsonDecode(r);
          return saved['trackId'] == trackId || saved['position'] == position;
        } catch (e) {
          return false;
        }
      });

      if (index != -1) {
        ratings[index] = jsonEncode(ratingData);
      } else {
        ratings.add(jsonEncode(ratingData));
      }

      await prefs.setStringList(ratingsKey, ratings);
    } catch (e) {
      Logging.severe('Error saving new rating', e);
    }
  }

  static Future<void> migrateDataToNewModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      List<String> newSavedAlbums = [];
      
      // Convert each album to the new model
      for (String albumJson in savedAlbums) {
        try {
          Map<String, dynamic> albumData = jsonDecode(albumJson);
          
          // Check if this is already the new model
          if (albumData.containsKey('modelVersion')) {
            newSavedAlbums.add(albumJson);
            continue;
          }
          
          // Convert to the new model
          Album album = Album.fromLegacy(albumData);
          newSavedAlbums.add(jsonEncode(album.toJson()));
        } catch (e) {
          // Keep the original on error
          newSavedAlbums.add(albumJson);
          Logging.severe('Error migrating album to new model', e);
        }
      }
      
      // Save the converted albums
      await prefs.setStringList(_savedAlbumsKey, newSavedAlbums);
      
      // Mark migration as done
      await prefs.setInt('data_migration_version', 1);
      
      Logging.severe('Legacy albums data format validated - safe to use');
    } catch (e, stackTrace) {
      Logging.severe('Error migrating data to new model', e, stackTrace);
    }
  }

  static Future<Map<String, dynamic>> _getAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> data = {};
      
      for (String key in prefs.getKeys()) {
        if (prefs.containsKey(key)) {
          if (key.endsWith('Int')) {
            data[key] = prefs.getInt(key);
          } else if (key.endsWith('Bool')) {
            data[key] = prefs.getBool(key);
          } else if (key.endsWith('Double')) {
            data[key] = prefs.getDouble(key);
          } else if (prefs.getString(key) != null) {
            data[key] = prefs.getString(key);
          } else if (prefs.getStringList(key) != null) {
            data[key] = prefs.getStringList(key);
          }
        }
      }
      
      return data;
    } catch (e) {
      Logging.severe('Error getting all data', e);
      return {};
    }
  }

  static Future<Directory> getDownloadsDirectory() async {
    try {
      if (Platform.isAndroid) {
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
      } else {
        return await getApplicationDocumentsDirectory();
      }
    } catch (e) {
      Logging.severe('Error getting downloads directory', e);
      return await getTemporaryDirectory();
    }
  }

  static Future<bool> repairSavedAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedAlbumsJson = prefs.getStringList(_savedAlbumsKey) ?? [];
      
      if (savedAlbumsJson.isEmpty) {
        Logging.severe('No albums to repair');
        return false;
      }
      
      List<String> repairedAlbums = [];
      bool repairsNeeded = false;
      
      for (String albumJson in savedAlbumsJson) {
        try {
          Map<String, dynamic> albumData = jsonDecode(albumJson);
          bool modified = false;
          
          // Ensure an ID exists
          if (!albumData.containsKey('id') && !albumData.containsKey('collectionId')) {
            albumData['id'] = DateTime.now().millisecondsSinceEpoch.toString();
            modified = true;
          }
          
          // Handle missing or empty artwork URL
          if (!albumData.containsKey('artworkUrl100') || albumData['artworkUrl100'] == null) {
            if (albumData.containsKey('artworkUrl') && albumData['artworkUrl'] != null) {
              albumData['artworkUrl100'] = albumData['artworkUrl'];
              modified = true;
            }
          }
          
          // Handle missing artistName
          if (!albumData.containsKey('artistName') || albumData['artistName'] == null) {
            if (albumData.containsKey('artist') && albumData['artist'] != null) {
              albumData['artistName'] = albumData['artist'];
              modified = true;
            } else {
              albumData['artistName'] = 'Unknown Artist';
              modified = true;
            }
          }
          
          // Handle missing collectionName
          if (!albumData.containsKey('collectionName') || albumData['collectionName'] == null) {
            if (albumData.containsKey('name') && albumData['name'] != null) {
              albumData['collectionName'] = albumData['name'];
              modified = true;
            } else {
              albumData['collectionName'] = 'Unknown Album';
              modified = true;
            }
          }
          
          if (modified) {
            repairsNeeded = true;
            repairedAlbums.add(jsonEncode(albumData));
          } else {
            repairedAlbums.add(albumJson);
          }
        } catch (e) {
          // If JSON is invalid, skip this album
          Logging.severe('Error repairing album JSON', e);
        }
      }
      
      if (repairsNeeded) {
        await prefs.setStringList(_savedAlbumsKey, repairedAlbums);
        
        // Also repair custom lists
        await _repairCustomLists(prefs);
        
        Logging.severe('Repaired ${repairedAlbums.length} albums');
        return true;
      }
      
      return false;
    } catch (e) {
      Logging.severe('Error repairing saved albums', e);
      return false;
    }
  }

  // Helper to repair custom lists
  static Future<void> _repairCustomLists(SharedPreferences prefs) async {
    try {
      List<String> listsJson = prefs.getStringList(_customListsKey) ?? [];
      List<String> repairedLists = [];
      bool repairsNeeded = false;
      
      for (String listJson in listsJson) {
        try {
          Map<String, dynamic> data = jsonDecode(listJson);
          CustomList list = CustomList.fromJson(data);
          
          // Clean up album IDs
          int originalCount = list.albumIds.length;
          list.cleanupAlbumIds();
          
          bool modified = list.albumIds.length != originalCount;
          
          if (modified) {
            repairsNeeded = true;
            repairedLists.add(jsonEncode(list.toJson()));
          } else {
            repairedLists.add(listJson);
          }
        } catch (e) {
          // Keep original if we can't parse it
          repairedLists.add(listJson);
        }
      }
      
      if (repairsNeeded) {
        await prefs.setStringList(_customListsKey, repairedLists);
        Logging.severe('Repaired ${repairedLists.length} custom lists');
      }
    } catch (e) {
      Logging.severe('Error repairing custom lists', e);
    }
  }

  // Add a method to convert all saved albums to unified format
  static Future<int> convertAllAlbumsToUnifiedFormat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedAlbumsJson = prefs.getStringList(_savedAlbumsKey) ?? [];
      
      if (savedAlbumsJson.isEmpty) {
        Logging.severe('No albums to convert to unified format');
        return 0;
      }
      
      // Make a backup
      await prefs.setStringList('backup_saved_albums', savedAlbumsJson);
      
      List<String> convertedAlbums = [];
      int successCount = 0;
      
      for (String albumJson in savedAlbumsJson) {
        try {
          Map<String, dynamic> albumData = jsonDecode(albumJson);
          
          // Convert to unified model
          Album album;
          if (albumData.containsKey('modelVersion')) {
            // Already in unified format
            album = Album.fromJson(albumData);
          } else {
            // Legacy format
            album = Album.fromLegacy(albumData);
          }
          
          // Add to converted list
          convertedAlbums.add(jsonEncode(album.toJson()));
          successCount++;
          
          Logging.severe('Successfully converted album to unified format: ${album.name}');
        } catch (e) {
          Logging.severe('Error converting album to unified format: $e');
          // Keep original on error
          convertedAlbums.add(albumJson);
        }
      }
      
      // Save converted albums
      await prefs.setStringList(_savedAlbumsKey, convertedAlbums);
      
      return successCount;
    } catch (e) {
      Logging.severe('Error converting all albums to unified format', e);
      return 0;
    }
  }

  /// Save album in unified format
  static Future<bool> saveUnifiedAlbum(Album album) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing albums
      List<String> savedAlbums = prefs.getStringList('saved_albums') ?? [];
      List<String> albumOrder = prefs.getStringList('saved_album_order') ?? [];
      
      // Check if album already exists
      int existingIndex = savedAlbums.indexWhere((json) {
        try {
          final data = jsonDecode(json);
          return data['id']?.toString() == album.id.toString() ||
                 data['collectionId']?.toString() == album.id.toString();
        } catch (e) {
          return false;
        }
      });
      
      // Convert to JSON and save
      final albumJson = jsonEncode(album.toJson());
      if (existingIndex >= 0) {
        savedAlbums[existingIndex] = albumJson;
      } else {
        savedAlbums.add(albumJson);
        albumOrder.add(album.id.toString());
      }
      
      // Save both lists
      await prefs.setStringList('saved_albums', savedAlbums);
      await prefs.setStringList('saved_album_order', albumOrder);
      
      return true;
    } catch (e) {
      Logging.severe('Error saving unified album', e);
      return false;
    }
  }

  /// Get album by ID, returns in unified format when possible
  static Future<Album?> getUnifiedAlbum(dynamic albumId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAlbums = prefs.getStringList('saved_albums') ?? [];
      
      for (String albumJson in savedAlbums) {
        try {
          final data = jsonDecode(albumJson);
          if (data['id']?.toString() == albumId.toString() ||
              data['collectionId']?.toString() == albumId.toString()) {
            
            // Try to convert to unified model
            if (ModelMappingService.isLegacyFormat(data)) {
              return ModelMappingService.mapItunesSearchResult(data);
            } else {
              return Album.fromJson(data);
            }
          }
        } catch (e) {
          Logging.severe('Error parsing album JSON', e);
          continue;
        }
      }
      
      return null;
    } catch (e) {
      Logging.severe('Error getting unified album', e);
      return null;
    }
  }

  static Future<int> cleanupOrphanedRatings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int removedCount = 0;
      
      // Get all saved album IDs
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      Set<String> validAlbumIds = {};
      
      // Extract all valid album IDs
      for (String albumJson in savedAlbums) {
        try {
          Map<String, dynamic> album = jsonDecode(albumJson);
          String id = (album['id'] ?? album['collectionId']).toString();
          validAlbumIds.add(id);
        } catch (e) {
          Logging.severe('Error parsing album JSON', e);
        }
      }
      
      // Find and remove orphaned ratings
      for (String key in prefs.getKeys()) {
        if (key.startsWith(_ratingsPrefix)) {
          String albumId = key.replaceFirst(_ratingsPrefix, '');
          if (!validAlbumIds.contains(albumId)) {
            await prefs.remove(key);
            removedCount++;
            Logging.severe('Removed orphaned ratings for album ID: $albumId');
          }
        }
      }
      
      return removedCount;
    } catch (e) {
      Logging.severe('Error cleaning up orphaned ratings', e);
      return 0;
    }
  }
}