import 'dart:convert';
import '../../core/models/album_model.dart';
import '../../core/services/logging.dart';

/// Utility class to help with data model migration
class MigrationUtil {
  /// Safely convert legacy album data to Album model
  static Album? safeConvertToAlbum(Map<String, dynamic> legacyAlbum) {
    try {
      return Album.fromLegacy(legacyAlbum);
    } catch (e, stack) {
      Logging.severe('Failed to convert album to model', e, stack);
      return null;
    }
  }

  /// Check if an album can be converted to the model format
  static bool canConvertToModel(Map<String, dynamic> legacyAlbum) {
    try {
      Album.fromLegacy(legacyAlbum);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Pretty-print album data for debugging
  static String prettyPrintAlbum(Map<String, dynamic> album) {
    const encoder = JsonEncoder.withIndent('  ');
    try {
      return encoder.convert({
        'id': album['collectionId'],
        'name': album['collectionName'],
        'artist': album['artistName'],
        'platform': album['url']?.toString().contains('bandcamp.com') == true
            ? 'bandcamp'
            : 'itunes',
      });
    } catch (e) {
      return 'Invalid album format: $e';
    }
  }

  /// Check if tracks can be converted to Track model
  static bool validateTracks(List<dynamic> tracks, bool isBandcamp) {
    try {
      for (var trackData in tracks) {
        // Fix: Don't pass index to Track.fromLegacy - use Map instead
        Track.fromLegacy(Map<String, dynamic>.from(trackData));
      }
      return true;
    } catch (e) {
      Logging.severe('Track validation failed', e);
      return false;
    }
  }
}
