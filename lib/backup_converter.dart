import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
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

      // Import custom lists and their album relationships
      if (convertedData.containsKey('custom_lists')) {
        final db = DatabaseHelper.instance;
        for (var listData in convertedData['custom_lists']) {
          try {
            await db.insertCustomList(listData);
            final albumIds = listData['albumIds'] ?? [];
            for (int i = 0; i < albumIds.length; i++) {
              await db.addAlbumToList(albumIds[i], listData['id'], i);
            }
          } catch (e) {
            Logging.severe('Error importing custom list: $e');
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
        List<Map<String, dynamic>> newCustomLists = [];

        Logging.severe("Found ${customLists.length} custom lists to process");

        for (String listJson in customLists) {
          try {
            final listData = jsonDecode(listJson);
            final albumIds = listData['albumIds'] ?? [];
            newCustomLists.add({
              'id': listData['id'],
              'name': listData['name'],
              'description': listData['description'] ?? '',
              'albumIds': albumIds,
            });
          } catch (e) {
            Logging.severe('Error processing custom list: $e');
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
    try {
      // Read file content first
      final file = File(filePath);
      if (!await file.exists()) {
        Logging.severe('Backup file not found: $filePath');
        return;
      }
      final jsonString = await file.readAsString();

      // Use smartImport instead of individual methods to ensure the best method is chosen
      final success = await smartImport(jsonString);

      if (success) {
        Logging.severe('Completed full import using smart detection');
      } else {
        // Fall back to traditional methods if smart import failed
        await importSavedAlbumsAndRatings(filePath);
        await importCustomLists(filePath);
        await importAlbumOrder(filePath);
        Logging.severe(
            'Completed fallback full import from SharedPreferences backup');
      }
    } catch (e, stack) {
      Logging.severe('Error importing everything', e, stack);
    }
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

    // Custom lists - improved handling
    final List<dynamic> customListsRaw = prefs['custom_lists'] ?? [];
    int importedLists = 0;
    int importedListAlbums = 0;

    Logging.severe('Starting import of ${customListsRaw.length} custom lists');

    for (final listRaw in customListsRaw) {
      try {
        // Handle both Map and String formats
        Map<String, dynamic> listMap;

        if (listRaw is String) {
          listMap = json.decode(listRaw);
        } else if (listRaw is Map) {
          listMap = Map<String, dynamic>.from(listRaw);
        } else {
          continue; // Skip invalid format
        }

        // Extract albumIds with better parsing
        List<String> albumIds = [];

        // Process albumIds as either List or String
        if (listMap.containsKey('albumIds')) {
          final rawAlbumIds = listMap['albumIds'];

          if (rawAlbumIds is List) {
            albumIds = rawAlbumIds.map((id) => id.toString()).toList();
          } else if (rawAlbumIds is String) {
            try {
              // Try to parse as JSON
              final parsed = json.decode(rawAlbumIds);
              if (parsed is List) {
                albumIds = parsed.map((id) => id.toString()).toList();
              }
            } catch (_) {
              // Not valid JSON, maybe comma-separated
              albumIds = rawAlbumIds
                  .split(',')
                  .map((id) => id.trim())
                  .where((id) => id.isNotEmpty)
                  .toList();
            }
          }
        }

        // Make sure albumIds is explicitly set in the map
        listMap['albumIds'] = albumIds;

        // Log what we're going to import
        Logging.severe(
            'Importing custom list "${listMap['name']}" with ${albumIds.length} albums');

        // Use the enhanced insertCustomList method
        await db.insertCustomList(listMap);

        importedLists++;
        importedListAlbums += albumIds.length;
      } catch (e) {
        Logging.severe('Failed to import custom list: $e');
      }
    }

    Logging.severe(
        'Imported $importedLists custom lists with $importedListAlbums album relationships');

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

      // 3. Import custom lists - completely rewritten with transaction support
      if (data.containsKey('custom_lists')) {
        int listCount = 0;
        int albumRelationships = 0;

        Logging.severe('Processing custom lists from backup');
        final customListsData = data['custom_lists'];
        final List<dynamic> customLists =
            customListsData is List ? customListsData : [];

        for (final listData in customLists) {
          try {
            // Handle both string (old format) and map (new format)
            Map<String, dynamic> list;

            if (listData is String) {
              // Parse JSON string to Map
              list = json.decode(listData);
            } else if (listData is Map) {
              // Already a Map, just ensure it's the right type
              list = Map<String, dynamic>.from(listData);
            } else {
              // Unexpected format, skip
              Logging.severe('Skipping custom list with unexpected format');
              continue;
            }

            // Ensure list has required fields
            if (!list.containsKey('id') || !list.containsKey('name')) {
              Logging.severe('Skipping invalid custom list missing id or name');
              continue;
            }

            // Extract albumIds list from the custom list
            List<String> albumIds = [];

            // Check different ways albumIds might be stored
            if (list.containsKey('albumIds')) {
              if (list['albumIds'] is List) {
                albumIds = List<String>.from(list['albumIds']);
              } else if (list['albumIds'] is String) {
                try {
                  final parsed = json.decode(list['albumIds']);
                  if (parsed is List) {
                    albumIds = List<String>.from(parsed);
                  }
                } catch (_) {
                  // Not valid JSON, could be comma-separated
                  final rawIds = list['albumIds'] as String;
                  if (rawIds.isNotEmpty) {
                    albumIds = rawIds.split(',').map((e) => e.trim()).toList();
                  }
                }
              }
            }

            Logging.severe(
                'Processed custom list "${list['name']}" with ${albumIds.length} albums');

            // Add albumIds back to the list object (ensuring it's a proper List<String>)
            list['albumIds'] = albumIds;

            // Use the enhanced insertCustomList method which handles transaction and relationships
            await db.insertCustomList(list);

            listCount++;
            albumRelationships += albumIds.length;
          } catch (e) {
            Logging.severe('Error importing custom list: $e');
          }
        }

        stats['lists'] = listCount;
        stats['album_list_relationships'] = albumRelationships;
        Logging.severe(
            'Imported $listCount custom lists with $albumRelationships album relationships');
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

      // 6. After import, verify and log empty lists (but don't use undefined diagnostic class)
      try {
        // Check for any empty lists (lists with no albums) and log them
        final db = await DatabaseHelper.instance.database;

        // Get all custom lists
        final lists = await db.query('custom_lists');

        // For each list, check if it has any albums in the album_lists table
        int emptyListsCount = 0;
        for (final list in lists) {
          final listId = list['id'].toString();
          final listName = list['name'].toString();

          // Count albums for this list
          final albumCountResult = await db.rawQuery(
              'SELECT COUNT(*) as count FROM album_lists WHERE list_id = ?',
              [listId]);

          final albumCount = Sqflite.firstIntValue(albumCountResult) ?? 0;

          if (albumCount == 0) {
            emptyListsCount++;
            Logging.severe(
                'Empty list found after import: "$listName" ($listId)');
          }
        }

        if (emptyListsCount > 0) {
          Logging.severe('Found $emptyListsCount empty lists after import');
        }
      } catch (e) {
        // Silent catch - don't fail the import if verification fails
        Logging.severe('Error checking for empty lists after import: $e');
      }

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

      // Add track counter
      int trackCount = 0;

      // 1. Import albums
      if (backup.containsKey('albums')) {
        final List<dynamic> albums = backup['albums'];
        int albumCount = 0;

        for (final albumData in albums) {
          try {
            final album = Album.fromJson(albumData);
            await db.insertAlbum(album);

            // Import tracks if present - ENHANCED TO BE MORE ROBUST
            if (albumData.containsKey('tracks') &&
                albumData['tracks'] is List) {
              final albumTracks =
                  List<Map<String, dynamic>>.from(albumData['tracks']);

              if (albumTracks.isNotEmpty) {
                // Process each track to ensure it has the right format
                final processedTracks = albumTracks.map((track) {
                  // Make sure required fields are present
                  return {
                    'trackId': track['trackId'] ?? track['id'] ?? '',
                    'trackName': track['trackName'] ??
                        track['name'] ??
                        track['title'] ??
                        'Unknown Track',
                    'trackNumber':
                        track['trackNumber'] ?? track['position'] ?? 0,
                    'trackTimeMillis': track['trackTimeMillis'] ??
                        track['durationMs'] ??
                        track['duration'] ??
                        0,
                    // Include any other fields
                    ...track,
                  };
                }).toList();

                // Insert tracks into database
                await db.insertTracks(album.id.toString(), processedTracks);
                trackCount += processedTracks.length;
                Logging.severe(
                    'Imported ${processedTracks.length} tracks for album ${album.name}');
              }
            }

            albumCount++;
          } catch (e, stack) {
            Logging.severe('Error importing album: $e', e, stack);
          }
        }

        stats['albums'] = albumCount;
        stats['tracks'] = trackCount;
        Logging.severe(
            'Imported $albumCount albums with $trackCount tracks from SQLite format');
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
        int albumListRelationships = 0;

        Logging.severe('Found ${lists.length} custom lists to import');

        for (final list in lists) {
          try {
            // Extract list ID and album IDs before inserting
            final String listId = list['id']?.toString() ?? '';
            final String listName = list['name']?.toString() ?? 'Unknown list';
            List<String> albumIds = [];

            // Handle different ways albumIds might be stored
            if (list.containsKey('albumIds') && list['albumIds'] is List) {
              albumIds = List<String>.from(list['albumIds']);
            }

            Logging.severe(
                'Importing custom list "$listName" (id: $listId) with ${albumIds.length} albums: ${albumIds.take(5).join(", ")}${albumIds.length > 5 ? "..." : ""}');

            // Insert the list first
            await db.insertCustomList(list);

            // Then explicitly insert all album-list relationships
            for (int i = 0; i < albumIds.length; i++) {
              try {
                await db.addAlbumToList(albumIds[i], listId, i);
                albumListRelationships++;
              } catch (e) {
                Logging.severe(
                    'Error adding album ${albumIds[i]} to list $listId: $e');
              }
            }

            listCount++;
            Logging.severe(
                'Imported custom list: $listName with ${albumIds.length} albums');
          } catch (e) {
            Logging.severe('Error importing custom list: $e');
          }
        }

        // Verify that all lists were imported correctly
        final importedLists = await db.getAllCustomLists();
        Logging.severe(
            'After import: ${importedLists.length} lists in database (expected $listCount)');

        stats['lists'] = listCount;
        stats['album_list_relationships'] = albumListRelationships;
        Logging.severe(
            'Imported $listCount custom lists with $albumListRelationships album relationships from SQLite format');
      } else {
        Logging.severe('No custom_lists found in backup');
      }

      // 4. Import album order
      if (backup.containsKey('album_order')) {
        final List<dynamic> albumOrder = backup['album_order'];
        if (albumOrder.isNotEmpty) {
          final List<String> albumIds =
              albumOrder.map((id) => id.toString()).toList();
          await db.saveAlbumOrder(albumIds);
          // Fix: Cast num to int using toInt()
          stats['album_order'] = albumIds.length.toInt();
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

      // ENHANCED FORMAT DETECTION
      // Check for various indicators of format types
      final bool hasSqliteTables = data.containsKey('albums') &&
          (data.containsKey('ratings') || data.containsKey('tracks'));
      final bool hasSharedPrefsFormat = data.containsKey('saved_albums') ||
          data.keys.any((key) => key.startsWith('saved_ratings_'));

      // Additional check for tracks embedded inside albums
      bool hasEmbeddedTracks = false;
      if (data.containsKey('albums') &&
          data['albums'] is List &&
          (data['albums'] as List).isNotEmpty) {
        final firstAlbum = (data['albums'] as List).first;
        if (firstAlbum is Map && firstAlbum.containsKey('tracks')) {
          hasEmbeddedTracks = true;
          Logging.severe('Detected embedded tracks in albums');
        }
      }

      if (hasSqliteTables || hasEmbeddedTracks) {
        Logging.severe('Detected SQLite format backup');
        return importFromSqliteJson(jsonString);
      } else if (hasSharedPrefsFormat) {
        Logging.severe('Detected SharedPreferences format backup');
        return importFromSharedPrefsJson(jsonString);
      } else {
        Logging.severe(
            'Unknown backup format, attempting to parse as SQLite format');
        // Try SQLite format as default for unknown formats since it's more flexible
        return importFromSqliteJson(jsonString);
      }
    } catch (e, stack) {
      Logging.severe('Error in smart import', e, stack);
      return false;
    }
  }
}
