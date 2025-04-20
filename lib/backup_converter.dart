import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'database/database_helper.dart'; // Add database helper import
import 'album_model.dart';
import 'logging.dart';

/// Tool for converting old backup files to new model format
class BackupConverter {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Convert a backup file to new format - no longer needs context parameter
  static Future<bool> convertBackupFile() async {
    try {
      // 1. Select the old backup file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select old backup file to convert',
      );

      if (result == null || result.files.isEmpty) {
        _showSnackBar('No file selected');
        return false;
      }

      // 2. Read the file
      final file = File(result.files.first.path!);
      final jsonData = await file.readAsString();
      final data = jsonDecode(jsonData);

      // 3. Get navigator from global key
      final navigator = navigatorKey.currentState;
      if (navigator == null) return false;

      final previewResult = await _showPreviewDialog(data);
      if (previewResult != true) {
        return false;
      }

      // 4. Convert all albums to new format
      final convertedData = await _convertBackupData(data);

      // 5. Save the converted backup
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final newFilename = 'rateme_converted_backup_$timestamp.json';

      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save converted backup as',
        fileName: newFilename,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputPath == null) {
        _showSnackBar('Save cancelled');
        return false;
      }

      // 6. Write the new file
      final newFile = File(outputPath);
      await newFile.writeAsString(jsonEncode(convertedData));

