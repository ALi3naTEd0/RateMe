import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'album_model.dart';
import 'logging.dart';

/// Tool for converting old backup files to new model format
class BackupConverter {
  /// Convert a backup file to new format
  static Future<bool> convertBackupFile(BuildContext context) async {
    try {
      // 1. Select the old backup file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select old backup file to convert',
      );

      if (result == null || result.files.isEmpty) {
        _showSnackBar(context, 'No file selected');
        return false;
      }

      // 2. Read the file
      final file = File(result.files.first.path!);
      final jsonData = await file.readAsString();
      final data = jsonDecode(jsonData);

      // 3. Show preview dialog
      final previewResult = await _showPreviewDialog(context, data);

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
        _showSnackBar(context, 'Save cancelled');
        return false;
      }

      // 6. Write the new file
      final newFile = File(outputPath);
      await newFile.writeAsString(jsonEncode(convertedData));

      _showSnackBar(context, 'Backup converted and saved successfully!');
      return true;
    } catch (e, stack) {
      Logging.severe('Error converting backup', e, stack);
      _showSnackBar(context, 'Error converting backup: $e');
      return false;
    }
  }

  /// Import the converted backup directly
  static Future<bool> importConvertedBackup(BuildContext context) async {
    try {
      // 1. Select the old backup file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select backup file to convert and import',
      );

      if (result == null || result.files.isEmpty) {
        _showSnackBar(context, 'No file selected');
        return false;
      }

      // 2. Read the file
      final file = File(result.files.first.path!);
      final jsonData = await file.readAsString();
      final data = jsonDecode(jsonData);

      // 3. Show preview dialog
      final previewResult = await _showPreviewDialog(context, data);

      if (previewResult != true) {
        return false;
      }

      // 4. Convert data
      final convertedData = await _convertBackupData(data);

      // 5. Show confirmation dialog before replacing data
      final confirmResult = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import Converted Data'),
          content: const Text(
              'This will replace all existing data with the converted backup. Continue?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (confirmResult != true) {
        return false;
      }

      // 6. Import the converted data
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      await Future.forEach(convertedData.entries,
          (MapEntry<String, dynamic> entry) async {
        final key = entry.key;
        final value = entry.value;

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
      });

      _showSnackBar(context, 'Backup converted and imported successfully!');
      return true;
    } catch (e, stack) {
      Logging.severe('Error importing converted backup', e, stack);
      _showSnackBar(context, 'Error importing converted backup: $e');
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

  /// Show file preview dialog
  static Future<bool?> _showPreviewDialog(
      BuildContext context, Map<String, dynamic> data) async {
    int albumCount = 0;
    int listCount = 0;

    if (data.containsKey('saved_albums') && data['saved_albums'] is List) {
      albumCount = (data['saved_albums'] as List).length;
    }

    if (data.containsKey('custom_lists') && data['custom_lists'] is List) {
      listCount = (data['custom_lists'] as List).length;
    }

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert Backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Found $albumCount saved albums'),
            Text('Found $listCount custom lists'),
            const SizedBox(height: 16),
            const Text(
              'This will convert all albums to the new model format while preserving all your ratings and custom lists.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            const Text(
              'Note: This process creates a new backup file and does not modify your original backup.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
  }

  /// Show a snackbar message
  static void _showSnackBar(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
}
