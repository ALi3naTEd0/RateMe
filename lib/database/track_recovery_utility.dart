import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_helper.dart';
import '../core/services/logging.dart';
import '../core/models/album_model.dart';
import '../platforms/platform_service_factory.dart';

/// Utility for recovering tracks for albums that don't have them
class TrackRecoveryUtility {
  /// Recover tracks for albums that have 0 tracks
  static Future<Map<String, int>> recoverMissingTracks() async {
    final db = await DatabaseHelper.instance.database;
    final stats = <String, int>{};
    stats['processed'] = 0;
    stats['recovered'] = 0;
    stats['failed'] = 0;

    // Get all albums
    final albums = await db.query('albums');
    Logging.severe('Checking ${albums.length} albums for missing tracks');

    // For each album, check if it has tracks
    for (final album in albums) {
      final albumId = album['id']?.toString() ?? '';
      if (albumId.isEmpty) continue;

      // Check if album has tracks
      final tracksCount = await _getTrackCount(albumId);
      if (tracksCount > 0) continue; // Skip if album already has tracks

      Logging.severe(
          'Album $albumId (${album['name']}) has no tracks, attempting recovery');
      stats['processed'] = (stats['processed'] ?? 0) + 1;

      // Get album data
      final dataStr = album['data'] as String?;
      if (dataStr == null || dataStr.isEmpty) {
        Logging.severe('Album $albumId has no data field, skipping');
        stats['failed'] = (stats['failed'] ?? 0) + 1;
        continue;
      }

      // Try to parse album data
      Map<String, dynamic> metadata;
      try {
        metadata = json.decode(dataStr);
      } catch (e) {
        Logging.severe('Failed to parse album data for $albumId: $e');
        stats['failed'] = (stats['failed'] ?? 0) + 1;
        continue;
      }

      // Check if the metadata has tracks
      if (metadata.containsKey('tracks') && metadata['tracks'] is List) {
        final tracksList = metadata['tracks'] as List;
        if (tracksList.isNotEmpty) {
          Logging.severe(
              'Found ${tracksList.length} tracks in metadata for album $albumId');

          // Convert tracks to proper format
          List<Map<String, dynamic>> tracks = [];
          for (final trackData in tracksList) {
            if (trackData is Map) {
              tracks.add(Map<String, dynamic>.from(trackData));
            }
          }

          if (tracks.isNotEmpty) {
            // Process each track to ensure required fields
            tracks = tracks.map((track) {
              return {
                'trackId': track['trackId'] ??
                    track['id'] ??
                    '${tracks.indexOf(track) + 1}',
                'trackName': track['trackName'] ??
                    track['name'] ??
                    'Track ${tracks.indexOf(track) + 1}',
                'trackNumber': track['trackNumber'] ??
                    track['position'] ??
                    (tracks.indexOf(track) + 1),
                'trackTimeMillis': track['trackTimeMillis'] ??
                    track['durationMs'] ??
                    track['duration'] ??
                    0,
                ...track,
              };
            }).toList();

            // Insert tracks into database
            try {
              await db.transaction((txn) async {
                // Delete any existing tracks (unlikely)
                await txn.delete('tracks',
                    where: 'album_id = ?', whereArgs: [albumId]);

                // Insert new tracks
                for (final track in tracks) {
                  await txn.insert(
                    'tracks',
                    {
                      'id': track['trackId'].toString(),
                      'album_id': albumId,
                      'name': track['trackName'].toString(),
                      'position': track['trackNumber'],
                      'duration_ms': track['trackTimeMillis'],
                      'data': json.encode(track),
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace,
                  );
                }
              });

              Logging.severe(
                  'Successfully recovered ${tracks.length} tracks for album $albumId');
              stats['recovered'] = (stats['recovered'] ?? 0) + 1;
              continue;
            } catch (e) {
              Logging.severe('Error inserting tracks for album $albumId: $e');
              stats['failed'] = (stats['failed'] ?? 0) + 1;
              continue;
            }
          }
        }
      }

      // If we're here, we couldn't recover tracks from metadata
      // Try to recover using platform service
      final platform = album['platform']?.toString().toLowerCase() ?? '';
      if (platform.isEmpty || platform == 'unknown') {
        Logging.severe('Album $albumId has unknown platform, skipping');
        stats['failed'] = (stats['failed'] ?? 0) + 1;
        continue;
      }

      // Try to recover using platform service
      try {
        final url = album['url']?.toString() ?? '';
        if (url.isEmpty) {
          Logging.severe('Album $albumId has no URL, skipping');
          stats['failed'] = (stats['failed'] ?? 0) + 1;
          continue;
        }

        // Try to get tracks using platform service
        final factoryResult =
            await _recoverTracksFromPlatform(platform, albumId, url);
        if (factoryResult) {
          Logging.severe(
              'Successfully recovered tracks for album $albumId using platform service');
          stats['recovered'] = (stats['recovered'] ?? 0) + 1;
          continue;
        }

        // If platform service failed, try to create tracks from scratch using album data
        final createResult = await _createTracksFromScratch(albumId, album);
        if (createResult) {
          Logging.severe('Created placeholder tracks for album $albumId');
          stats['recovered'] = (stats['recovered'] ?? 0) + 1;
        } else {
          Logging.severe('Failed to recover tracks for album $albumId');
          stats['failed'] = (stats['failed'] ?? 0) + 1;
        }
      } catch (e) {
        Logging.severe('Error recovering tracks for album $albumId: $e');
        stats['failed'] = (stats['failed'] ?? 0) + 1;
      }
    }

    return stats;
  }

  /// Get the number of tracks for an album
  static Future<int> _getTrackCount(String albumId) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM tracks WHERE album_id = ?', [albumId]);
    return result.first['count'] as int? ?? 0;
  }

