import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'logging.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'custom_lists_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'album_model.dart';
import 'model_mapping_service.dart';

class UserData {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

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

  /// Get saved album ratings with proper ID handling for both string and int IDs
  static Future<List<Map<String, dynamic>>> getSavedAlbumRatings(
      dynamic albumId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_ratingsPrefix${_normalizeId(albumId)}';
      Logging.severe('Getting ratings with key: $key');

      final List<String> savedRatings = prefs.getStringList(key) ?? [];
      Logging.severe('Found ${savedRatings.length} saved ratings');

      // Log sample for debugging
      if (savedRatings.isNotEmpty) {
        Logging.severe('Sample rating JSON: ${savedRatings.first}');
      }

      return savedRatings.map((ratingJson) {
        try {
          final rating = jsonDecode(ratingJson);
          // Ensure trackId is always consistent
          rating['trackId'] = _normalizeId(rating['trackId']);
          return rating as Map<String, dynamic>;
        } catch (e, stack) {
          Logging.severe('Error parsing rating JSON: $ratingJson', e, stack);
          return {'trackId': '0', 'rating': 0.0, 'error': true};
        }
      }).toList();
    } catch (e, stackTrace) {
      Logging.severe(
          'Error getting saved ratings for album $albumId', e, stackTrace);
      return [];
    }
  }

  static Future<void> saveAlbum(Map<String, dynamic> album) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String albumKey = 'album_${album['collectionId']}';

      // Filter and save only audio tracks
      if (album['tracks'] != null) {
        var audioTracks = (album['tracks'] as List)
            .where((track) =>
                track['wrapperType'] == 'track' && track['kind'] == 'song')
            .toList();
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

      // Convert to Album object if not already
      Album album;
      if (albumData is Album) {
        album = albumData;
      } else {
        // Extra logging for debugging
        Logging.severe(
            'Converting album to unified format: ${albumData['name'] ?? albumData['collectionName']}');

        // Ensure platform is preserved during conversion
        String platform = albumData['platform']?.toString() ?? 'unknown';
        Logging.severe('Original platform: $platform');

        // Special handling for Spotify albums
        final albumId = albumData['id']?.toString() ??
            albumData['collectionId']?.toString() ??
            '';
        if (albumId.isNotEmpty &&
            albumId.length > 10 &&
            !albumId.contains(RegExp(r'^[0-9]+$'))) {
          if (platform == 'unknown') {
            platform = 'spotify';
            albumData['platform'] = 'spotify';
            Logging.severe(
                'Auto-detected platform as Spotify based on ID format');
          }
        }

        album = Album.fromLegacy(albumData);

        // Double-check that platform was properly transferred
        if (album.platform != platform && platform != 'unknown') {
          Logging.severe(
              'Platform mismatch! Expected: $platform, Got: ${album.platform}. Fixing...');
          // Create a corrected album with the right platform
          album = Album(
            id: album.id,
            name: album.name,
            artist: album.artist,
            artworkUrl: album.artworkUrl,
            url: album.url,
            platform: platform,
            releaseDate: album.releaseDate,
            metadata: album.metadata,
            tracks: album.tracks,
          );
        }
      }

      // Get album ID as string for consistent comparison
      String albumId = album.id.toString();
      Logging.severe(
          'Processed album ID: $albumId (Platform: ${album.platform})');

      // Check if album already exists
      bool exists = false;
      int existingIndex = -1;

      for (int i = 0; i < savedAlbums.length; i++) {
        try {
          final saved = jsonDecode(savedAlbums[i]);
          final savedId =
              (saved['id'] ?? saved['collectionId'])?.toString() ?? '';

          if (savedId == albumId) {
            exists = true;
            existingIndex = i;
            break;
          }
        } catch (e) {
          Logging.severe('Error checking existing album: $e');
        }
      }

      // Convert to JSON for storage
      final albumJson = jsonEncode(album.toJson());

      if (exists) {
        // Update existing album
        Logging.severe('Updating existing album at index $existingIndex');
        savedAlbums[existingIndex] = albumJson;
      } else {
        // Add new album
        Logging.severe('Adding new album');
        savedAlbums.add(albumJson);
        albumOrder.add(albumId);
      }

      // Save changes
      await prefs.setStringList(_savedAlbumsKey, savedAlbums);
      await prefs.setStringList(_savedAlbumOrderKey, albumOrder);

      Logging.severe(
          'Album saved successfully. Platform: ${album.platform}, Total albums: ${savedAlbums.length}');
    } catch (e, stack) {
      Logging.severe('Error saving album', e, stack);
      rethrow;
    }
  }

  static Future<void> deleteAlbum(Map<String, dynamic> album) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      List<String> albumOrder = prefs.getStringList(_savedAlbumOrderKey) ?? [];

      // Get album ID as string for consistent comparison
      String albumId = (album['id'] ?? album['collectionId']).toString();

      Logging.severe('Deleting album with ID: $albumId');

      // Remove from albums list
      int removedCount = 0;
      savedAlbums.removeWhere((albumJson) {
        try {
          Map<String, dynamic> savedAlbum = jsonDecode(albumJson);
          String savedId =
              (savedAlbum['id'] ?? savedAlbum['collectionId']).toString();
          bool shouldRemove = savedId == albumId;
          if (shouldRemove) removedCount++;
          return shouldRemove;
        } catch (e) {
          Logging.severe('Error checking album for removal: $e');
          return false;
        }
      });

      // Remove from order list
      albumOrder.remove(albumId);

      // Also delete ratings
      await _deleteRatings(albumId);

      Logging.severe('Removed $removedCount albums with ID: $albumId');

      // Save updated lists
      await prefs.setStringList(_savedAlbumsKey, savedAlbums);
      await prefs.setStringList(_savedAlbumOrderKey, albumOrder);

      Logging.severe('Album deletion complete for ID: $albumId');
    } catch (e, stackTrace) {
      Logging.severe('Error deleting album', e, stackTrace);
      rethrow;
    }
  }

  static Future<void> _deleteRatings(dynamic albumId) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String key = '$_ratingsPrefix${_normalizeId(albumId)}';

      Logging.severe('Deleting ratings with key: $key');

      bool removed = await prefs.remove(key);

      Logging.severe('Ratings removal success: $removed');
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

  /// Get ratings with better error handling and type conversion
  static Future<Map<int, double>?> getRatings(dynamic albumId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_ratingsPrefix${_normalizeId(albumId)}';
      final List<String>? savedRatings = prefs.getStringList(key);

      if (savedRatings == null || savedRatings.isEmpty) {
        return null;
      }

      Map<int, double> result = {};
      for (String ratingJson in savedRatings) {
        try {
          Map<String, dynamic> rating = jsonDecode(ratingJson);

          // Handle string or int trackId
          int trackId;
          if (rating['trackId'] is String) {
            trackId = int.parse(rating['trackId']);
          } else {
            trackId = rating['trackId'];
          }

          double ratingValue = rating['rating'].toDouble();
          result[trackId] = ratingValue;
        } catch (e) {
          Logging.severe('Error parsing rating: $e', e);
        }
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

  static Future<void> exportData() async {
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
        return; // User cancelled
      }

      final data = await _getAllData();
      final jsonData = jsonEncode(data);

      final file = File(outputFile);
      await file.writeAsString(jsonData);

      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Data exported to: $outputFile'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      Logging.severe('Error exporting data', e);
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Error exporting data: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static Future<bool> importData() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select backup file',
      );

      if (result == null || result.files.isEmpty) {
        return false; // User cancelled
      }

      final file = File(result.files.first.path!);
      final jsonData = await file.readAsString();
      final data = jsonDecode(jsonData);

      // Show conversion dialog
      final shouldConvert = await showDialog<bool>(
        context: navigatorKey.currentContext!,
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

      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(shouldConvert == true
              ? 'Data converted and imported successfully'
              : 'Data imported successfully'),
        ),
      );

      return true;
    } catch (e) {
      Logging.severe('Error importing data', e);
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error importing data: $e')),
      );
      return false;
    }
  }

  static Future<void> exportAlbum(Map<String, dynamic> album) async {
    try {
      final String artistName = album['artistName'] ?? 'Unknown';
      final String albumName = album['collectionName'] ?? 'Unknown';

      String fileName = '${artistName}_$albumName.json';
      // Clean filename
      fileName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save album as',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputFile == null) {
        return; // User cancelled
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

      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Album exported to: $outputFile'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      Logging.severe('Error exporting album', e);
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Error exporting album: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static Future<Map<String, dynamic>?> importAlbum() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select album file',
      );

      if (result == null || result.files.isEmpty) {
        return null; // User cancelled
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
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Error importing album: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

  static Future<String?> saveImage(String defaultFileName) async {
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

  static Future<void> migrateRatings(int albumId, List<dynamic> tracks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final oldRatingsKey = '$_ratingsPrefix$albumId';
      final oldRatings = prefs.getStringList(oldRatingsKey) ?? [];

      if (oldRatings.isEmpty) return;

      // Create new ratings with correct track IDs
      List<Map<String, dynamic>> newRatings = [];
      for (var trackObj in tracks) {
        // Handle both Map<String, dynamic> and Track objects
        int? trackId;
        int? position;

        if (trackObj is Map<String, dynamic>) {
          position = trackObj['position'] ?? trackObj['trackNumber'] ?? 0;
          trackId = trackObj['trackId'] ?? trackObj['id'];
        } else if (trackObj is Track) {
          position = trackObj.position;
          trackId = trackObj.id;
        }

        if (trackId == null) continue;

        // Find ratings by position
        for (var ratingJson in oldRatings) {
          try {
            final rating = jsonDecode(ratingJson);
            final ratingPosition =
                rating['position'] ?? rating['trackNumber'] ?? 0;

            if (ratingPosition == position) {
              final newRating = {
                'trackId': trackId,
                'rating': rating['rating'],
                'position': position,
                'timestamp':
                    rating['timestamp'] ?? DateTime.now().toIso8601String(),
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

  static Future<Map<int, Map<String, dynamic>>> migrateAlbumRatings(
      int albumId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ratingsKey = 'saved_ratings_$albumId';
      Map<int, Map<String, dynamic>> ratingsByPosition = {};

      final oldRatingsJson = prefs.getStringList(ratingsKey) ?? [];
      if (oldRatingsJson.isEmpty) return ratingsByPosition;

      final oldRatings = oldRatingsJson
          .map((r) => jsonDecode(r) as Map<String, dynamic>)
          .toList();

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
          if (!albumData.containsKey('id') &&
              !albumData.containsKey('collectionId')) {
            albumData['id'] = DateTime.now().millisecondsSinceEpoch.toString();
            modified = true;
          }

          // Handle missing or empty artwork URL
          if (!albumData.containsKey('artworkUrl100') ||
              albumData['artworkUrl100'] == null) {
            if (albumData.containsKey('artworkUrl') &&
                albumData['artworkUrl'] != null) {
              albumData['artworkUrl100'] = albumData['artworkUrl'];
              modified = true;
            }
          }

          // Handle missing artistName
          if (!albumData.containsKey('artistName') ||
              albumData['artistName'] == null) {
            if (albumData.containsKey('artist') &&
                albumData['artist'] != null) {
              albumData['artistName'] = albumData['artist'];
              modified = true;
            } else {
              albumData['artistName'] = 'Unknown Artist';
              modified = true;
            }
          }

          // Handle missing collectionName
          if (!albumData.containsKey('collectionName') ||
              albumData['collectionName'] == null) {
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

          Logging.severe(
              'Successfully converted album to unified format: ${album.name}');
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

  /// Check if an album exists in saved albums
  static Future<bool> albumExists(String albumId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];

      for (String albumJson in savedAlbums) {
        try {
          final album = jsonDecode(albumJson);
          final savedId =
              album['id']?.toString() ?? album['collectionId']?.toString();
          if (savedId == albumId) {
            return true;
          }

          // Also check URL for Bandcamp albums
          if (album['url'] != null && album['url'] == albumId) {
            return true;
          }
        } catch (e) {
          continue;
        }
      }
      return false;
    } catch (e) {
      Logging.severe('Error checking if album exists', e);
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getSavedAlbumByUrlOrId(
      String identifier) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];

      for (String albumJson in savedAlbums) {
        try {
          final album = jsonDecode(albumJson);

          // Check by ID (support both legacy and new format)
          if (album['id']?.toString() == identifier.toString() ||
              album['collectionId']?.toString() == identifier.toString()) {
            return album;
          }

          // Check by URL (for Bandcamp albums)
          if (album['url'] == identifier) {
            return album;
          }
        } catch (e) {
          Logging.severe('Error parsing album JSON', e);
          continue;
        }
      }
      return null;
    } catch (e) {
      Logging.severe('Error getting saved album', e);
      return null;
    }
  }

  /// Convert any ID type to string for storage
  static String _normalizeId(dynamic id) {
    if (id == null) return '';
    return id.toString();
  }

  /// Save rating with proper ID handling for both string and int IDs
  static Future<void> saveRating(
      dynamic albumId, dynamic trackId, double rating) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final albumKey = '$_ratingsPrefix${_normalizeId(albumId)}';
      Logging.severe('Saving rating for album key: $albumKey, track: $trackId');

      // Verify if album exists in saved albums
      final albumExists = await _verifyAlbumExists(albumId);
      if (!albumExists) {
        Logging.severe(
            'Warning: Attempting to save rating for album that may not exist: $albumId');
      }

      final List<String> ratings = prefs.getStringList(albumKey) ?? [];

      // Ensure trackId is normalized
      final normalizedTrackId = _normalizeId(trackId);

      final ratingData = {
        'trackId': normalizedTrackId,
        'rating': rating,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Update or add rating
      int existingIndex = ratings.indexWhere((ratingJson) {
        try {
          final existing = jsonDecode(ratingJson);
          return _normalizeId(existing['trackId']) == normalizedTrackId;
        } catch (e) {
          return false;
        }
      });

      if (existingIndex >= 0) {
        Logging.severe('Updating existing rating at index $existingIndex');
        ratings[existingIndex] = jsonEncode(ratingData);
      } else {
        Logging.severe('Adding new rating');
        ratings.add(jsonEncode(ratingData));
      }

      await prefs.setStringList(albumKey, ratings);
      Logging.severe(
          'Saved rating successfully. Total ratings for this album: ${ratings.length}');

      // Debug list keys to verify storage
      _debugListStoredAlbumIds(prefs);
    } catch (e, stack) {
      Logging.severe('Error saving rating', e, stack);
      rethrow;
    }
  }

  // Add this missing method
  static Future<bool> _verifyAlbumExists(dynamic albumId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> savedAlbumsJson =
          prefs.getStringList(_savedAlbumsKey) ?? [];

      final normalizedId = _normalizeId(albumId);

      for (var albumJson in savedAlbumsJson) {
        try {
          final album = jsonDecode(albumJson);
          final savedId = _normalizeId(album['id'] ?? album['collectionId']);
          if (savedId == normalizedId) {
            return true;
          }
        } catch (e) {
          continue;
        }
      }
      return false;
    } catch (e) {
      Logging.severe('Error verifying album exists: $e');
      return false;
    }
  }

  // Debug helper to list all stored album IDs
  static Future<void> _debugListStoredAlbumIds(SharedPreferences prefs) async {
    try {
      final keys =
          prefs.getKeys().where((k) => k.startsWith(_ratingsPrefix)).toList();
      Logging.severe('Stored rating keys: ${keys.join(', ')}');

      final savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];
      final savedIds = <String>[];
      for (var albumJson in savedAlbums) {
        try {
          final album = jsonDecode(albumJson);
          savedIds.add(_normalizeId(album['id'] ?? album['collectionId']));
        } catch (e) {
          continue;
        }
      }
      Logging.severe('Saved album IDs: ${savedIds.join(', ')}');
    } catch (e) {
      Logging.severe('Error listing stored album IDs', e);
    }
  }

  /// Save rating with track position information (useful for Bandcamp)
  static Future<void> saveRatingWithPosition(
      dynamic albumId, dynamic trackId, int position, double rating) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final normalizedId = _normalizeId(albumId);
      final albumKey = '$_ratingsPrefix$normalizedId';

      // Verify the album exists
      final albumExists = await _verifyAlbumExists(albumId);
      if (!albumExists) {
        Logging.severe('Cannot save rating - album does not exist: $albumId');
        return;
      }

      // Get existing ratings for this album
      final List<String> ratings = prefs.getStringList(albumKey) ?? [];

      // Create the rating with position information
      final ratingData = {
        'trackId': _normalizeId(trackId),
        'position': position,
        'rating': rating,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Update or add the rating
      int existingIndex = ratings.indexWhere((ratingJson) {
        try {
          final existing = jsonDecode(ratingJson);
          return _normalizeId(existing['trackId']) == _normalizeId(trackId) ||
              (existing['position'] == position);
        } catch (e) {
          return false;
        }
      });

      if (existingIndex >= 0) {
        ratings[existingIndex] = jsonEncode(ratingData);
      } else {
        ratings.add(jsonEncode(ratingData));
      }

      // Save the updated ratings
      await prefs.setStringList(albumKey, ratings);
      Logging.severe(
          'Saved rating with position for album $albumId, track $trackId, position $position');
    } catch (e, stack) {
      Logging.severe('Error saving rating with position', e, stack);
    }
  }

  /// Get album by ID from any source (string or int)
  static Future<Album?> getAlbumByAnyId(dynamic albumId) async {
    try {
      final normalizedId = _normalizeId(albumId);
      Logging.severe(
          'Getting album by any ID format: $albumId (normalized: $normalizedId)');

      // Try to get using unified method first
      Album? album = await getUnifiedAlbum(normalizedId);
      if (album != null) {
        Logging.severe('Found album using unified method: ${album.name}');
        return album;
      }

      // If that fails, try with int conversion for legacy method
      if (int.tryParse(normalizedId) != null) {
        album = await getSavedAlbumById(int.parse(normalizedId));
        if (album != null) {
          Logging.severe('Found album using legacy int method: ${album.name}');
          return album;
        }
      }

      // Try by string representation as last resort
      final prefs = await SharedPreferences.getInstance();
      final savedAlbums = prefs.getStringList(_savedAlbumsKey) ?? [];

      for (String json in savedAlbums) {
        try {
          final data = jsonDecode(json);
          final savedId = _normalizeId(data['id'] ?? data['collectionId']);

          if (savedId == normalizedId) {
            // Use fromLegacy if needed
            if (data.containsKey('modelVersion')) {
              album = Album.fromJson(data);
            } else {
              album = Album.fromLegacy(data);
            }

            Logging.severe('Found album using raw JSON scan: ${album.name}');
            return album;
          }
        } catch (e) {
          continue;
        }
      }

      Logging.severe('No album found with ID: $albumId');
      return null;
    } catch (e, stack) {
      Logging.severe('Error getting album by any ID', e, stack);
      return null;
    }
  }
}