      _showSnackBar('Backup converted and saved successfully!');
      return true;
    } catch (e, stack) {
      Logging.severe('Error converting backup', e, stack);
      _showSnackBar('Error converting backup: $e');
      return false;
    }
  }

  /// Import the converted backup directly - no longer needs context parameter
  static Future<bool> importConvertedBackup() async {
    try {
      // 1. Select the old backup file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select backup file to convert and import',
      );

      if (result == null || result.files.isEmpty) {
        _showSnackBar('No file selected');
        return false;
      }

      // 2. Read the file
      final file = File(result.files.first.path!);
      final jsonData = await file.readAsString();
      final data = jsonDecode(jsonData);

      // 3. Show preview dialog using navigator key
      final previewResult = await _showPreviewDialog(data);
      if (previewResult != true) {
        return false;
      }

      // 4. Convert data
      final convertedData = await _convertBackupData(data);

      // 5. Show confirmation dialog before replacing data
      final confirmResult = await _showConfirmationDialog();
      if (confirmResult != true) {
        return false;
      }

      // 6. Import the converted data
      final db = DatabaseHelper.instance;

      // For each album in the backup
      for (var albumData in convertedData['saved_albums']) {
        try {
          final album = Album.fromJson(jsonDecode(albumData));
          await db.insertAlbum(album);
        } catch (e) {
          Logging.severe('Error importing album: $e');
        }
      }

      // For each rating in the backup
      for (String key in convertedData.keys) {
        if (key.startsWith('saved_ratings_')) {
          for (var ratingData in convertedData[key]) {
            try {
              final rating = jsonDecode(ratingData);
              final albumId = rating['albumId'];
              final trackId = rating['trackId'];
              final ratingValue = rating['rating']?.toDouble() ?? 0.0;

              await db.saveRating(albumId, trackId, ratingValue);
            } catch (e) {
              Logging.severe('Error importing rating: $e');
            }
          }
        }
      }

      _showSnackBar('Backup converted and imported successfully!');
      return true;
    } catch (e, stack) {
      Logging.severe('Error importing converted backup', e, stack);
      _showSnackBar('Error importing converted backup: $e');
      return false;
    }
  }

  /// Convert backup data to new format
  static Future<Map<String, dynamic>> _convertBackupData(
      Map<String, dynamic> data) async {
    final newData = Map<String, dynamic>.from(data);

    try {
      // Detailed logging
      Logging.severe("Starting backup conversion process");
      Logging.severe("Backup keys found: ${data.keys.join(', ')}");

      // Convert saved albums if they exist
      if (data.containsKey('saved_albums') && data['saved_albums'] is List) {
        List<String> savedAlbums = List<String>.from(data['saved_albums']);
        List<String> newSavedAlbums = [];
        List<String> newAlbumIds = [];

        Logging.severe("Found ${savedAlbums.length} albums to convert");

        int successCount = 0;
        int failureCount = 0;

        for (int i = 0; i < savedAlbums.length; i++) {
          try {
            String albumJson = savedAlbums[i];
            Map<String, dynamic> albumData = jsonDecode(albumJson);

            // Attempt conversion to new format
            Album? album;
            try {
              album = Album.fromLegacy(albumData);
              successCount++;
            } catch (e) {
              Logging.severe(
                  "Failed to convert album directly, applying fixes: $e");

              // Apply fixes to common issues:
              if (!albumData.containsKey('collectionId') &&
                  albumData.containsKey('id')) {
                albumData['collectionId'] = albumData['id'];
                Logging.severe("Fixed missing collectionId using id");
              }

              if (!albumData.containsKey('artistName') &&
                  albumData.containsKey('artist')) {
                albumData['artistName'] = albumData['artist'];
                Logging.severe("Fixed missing artistName using artist");
              }

              if (!albumData.containsKey('collectionName') &&
                  albumData.containsKey('name')) {
                albumData['collectionName'] = albumData['name'];
                Logging.severe("Fixed missing collectionName using name");
              }

              // Try conversion again after fixes
              try {
                album = Album.fromLegacy(albumData);
                successCount++;
                Logging.severe("Successfully converted album after fixes");
              } catch (e2) {
                // Keep the original if it still fails
                Logging.severe("Album conversion failed even after fixes: $e2");
                failureCount++;
                newSavedAlbums.add(albumJson);
                continue;
              }
            }

            // If conversion succeeded, add to new list
            String newAlbumJson = jsonEncode(album.toJson());
            newSavedAlbums.add(newAlbumJson);
            newAlbumIds.add(album.id.toString());
            Logging.severe("Successfully converted album: ${album.name}");
          } catch (e) {
            Logging.severe("Error processing album ${i + 1}: $e");
            failureCount++;
            // Keep the original on any error
            newSavedAlbums.add(savedAlbums[i]);
          }
        }

        Logging.severe(
            "Album conversion summary: $successCount succeeded, $failureCount failed");

        newData['saved_albums'] = newSavedAlbums;

        // Handle album order - either use existing order or create a new one
        if (!data.containsKey('saved_album_order') ||
            (data['saved_album_order'] as List).isEmpty) {
          newData['saved_album_order'] = newAlbumIds;
          Logging.severe(
              "Created new album order with ${newAlbumIds.length} albums");
        } else {
          // Keep original order when possible, but make sure all albums are included
          List<String> albumOrder =
              List<String>.from(data['saved_album_order']);

          // Add any new albums that aren't in the order
          for (String albumId in newAlbumIds) {
            if (!albumOrder.contains(albumId)) {
              albumOrder.add(albumId);
            }
          }

          newData['saved_album_order'] = albumOrder;
          Logging.severe(
              "Preserved and extended album order to ${albumOrder.length} albums");
        }
      }

      // Process custom lists if present
      if (data.containsKey('custom_lists') && data['custom_lists'] is List) {
        List<String> customLists = List<String>.from(data['custom_lists']);
        List<String> newCustomLists = [];

        Logging.severe("Found ${customLists.length} custom lists to process");

        for (int i = 0; i < customLists.length; i++) {
          try {
            Map<String, dynamic> list = jsonDecode(customLists[i]);

            // Ensure list has required fields
            if (!list.containsKey('id')) {
              list['id'] = DateTime.now().millisecondsSinceEpoch.toString();
            }

            if (!list.containsKey('albumIds') || list['albumIds'] == null) {
              list['albumIds'] = [];
            } else if (list['albumIds'] is! List) {
              list['albumIds'] = [];
            }

            // Clean up album IDs (remove nulls and duplicates)
            List<String> albumIds = [];
            for (var id in list['albumIds']) {
              if (id != null && id.toString().isNotEmpty) {
                albumIds.add(id.toString());
              }
            }

            // Remove duplicates
            list['albumIds'] = albumIds.toSet().toList();

            // Add timestamps if missing
            if (!list.containsKey('createdAt')) {
              list['createdAt'] = DateTime.now().toIso8601String();
            }

            if (!list.containsKey('updatedAt')) {
              list['updatedAt'] = DateTime.now().toIso8601String();
            }

            newCustomLists.add(jsonEncode(list));
            Logging.severe(
                "Processed custom list: ${list['name']} with ${list['albumIds'].length} albums");
          } catch (e) {
            Logging.severe("Error processing custom list ${i + 1}: $e");
            // Keep original on error
            newCustomLists.add(customLists[i]);
          }
        }

        newData['custom_lists'] = newCustomLists;
      }

      // Process ratings data
      int ratingsKeysCount = 0;
      for (String key in data.keys) {
        if (key.startsWith('saved_ratings_')) {
          ratingsKeysCount++;

          try {
            List<String> ratings = List<String>.from(data[key]);
            List<String> cleanedRatings = [];

            for (String ratingJson in ratings) {
              try {
                Map<String, dynamic> rating = jsonDecode(ratingJson);

                // Ensure all required fields exist
                if (!rating.containsKey('trackId')) {
                  continue; // Skip invalid ratings
                }

                if (!rating.containsKey('position') &&
                    rating.containsKey('trackNumber')) {
                  rating['position'] = rating['trackNumber'];
                }

                if (!rating.containsKey('rating')) {
                  continue; // Skip ratings without a value
                }

                if (!rating.containsKey('timestamp')) {
                  rating['timestamp'] = DateTime.now().toIso8601String();
                }

                cleanedRatings.add(jsonEncode(rating));
              } catch (e) {
                Logging.severe("Error processing rating: $e");
                // Keep original on error
                cleanedRatings.add(ratingJson);
              }
            }

            newData[key] = cleanedRatings;
          } catch (e) {
            Logging.severe("Error processing ratings for $key: $e");
            // Keep original data for this key
          }
        }
      }

      Logging.severe("Processed ratings data for $ratingsKeysCount albums");

      // Add metadata about the conversion
      newData['_conversion'] = {
        'timestamp': DateTime.now().toIso8601String(),
        'version': 1,
      };

      return newData;
    } catch (e, stack) {
      Logging.severe('Error in _convertBackupData', e, stack);
      return data; // Return original data if conversion fails
    }
  }

  /// Show file preview dialog using GlobalKey
  static Future<bool?> _showPreviewDialog(Map<String, dynamic> data) {
    int albumCount = data['saved_albums']?.length ?? 0;
    int listCount = data['custom_lists']?.length ?? 0;

    final navigator = navigatorKey.currentState;
    if (navigator == null) return Future.value(false);

    return navigator.push<bool>(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Convert Backup',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text('Found $albumCount saved albums'),
                  Text('Found $listCount custom lists'),
                  const SizedBox(height: 16),
                  const Text(
                    'This will convert all albums to the new model format while preserving all your ratings and custom lists.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => navigator.pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => navigator.pop(true),
                        child: const Text('Convert'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Show confirmation dialog using GlobalKey
  static Future<bool?> _showConfirmationDialog() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return Future.value(false);

    return navigator.push<bool>(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Import Converted Data',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                      'This will replace all existing data with the converted backup. Continue?'),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => navigator.pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => navigator.pop(true),
                        child: const Text('Import'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Show a snackbar message using the global key
  static void _showSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Import albums, ratings, lists, etc. from a JSON backup file
  static Future<void> importFromJsonFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Logging.severe('Backup file not found: $filePath');
        return;
      }
      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString);

      final db = DatabaseHelper.instance;

      // Import albums
      if (data['albums'] is List) {
        for (final albumJson in data['albums']) {
          try {
            final album = Album.fromJson(albumJson);
            await db.insertAlbum(album);
          } catch (e) {
            Logging.severe('Failed to import album: $e');
          }
        }
      }

      // Import ratings
      if (data['ratings'] is List) {
        for (final rating in data['ratings']) {
          try {
            await db.saveRating(
              rating['albumId'].toString(),
              rating['trackId'].toString(),
              (rating['rating'] as num).toDouble(),
            );
          } catch (e) {
            Logging.severe('Failed to import rating: $e');
          }
        }
      }

      // Import custom lists and album-list relationships
      if (data['lists'] is List) {
        for (final list in data['lists']) {
          try {
            // Insert the list metadata
            await db.insertCustomList(list);

            // Insert album-list relationships if present
            if (list['albumIds'] is List) {
              final albumIds = List<String>.from(list['albumIds']);
              for (int i = 0; i < albumIds.length; i++) {
                await db.addAlbumToList(albumIds[i], list['id'], i);
              }
            }
          } catch (e) {
            Logging.severe('Failed to import list: $e');
          }
        }
      }

      Logging.severe('Backup import completed from $filePath');
    } catch (e, stack) {
      Logging.severe('Error importing backup', e, stack);
    }
  }

  /// Import from a SharedPreferences-style JSON backup
  static Future<void> importSharedPrefsBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Logging.severe('Backup file not found: $filePath');
        return;
      }
      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString);

      final db = DatabaseHelper.instance;

      // Import albums
      if (data['saved_albums'] is List) {
        for (final albumStr in data['saved_albums']) {
          try {
            final albumJson = jsonDecode(albumStr);
            // You may need to adapt this if Album.fromJson doesn't match legacy format
            final album = Album.fromJson(albumJson);
            await db.insertAlbum(album);
          } catch (e) {
            Logging.severe('Failed to import album: $e');
          }
        }
      }

      // Import ratings
      for (final key in data.keys) {
        if (key.startsWith('saved_ratings_')) {
          final albumId = key.replaceFirst('saved_ratings_', '');
          final ratingsList = data[key];
          if (ratingsList is List) {
            for (final ratingStr in ratingsList) {
              try {
                final ratingJson = jsonDecode(ratingStr);
                final trackId = ratingJson['trackId'].toString();
                final rating = (ratingJson['rating'] as num).toDouble();
                await db.saveRating(albumId, trackId, rating);
              } catch (e) {
                Logging.severe('Failed to import rating: $e');
              }
            }
          }
        }
      }

      Logging.severe(
          'SharedPreferences backup import completed from $filePath');
    } catch (e, stack) {
      Logging.severe('Error importing SharedPreferences backup', e, stack);
    }
  }

  /// Import albums from SharedPreferences-style "saved_albums" backup
  static Future<void> importSavedAlbums(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Logging.severe('Backup file not found: $filePath');
        return;
      }
      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString);

      final db = DatabaseHelper.instance;

      // Import albums
      if (data['saved_albums'] is List) {
        int count = 0;
        for (final albumStr in data['saved_albums']) {
          try {
            final albumJson = jsonDecode(albumStr);
            // Use fromLegacy for best compatibility with old format
            final album = Album.fromLegacy(albumJson);
            await db.insertAlbum(album);
            count++;
          } catch (e) {
            Logging.severe('Failed to import album: $e');
          }
        }
        Logging.severe('Imported $count albums from saved_albums');
      } else {
        Logging.severe('No saved_albums found in backup');
      }
    } catch (e, stack) {
      Logging.severe('Error importing saved_albums', e, stack);
    }
  }

  /// Import albums and ratings from SharedPreferences-style backup
  static Future<void> importSavedAlbumsAndRatings(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Logging.severe('Backup file not found: $filePath');
        return;
      }
      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString);

      final db = DatabaseHelper.instance;

      // Import albums
      if (data['saved_albums'] is List) {
        int count = 0;
        for (final albumStr in data['saved_albums']) {
          try {
            final albumJson = jsonDecode(albumStr);
            // Use fromLegacy for best compatibility with old format
            final album = Album.fromLegacy(albumJson);
            await db.insertAlbum(album);
            count++;
          } catch (e) {
            Logging.severe('Failed to import album: $e');
          }
        }
        Logging.severe('Imported $count albums from saved_albums');
      } else {
        Logging.severe('No saved_albums found in backup');
      }

      // Import ratings
      int ratingsCount = 0;
      for (final key in data.keys) {
        if (key.startsWith('saved_ratings_')) {
          final albumId = key.replaceFirst('saved_ratings_', '');
          final ratingsList = data[key];
          if (ratingsList is List) {
            for (final ratingStr in ratingsList) {
              try {
                final ratingJson = jsonDecode(ratingStr);
                final trackId = ratingJson['trackId'].toString();
                final rating = (ratingJson['rating'] as num).toDouble();
                await db.saveRating(albumId, trackId, rating);
                ratingsCount++;
              } catch (e) {
                Logging.severe('Failed to import rating: $e');
              }
            }
          }
        }
      }
      Logging.severe('Imported $ratingsCount ratings from backup');
    } catch (e, stack) {
      Logging.severe('Error importing saved albums/ratings', e, stack);
    }
  }

  /// Import custom lists from SharedPreferences-style "custom_lists" backup
  static Future<void> importCustomLists(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Logging.severe('Backup file not found: $filePath');
        return;
      }
      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString);

      final db = DatabaseHelper.instance;

      // Import custom lists
      if (data['custom_lists'] is List) {
        int count = 0;
        for (final listStr in data['custom_lists']) {
          try {
            final listJson = jsonDecode(listStr);

            // Insert the list metadata
            await db.insertCustomList(listJson);

            // Insert album-list relationships if present
            if (listJson['albumIds'] is List) {
              final albumIds = List<String>.from(listJson['albumIds']);
              for (int i = 0; i < albumIds.length; i++) {
                await db.addAlbumToList(albumIds[i], listJson['id'], i);
              }
            }
            count++;
          } catch (e) {
            Logging.severe('Failed to import custom list: $e');
          }
        }
        Logging.severe('Imported $count custom lists from custom_lists');
      } else {
        Logging.severe('No custom_lists found in backup');
      }
    } catch (e, stack) {
      Logging.severe('Error importing custom_lists', e, stack);
    }
  }

  /// Import album order from SharedPreferences-style "savedAlbumsOrder"
  static Future<void> importAlbumOrder(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Logging.severe('Backup file not found: $filePath');
        return;
      }
      final jsonString = await file.readAsString();
      final data = jsonDecode(jsonString);

      final db = DatabaseHelper.instance;

      if (data['savedAlbumsOrder'] is List) {
        final albumOrder = List<String>.from(data['savedAlbumsOrder']);
        await db.saveAlbumOrder(albumOrder);
        Logging.severe('Imported album order with ${albumOrder.length} albums');
      } else {
        Logging.severe('No savedAlbumsOrder found in backup');
      }
    } catch (e, stack) {
      Logging.severe('Error importing album order', e, stack);
    }
  }

  /// Import everything from SharedPreferences-style backup
  static Future<void> importAll(String filePath) async {
    await importSavedAlbumsAndRatings(filePath);
    await importCustomLists(filePath);
    await importAlbumOrder(filePath);
    Logging.severe('Completed full import from SharedPreferences backup');
  }

  /// Import from a SharedPreferences-style JSON string.
  static Future<void> importFromSharedPrefsJsonString(String jsonString) async {
    final db = DatabaseHelper.instance;
    final Map<String, dynamic> prefs = json.decode(jsonString);

    // Albums
    final List<String> savedAlbums =
        List<String>.from(prefs['saved_albums'] ?? []);
    int importedAlbums = 0;
    for (final albumJson in savedAlbums) {
      try {
        final albumMap = json.decode(albumJson);
        final album = Album.fromLegacy(albumMap);
        await db.insertAlbum(album);
        importedAlbums++;
      } catch (e) {
        Logging.severe('Failed to import album: $e');
      }
    }
    Logging.severe('Imported $importedAlbums albums from saved_albums');

    // Ratings
    int importedRatings = 0;
    for (final key in prefs.keys) {
      if (key.startsWith('saved_ratings_')) {
        final albumId = key.replaceFirst('saved_ratings_', '');
        final List<String> ratingsList = List<String>.from(prefs[key] ?? []);
        for (final ratingJson in ratingsList) {
          try {
            final ratingMap = json.decode(ratingJson);
            final trackId = ratingMap['trackId'].toString();
            final rating = (ratingMap['rating'] as num?)?.toDouble() ?? 0.0;
            await db.saveRating(albumId, trackId, rating);
            importedRatings++;
          } catch (e) {
            Logging.severe('Failed to import rating: $e');
          }
        }
      }
    }
    Logging.severe('Imported $importedRatings ratings from backup');

    // Custom lists
    final List<String> customLists =
        List<String>.from(prefs['custom_lists'] ?? []);
    int importedLists = 0;
    for (final listJson in customLists) {
      try {
        final listMap = json.decode(listJson);
        await db.insertCustomList(listMap);
        // Insert album-list relationships if present
        if (listMap['albumIds'] is List) {
          final albumIds = List<String>.from(listMap['albumIds']);
          for (int i = 0; i < albumIds.length; i++) {
            await db.addAlbumToList(albumIds[i], listMap['id'], i);
          }
        }
        importedLists++;
      } catch (e) {
        Logging.severe('Failed to import custom list: $e');
      }
    }
    Logging.severe('Imported $importedLists custom lists from custom_lists');

    // Album order
    final List<String> albumOrder =
        List<String>.from(prefs['album_order'] ?? []);
    if (albumOrder.isNotEmpty) {
      await db.saveAlbumOrder(albumOrder);
      Logging.severe('Imported album order with ${albumOrder.length} albums');
    }

    Logging.severe('Completed full import from SharedPreferences backup');
  }

  /// Import data from a SharedPreferences-style JSON backup
  static Future<bool> importFromSharedPrefsJson(String jsonString) async {
    try {
      Logging.severe('Importing from SharedPreferences format JSON');

      final Map<String, dynamic> data = json.decode(jsonString);
      final db = DatabaseHelper.instance;

      // Track what we've imported
      final stats = <String, int>{};

      // 1. Import albums
      if (data.containsKey('saved_albums')) {
        final List<dynamic> albumJsons = data['saved_albums'];
        int albumCount = 0;

        for (final albumJson in albumJsons) {
          try {
            // Handle both string (old format) and map (new format) album entries
            final Map<String, dynamic> albumData =
                albumJson is String ? json.decode(albumJson) : albumJson;

            // Convert to Album object and save
            final album = Album.fromJson(albumData);
            await db.insertAlbum(album);
            albumCount++;
          } catch (e) {
            Logging.severe('Error importing album: $e');
          }
        }

        stats['albums'] = albumCount;
        Logging.severe('Imported $albumCount albums');
      }

      // 2. Import ratings
      int ratingCount = 0;
      for (final key in data.keys) {
        if (key.startsWith('saved_ratings_')) {
          final albumId = key.replaceFirst('saved_ratings_', '');
          final List<dynamic> ratingJsons = data[key];

          for (final ratingJson in ratingJsons) {
            try {
              // Handle both string (old format) and map (new format) rating entries
              final Map<String, dynamic> ratingData =
                  ratingJson is String ? json.decode(ratingJson) : ratingJson;

              final trackId = ratingData['trackId'].toString();
              final rating = (ratingData['rating'] is num)
                  ? (ratingData['rating'] as num).toDouble()
                  : double.parse(ratingData['rating'].toString());

              await db.saveRating(albumId, trackId, rating);
              ratingCount++;
            } catch (e) {
              Logging.severe('Error importing rating: $e');
            }
          }
        }
      }

      stats['ratings'] = ratingCount;
      Logging.severe('Imported $ratingCount ratings');

      // 3. Import custom lists
      if (data.containsKey('custom_lists')) {
        final List<dynamic> listJsons = data['custom_lists'];
        int listCount = 0;

        for (final listJson in listJsons) {
          try {
            // Handle both string (old format) and map (new format) list entries
            final Map<String, dynamic> listData =
                listJson is String ? json.decode(listJson) : listJson;

            await db.insertCustomList(listData);
            listCount++;
          } catch (e) {
            Logging.severe('Error importing custom list: $e');
          }
        }

        stats['lists'] = listCount;
        Logging.severe('Imported $listCount custom lists');
      }

      // 4. Import album order
      if (data.containsKey('album_order')) {
        final List<dynamic> albumOrder = data['album_order'];
        if (albumOrder.isNotEmpty) {
          final List<String> albumIds =
              albumOrder.map((id) => id.toString()).toList();
          await db.saveAlbumOrder(albumIds);
          stats['album_order'] = albumIds.length;
          Logging.severe('Imported album order with ${albumIds.length} items');
        }
      }

      // 5. Import settings
      int settingsCount = 0;
      for (final key in data.keys) {
        // Skip known list/array keys we've already processed
        if (key == 'saved_albums' ||
            key == 'custom_lists' ||
            key == 'album_order' ||
            key.startsWith('saved_ratings_')) {
          continue;
        }

        try {
          final value = data[key];
          if (value != null) {
            await db.saveSetting(key, value.toString());
            settingsCount++;
          }
        } catch (e) {
          Logging.severe('Error importing setting $key: $e');
        }
      }

      stats['settings'] = settingsCount;
      Logging.severe('Imported $settingsCount settings');

      // Log overall import stats
      Logging.severe('Import completed: $stats');
      return true;
    } catch (e, stack) {
      Logging.severe('Error importing from SharedPreferences JSON', e, stack);
      return false;
    }
  }

  /// Import data from newer SQLite-compatible JSON backup
  static Future<bool> importFromSqliteJson(String jsonString) async {
    try {
      Logging.severe('Importing from SQLite format JSON');

      final Map<String, dynamic> backup = json.decode(jsonString);
      final db = DatabaseHelper.instance;

      // Track import stats
      final stats = <String, int>{};

      // 1. Import albums
      if (backup.containsKey('albums')) {
        final List<dynamic> albums = backup['albums'];
        int albumCount = 0;

        for (final albumData in albums) {
          try {
            final album = Album.fromJson(albumData);
            await db.insertAlbum(album);

            // Import tracks if present
            if (albumData.containsKey('tracks') &&
                albumData['tracks'] is List) {
              await db.insertTracks(album.id,
                  List<Map<String, dynamic>>.from(albumData['tracks']));
            }
            albumCount++;
          } catch (e) {
            Logging.severe('Error importing album: $e');
          }
        }

        stats['albums'] = albumCount;
        Logging.severe('Imported $albumCount albums from SQLite format');
      }

      // 2. Import ratings
      if (backup.containsKey('ratings')) {
        final List<dynamic> ratings = backup['ratings'];
        int ratingCount = 0;

        for (final rating in ratings) {
          try {
            final albumId = rating['album_id'].toString();
            final trackId = rating['track_id'].toString();
            final ratingValue = (rating['rating'] is num)
                ? (rating['rating'] as num).toDouble()
                : double.parse(rating['rating'].toString());

            await db.saveRating(albumId, trackId, ratingValue);
            ratingCount++;
          } catch (e) {
            Logging.severe('Error importing rating: $e');
          }
        }

        stats['ratings'] = ratingCount;
        Logging.severe('Imported $ratingCount ratings from SQLite format');
      }

      // 3. Import custom lists
      if (backup.containsKey('custom_lists')) {
        final List<dynamic> lists = backup['custom_lists'];
        int listCount = 0;

        for (final list in lists) {
          try {
            await db.insertCustomList(list);
            listCount++;
          } catch (e) {
            Logging.severe('Error importing custom list: $e');
          }
        }

        stats['lists'] = listCount;
        Logging.severe('Imported $listCount custom lists from SQLite format');
      }

      // 4. Import album order
      if (backup.containsKey('album_order')) {
        final List<dynamic> albumOrder = backup['album_order'];
        if (albumOrder.isNotEmpty) {
          final List<String> albumIds =
              albumOrder.map((id) => id.toString()).toList();
          await db.saveAlbumOrder(albumIds);
          stats['album_order'] = albumIds.length;
          Logging.severe('Imported album order from SQLite format');
        }
      }

      // 5. Import settings
      if (backup.containsKey('settings')) {
        final List<dynamic> settings = backup['settings'];
        int settingsCount = 0;

        for (final setting in settings) {
          try {
            final key = setting['key'].toString();
            final value = setting['value'].toString();
            await db.saveSetting(key, value);
            settingsCount++;
          } catch (e) {
            Logging.severe('Error importing setting: $e');
          }
        }

        stats['settings'] = settingsCount;
        Logging.severe('Imported $settingsCount settings from SQLite format');
      }

      Logging.severe('Import from SQLite format completed: $stats');
      return true;
    } catch (e, stack) {
      Logging.severe('Error importing from SQLite JSON', e, stack);
      return false;
    }
  }

  /// Smart import that detects format based on JSON structure
  static Future<bool> smartImport(String jsonString) async {
    try {
      Logging.severe('Smart import: Detecting backup format...');

      final Map<String, dynamic> data = json.decode(jsonString);

      // Detect format based on structure
      bool isSqliteFormat =
          data.containsKey('albums') && data.containsKey('ratings');
      bool isSharedPrefsFormat = data.containsKey('saved_albums') ||
          data.keys.any((key) => key.startsWith('saved_ratings_'));

      if (isSqliteFormat) {
        Logging.severe('Detected SQLite format backup');
        return importFromSqliteJson(jsonString);
      } else if (isSharedPrefsFormat) {
        Logging.severe('Detected SharedPreferences format backup');
        return importFromSharedPrefsJson(jsonString);
      } else {
        Logging.severe('Unknown backup format');
        return false;
      }
    } catch (e, stack) {
      Logging.severe('Error in smart import', e, stack);
      return false;
    }
  }
}
