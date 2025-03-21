import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Add this import for Clipboard
import 'logging.dart';
import 'album_model.dart';

/// Utility class for debugging data issues
class DebugUtil {
  /// Diagnose issues with saved albums
  static Future<String> diagnoseSavedAlbumsIssue() async {
    final prefs = await SharedPreferences.getInstance();
    final report = StringBuffer();
    
    report.writeln('=== RateMe Debug Report ===');
    report.writeln('Generated at: ${DateTime.now().toIso8601String()}');
    report.writeln('');
    
    // Check saved albums
    final savedAlbums = prefs.getStringList('saved_albums') ?? [];
    report.writeln('Found ${savedAlbums.length} saved albums.');
    
    // Check album order
    final albumOrder = prefs.getStringList('saved_album_order') ?? [];
    report.writeln('Found ${albumOrder.length} albums in order list.');
    
    // Diagnose compatibility
    int validNewFormat = 0;
    int validLegacyFormat = 0;
    int invalidFormat = 0;
    List<String> errors = [];
    
    for (int i = 0; i < savedAlbums.length; i++) {
      try {
        final albumJson = savedAlbums[i];
        final albumData = jsonDecode(albumJson);
        
        // Check if it's in new format
        if (albumData.containsKey('modelVersion')) {
          validNewFormat++;
          continue;
        }
        
        // Check if it's valid legacy format
        if (albumData.containsKey('collectionId') && 
            albumData.containsKey('collectionName') &&
            albumData.containsKey('artistName')) {
          validLegacyFormat++;
          
          // Try to convert to make sure it can be converted
          try {
            Album.fromLegacy(albumData);
          } catch (e) {
            errors.add('Album ${i+1}: Conversion error: $e');
          }
          continue;
        }
        
        // Invalid format
        invalidFormat++;
        errors.add('Album ${i+1}: Missing required fields');
        
      } catch (e) {
        invalidFormat++;
        errors.add('Album ${i+1}: JSON parse error: $e');
      }
    }
    
    report.writeln('Valid new format albums: $validNewFormat');
    report.writeln('Valid legacy format albums: $validLegacyFormat');
    report.writeln('Invalid format albums: $invalidFormat');
    
    if (errors.isNotEmpty) {
      report.writeln('\nErrors:');
      for (final error in errors) {
        report.writeln('- $error');
      }
    }
    
    // Check custom lists
    final customLists = prefs.getStringList('custom_lists') ?? [];
    report.writeln('\nFound ${customLists.length} custom lists.');
    
    // Check ratings data
    int ratingsKeysCount = 0;
    for (final key in prefs.getKeys()) {
      if (key.startsWith('saved_ratings_')) {
        ratingsKeysCount++;
      }
    }
    report.writeln('Found ratings data for $ratingsKeysCount albums.');
    
    return report.toString();
  }
  
  /// Display debug report in a dialog
  static Future<void> showDebugReport(BuildContext context) async {
    final report = await diagnoseSavedAlbumsIssue();
    Logging.severe('Debug report: $report');
    
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Debug Report'),
          content: SingleChildScrollView(
            child: SelectableText(
              report,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: report));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Report copied to clipboard')),
                );
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }
}