  /// Recover tracks using platform service
  static Future<bool> _recoverTracksFromPlatform(
      String platform, String albumId, String url) async {
    try {
      final factory = PlatformServiceFactory();

      // Get the service - no need to check for null since it can't be null
      final service = factory.getService(platform);

      // Directly use the service and handle any errors in the catch block

      // Fetch album details from platform
      final albumDetails = await service.fetchAlbumDetails(url);
      // Check if we got valid album details with tracks
      if (albumDetails == null ||
          !albumDetails.containsKey('tracks') ||
          albumDetails['tracks'] is! List) {
        Logging.severe('Failed to fetch album details or no tracks found');
        return false;
      }

      final tracks =
          List<Map<String, dynamic>>.from(albumDetails['tracks'] as List);
      if (tracks.isEmpty) {
        Logging.severe('Empty tracks list returned from platform service');
        return false;
      }

      // Insert tracks
      await DatabaseHelper.instance.insertTracks(albumId, tracks);
      Logging.severe(
          'Inserted ${tracks.length} tracks for album $albumId using platform service');
      return true;
    } catch (e) {
      Logging.severe('Error recovering tracks from platform: $e');
      return false;
    }
  }

  /// Create placeholder tracks from album information
  static Future<bool> _createTracksFromScratch(
      String albumId, Map<String, dynamic> albumData) async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Try to parse album data - but don't use the result since we're just
      // creating placeholder tracks and don't need the album object
      try {
        // Just verify we can parse it
        Album.fromJson(albumData);
      } catch (e) {
        Logging.severe('Failed to parse album from database: $e');
        return false;
      }

      // First check for ratings - we can use these to determine tracks
      final ratings = await db
          .query('ratings', where: 'album_id = ?', whereArgs: [albumId]);

      if (ratings.isNotEmpty) {
        // We have ratings, use these to create tracks
        final tracks =
            await DatabaseHelper.instance.createTracksFromRatings(albumId);
        return tracks.isNotEmpty;
      }

      // No ratings, create placeholder tracks
      List<Map<String, dynamic>> placeholderTracks = [];

      // Determine a reasonable number of tracks (8-14 is typical)
      const defaultTrackCount = 10;
      for (int i = 1; i <= defaultTrackCount; i++) {
        placeholderTracks.add({
          'trackId': 'track$i',
          'trackName': 'Track $i',
          'trackNumber': i,
          'trackTimeMillis': 180000, // 3 minutes
        });
      }

      // Insert placeholder tracks
      await DatabaseHelper.instance.insertTracks(albumId, placeholderTracks);
      Logging.severe(
          'Created $defaultTrackCount placeholder tracks for album $albumId');
      return true;
    } catch (e) {
      Logging.severe('Error creating tracks from scratch: $e');
      return false;
    }
  }

  /// Analyze missing tracks and log statistics
  static Future<void> analyzeMissingTracks() async {
    final db = await DatabaseHelper.instance.database;
    final albums = await db.query('albums');

    int total = albums.length;
    int withTracks = 0;
    int withoutTracks = 0;
    Map<String, int> byPlatform = {};

    for (final album in albums) {
      final albumId = album['id']?.toString() ?? '';
      if (albumId.isEmpty) continue;

      final platform = album['platform']?.toString().toLowerCase() ?? 'unknown';
      byPlatform[platform] = (byPlatform[platform] ?? 0) + 1;

      final tracksCount = await _getTrackCount(albumId);
      if (tracksCount > 0) {
        withTracks++;
      } else {
        withoutTracks++;
      }
    }

    Logging.severe('=== TRACK ANALYSIS ===');
    Logging.severe('Total albums: $total');
    Logging.severe('Albums with tracks: $withTracks');
    Logging.severe('Albums without tracks: $withoutTracks');
    Logging.severe('By platform: $byPlatform');
    Logging.severe('=====================');
  }

  /// Run a full track recovery process
  static Future<void> runFullRecovery() async {
    Logging.severe('Starting full track recovery process');

    // Analyze current state
    await analyzeMissingTracks();

    // Recover missing tracks
    final stats = await recoverMissingTracks();

    Logging.severe('Track recovery completed:');
    Logging.severe('- Processed: ${stats['processed']} albums');
    Logging.severe('- Recovered: ${stats['recovered']} albums');
    Logging.severe('- Failed: ${stats['failed']} albums');

    // Final analysis
    await analyzeMissingTracks();
  }
}
