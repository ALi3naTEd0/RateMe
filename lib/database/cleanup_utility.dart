import 'package:sqflite/sqflite.dart';
import '../logging.dart';
import 'database_helper.dart';
import '../platforms/platform_service_factory.dart';

/// Utility class for cleaning up database issues
class CleanupUtility {
  /// Clean up duplicate platform_matches entries
  /// Consolidates iTunes entries into Apple Music
  static Future<int> cleanupPlatformMatches() async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Count duplicates (for the same album_id and platform)
      final dupes = await db.rawQuery('''
        SELECT album_id, platform, COUNT(*) as count
        FROM platform_matches
        GROUP BY album_id, platform
        HAVING count > 1
      ''');

      Logging.severe(
          'Found ${dupes.length} album-platform pairs with duplicate entries');

      int removedCount = 0;

      // For each duplicate set, keep only the most recently verified one
      for (var dupe in dupes) {
        final albumId = dupe['album_id'];
        final platform = dupe['platform'];

        // Get all entries for this album-platform pair
        final entries = await db.query(
          'platform_matches',
          where: 'album_id = ? AND platform = ?',
          whereArgs: [albumId, platform],
          orderBy:
              'verified DESC, timestamp DESC', // Keep verified and recent ones
        );

        // Skip the first one (the one to keep)
        for (int i = 1; i < entries.length; i++) {
          final id = entries[i]['rowid'];

          // Delete this duplicate
          await db.delete(
            'platform_matches',
            where: 'rowid = ?',
            whereArgs: [id],
          );

          removedCount++;
        }
      }

