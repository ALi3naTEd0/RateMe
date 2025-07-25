import 'dart:convert';
import '../services/logging.dart';
import '../services/search_service.dart';
import '../../database/database_helper.dart';

/// Utility to fix low-quality Deezer artwork in saved albums
class DeezerArtworkFixer {
  
  /// Fix artwork for all Deezer albums in the database
  static Future<Map<String, dynamic>> fixAllDeezerArtwork() async {
    try {
      Logging.severe('Starting Deezer artwork fix for all saved albums');
      
      final db = await DatabaseHelper.instance.database;
      
      // Get all Deezer albums
      final deezerAlbums = await db.query(
        'albums',
        where: 'platform = ?',
        whereArgs: ['deezer'],
      );
      
      Logging.severe('Found ${deezerAlbums.length} Deezer albums to check');
      
      int updatedCount = 0;
      int errorCount = 0;
      final List<String> updatedAlbums = [];
      
      for (final album in deezerAlbums) {
        final albumId = album['id'].toString();
        final albumName = (album['name'] ?? 'Unknown Album').toString();
        
        try {
          // Check if current artwork is low quality
          String currentArtwork = '';
          
          // Check artwork_url column first
          if (album['artwork_url'] != null) {
            currentArtwork = album['artwork_url'].toString();
          }
          
          // If no artwork_url, check data JSON
          if (currentArtwork.isEmpty && album['data'] != null) {
            try {
              final data = jsonDecode(album['data'].toString());
              currentArtwork = data['artworkUrl100'] ?? data['artworkUrl'] ?? '';
            } catch (e) {
              Logging.severe('Error parsing album data for $albumId: $e');
            }
          }
          
          // Check if artwork needs updating (if it's small/medium size or missing)
          bool needsUpdate = currentArtwork.isEmpty || 
                            currentArtwork.contains('cover_small') ||
                            currentArtwork.contains('cover_medium') ||
                            !currentArtwork.contains('cover_big');
          
          if (needsUpdate) {
            Logging.severe('Updating artwork for: $albumName (ID: $albumId)');
            
            final success = await SearchService.updateDeezerAlbumArtwork(albumId);
            
            if (success) {
              updatedCount++;
              updatedAlbums.add(albumName);
              Logging.severe('✓ Updated artwork for: $albumName');
            } else {
              errorCount++;
              Logging.severe('✗ Failed to update artwork for: $albumName');
            }
          } else {
            Logging.severe('Skipping $albumName - already has high-res artwork');
          }
          
          // Small delay to avoid rate limiting
          await Future.delayed(const Duration(milliseconds: 100));
          
        } catch (e, stack) {
          errorCount++;
          Logging.severe('Error processing album $albumName: $e', null, stack);
        }
      }
      
      final result = {
        'totalChecked': deezerAlbums.length,
        'updated': updatedCount,
        'errors': errorCount,
        'updatedAlbums': updatedAlbums,
      };
      
      Logging.severe('Deezer artwork fix completed: ${result.toString()}');
      return result;
      
    } catch (e, stack) {
      Logging.severe('Error in fixAllDeezerArtwork', e, stack);
      return {
        'totalChecked': 0,
        'updated': 0,
        'errors': 1,
        'updatedAlbums': <String>[],
        'error': e.toString(),
      };
    }
  }
  
  /// Fix artwork for a single Deezer album
  static Future<bool> fixSingleAlbumArtwork(String albumId) async {
    try {
      return await SearchService.updateDeezerAlbumArtwork(albumId);
    } catch (e, stack) {
      Logging.severe('Error fixing single album artwork', e, stack);
      return false;
    }
  }
}