      Logging.severe('Removed $removedCount duplicate platform matches');
      return removedCount;
    } catch (e, stack) {
      Logging.severe('Error cleaning up platform matches', e, stack);
      return -1;
    }
  }

  /// SQL-based fix for .0 issues in albums table (id, collectionId, and data column)
  static Future<void> fixDotZeroIssues() async {
    final db = await DatabaseHelper.instance.database;

    // 1. Fix id and collectionId columns (if they are stored as strings with .0)
    await db.execute('''
      UPDATE albums
      SET id = REPLACE(id, '.0', '')
      WHERE id LIKE '%.0'
    ''');

    await db.execute('''
      UPDATE albums
      SET collectionId = REPLACE(collectionId, '.0', '')
      WHERE collectionId LIKE '%.0'
    ''');

    // 2. Fix .0 in data column for "id" and "collectionId" keys (simple SQL replace)
    await db.execute('''
      UPDATE albums
      SET data = REPLACE(
        REPLACE(
          data, 
          '"id":"', 
          '"id":"'
        ),
        '.0"', 
        '"'
      )
      WHERE data LIKE '%"id":"%'
    ''');

    await db.execute('''
      UPDATE albums
      SET data = REPLACE(
        REPLACE(
          data, 
          '"collectionId":"', 
          '"collectionId":"'
        ),
        '.0"', 
        '"'
      )
      WHERE data LIKE '%"collectionId":"%'
    ''');

    // 3. Fix .0 in ratings table album_id and track_id columns
    await db.execute('''
      UPDATE ratings
      SET album_id = REPLACE(album_id, '.0', '')
      WHERE album_id LIKE '%.0'
    ''');

    await db.execute('''
      UPDATE ratings
      SET track_id = REPLACE(track_id, '.0', '')
      WHERE track_id LIKE '%.0'
    ''');

    // 4. Fix .0 in tracks table id and album_id columns
    await db.execute('''
      UPDATE tracks
      SET id = REPLACE(id, '.0', '')
      WHERE id LIKE '%.0'
    ''');

    await db.execute('''
      UPDATE tracks
      SET album_id = REPLACE(album_id, '.0', '')
      WHERE album_id LIKE '%.0'
    ''');

    Logging.severe('Fixed .0 issues in database columns');
  }

  /// Remove numeric-ID tracks if string-ID tracks exist for the same album/position.
  static Future<int> removeNumericIdTracksIfStringIdExists() async {
    final db = await DatabaseHelper.instance.database;
    int removed = 0;

    // Get all albums
    final albums = await db.query('albums');
    for (final album in albums) {
      final albumId = album['id'].toString();

      // Get all tracks for this album
      final tracks = await db.query(
        'tracks',
        where: 'album_id = ?',
        whereArgs: [albumId],
      );

      // Build maps by position
      final Map<int, Map<String, dynamic>> stringIdTracks = {};
      final Map<int, Map<String, dynamic>> numericIdTracks = {};

      for (final track in tracks) {
        final id = track['id']?.toString() ?? '';
        final pos = track['position'] is int
            ? track['position'] as int
            : int.tryParse(track['position']?.toString() ?? '') ?? 0;
        if (id.isEmpty || pos == 0) continue;
        if (RegExp(r'^\d+$').hasMatch(id)) {
          numericIdTracks[pos] = track;
        } else {
          stringIdTracks[pos] = track;
        }
      }

      // For each position, if both exist, remove the numeric one
      for (final pos in numericIdTracks.keys) {
        if (stringIdTracks.containsKey(pos)) {
          final track = numericIdTracks[pos]!;
          await db.delete(
            'tracks',
            where: 'id = ? AND album_id = ?',
            whereArgs: [track['id'], albumId],
          );
          removed++;
        }
      }
    }

    Logging.severe(
        'Removed $removed numeric-ID tracks where string-ID tracks exist');
    return removed;
  }

  /// For all Bandcamp albums, re-fetch tracks and update DB with real Bandcamp track IDs.
  /// Also migrates ratings from old track IDs (album1, album2, ...) to new Bandcamp IDs by track order.
  static Future<void> fixBandcampTrackIds() async {
    final db = await DatabaseHelper.instance.database;
    final albums = await db
        .query('albums', where: 'platform = ?', whereArgs: ['bandcamp']);
    int fixedAlbums = 0, fixedTracks = 0, migratedRatings = 0, skipped = 0;

    for (final album in albums) {
      final albumId = album['id'].toString();
      final url = album['url']?.toString() ?? '';
      if (!url.contains('bandcamp.com')) {
        skipped++;
        continue;
      }

      try {
        final platformFactory = PlatformServiceFactory();
        final bandcampService = platformFactory.getService('bandcamp');
        final albumDetails = await bandcampService.fetchAlbumDetails(url);

        if (albumDetails != null &&
            albumDetails['tracks'] is List &&
            (albumDetails['tracks'] as List).isNotEmpty) {
          final newTracks =
              List<Map<String, dynamic>>.from(albumDetails['tracks']);

          // Get old tracks (before deletion) and build a list sorted by position
          final oldTracks = await db.query(
            'tracks',
            where: 'album_id = ?',
            whereArgs: [albumId],
            orderBy: 'position ASC',
          );
          final oldTrackIds =
              oldTracks.map((t) => t['id']?.toString() ?? '').toList();

          // Get all ratings for this album
          final oldRatings = await db.query(
            'ratings',
            where: 'album_id = ?',
            whereArgs: [albumId],
          );

          // Remove all old tracks for this album
          await db
              .delete('tracks', where: 'album_id = ?', whereArgs: [albumId]);

          // Insert new tracks with correct IDs
          await DatabaseHelper.instance.insertTracks(albumId, newTracks);
          fixedAlbums++;
          fixedTracks += newTracks.length;

          // Migrate ratings: match by track order
          for (int i = 0; i < newTracks.length; i++) {
            final newTrackId = newTracks[i]['trackId']?.toString() ?? '';
            if (i < oldTrackIds.length) {
              final oldTrackId = oldTrackIds[i];
              // Use an empty map as the default value for firstWhere
              final ratingRow = oldRatings.firstWhere(
                (r) => r['track_id']?.toString() == oldTrackId,
                orElse: () => <String, Object?>{},
              );
              // Only insert if a rating was found (i.e., ratingRow is not empty)
              if (ratingRow.isNotEmpty) {
                await db.insert(
                  'ratings',
                  {
                    'album_id': albumId,
                    'track_id': newTrackId,
                    'rating': ratingRow['rating'],
                    'timestamp': DateTime.now().toIso8601String(),
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                migratedRatings++;
              }
            }
          }

          // Remove all ratings for old track IDs (cleanup)
          final newTrackIdSet =
              newTracks.map((t) => t['trackId']?.toString() ?? '').toSet();
          for (final rating in oldRatings) {
            final tid = rating['track_id']?.toString() ?? '';
            if (!newTrackIdSet.contains(tid)) {
              await db.delete(
                'ratings',
                where: 'album_id = ? AND track_id = ?',
                whereArgs: [albumId, tid],
              );
            }
          }

          Logging.severe(
              'Fixed Bandcamp track IDs for album $albumId (migrated $migratedRatings ratings)');
        } else {
          skipped++;
          Logging.severe('No tracks found for Bandcamp album $albumId');
        }
      } catch (e, stack) {
        Logging.severe(
            'Error fixing Bandcamp track IDs for $albumId', e, stack);
        skipped++;
      }
    }

    Logging.severe(
        'Bandcamp track ID fix: $fixedAlbums albums, $fixedTracks tracks updated, $migratedRatings ratings migrated, $skipped skipped');
  }

  /// Run all database cleanup tasks
  static Future<void> runFullCleanup() async {
    Logging.severe('Starting full database cleanup');
    try {
      // Cleanup platform matches
      final platformMatchesRemoved = await cleanupPlatformMatches();

      // Remove numeric-ID tracks if string-ID tracks exist
      final numericRemoved = await removeNumericIdTracksIfStringIdExists();

      // Vacuum database after cleanup
      final db = await DatabaseHelper.instance.database;
      await db.execute('VACUUM');
      await db.execute('ANALYZE');

      Logging.severe(
          'Full cleanup complete: removed $platformMatchesRemoved duplicate platform matches, $numericRemoved numeric-ID tracks');
    } catch (e, stack) {
      Logging.severe('Error during full cleanup', e, stack);
    }
  }
}
