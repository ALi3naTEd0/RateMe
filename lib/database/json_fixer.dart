import 'dart:convert';
import 'package:rateme/database/database_helper.dart';
import 'package:rateme/logging.dart';

/// Utility to fix albums with invalid JSON in the 'data' field.
class JsonFixer {
  /// Run this to fix all albums in the database.
  static Future<void> fixAlbumDataFields() async {
    final db = await DatabaseHelper.instance.database;
    final albums = await db.query('albums');
    int fixed = 0, skipped = 0, total = albums.length;

    for (final album in albums) {
      final id = album['id']?.toString() ?? '';
      final dataField = album['data'];
      if (dataField == null || dataField is! String) {
        skipped++;
        continue;
      }

      // Try to parse as JSON
      try {
        json.decode(dataField);
        skipped++;
        continue;
      } catch (_) {
        // Not valid JSON, try to convert Dart map string to JSON
        try {
          String dartMap = dataField.trim();

          // Remove leading/trailing braces
          if (dartMap.startsWith('{') && dartMap.endsWith('}')) {
            dartMap = dartMap.substring(1, dartMap.length - 1);
          }

          // Split by comma, but not inside quotes
          final entries = <String>[];
          int bracket = 0;
          String current = '';
          for (int i = 0; i < dartMap.length; i++) {
            final c = dartMap[i];
            if (c == ',' && bracket == 0) {
              entries.add(current);
              current = '';
            } else {
              if (c == '{') bracket++;
              if (c == '}') bracket--;
              current += c;
            }
          }
          if (current.isNotEmpty) entries.add(current);

          final map = <String, dynamic>{};
          for (final entry in entries) {
            final idx = entry.indexOf(':');
            if (idx == -1) continue;
            final key = entry.substring(0, idx).trim();
            final value = entry.substring(idx + 1).trim();

            // Remove possible quotes from key
            String jsonKey = key;
            if ((jsonKey.startsWith("'") && jsonKey.endsWith("'")) ||
                (jsonKey.startsWith('"') && jsonKey.endsWith('"'))) {
              jsonKey = jsonKey.substring(1, jsonKey.length - 1);
            }

            // Try to parse value as number, bool, or keep as string
            dynamic jsonValue;
            if (value == 'null') {
              jsonValue = null;
            } else if (value == 'true') {
              jsonValue = true;
            } else if (value == 'false') {
              jsonValue = false;
            } else if (double.tryParse(value) != null) {
              // If the key is 'id', 'collectionId', or 'album_id', always save as string!
              if (jsonKey == 'id' ||
                  jsonKey == 'collectionId' ||
                  jsonKey == 'album_id') {
                jsonValue = value.replaceAll('.0', '');
              } else {
                jsonValue = double.parse(value);
              }
            } else {
              // Remove possible quotes from value
              String cleanedValue = value;
              if ((cleanedValue.startsWith("'") &&
                      cleanedValue.endsWith("'")) ||
                  (cleanedValue.startsWith('"') &&
                      cleanedValue.endsWith('"'))) {
                cleanedValue =
                    cleanedValue.substring(1, cleanedValue.length - 1);
              }
              jsonValue = cleanedValue;
            }

            map[jsonKey] = jsonValue;
          }

          // Save as JSON
          await db.update(
            'albums',
            {'data': json.encode(map)},
            where: 'id = ?',
            whereArgs: [id],
          );
          Logging.severe('Fixed album $id');
          fixed++;
        } catch (e) {
          Logging.severe('Failed to fix album $id: $e');
          skipped++;
        }
      }
    }

    Logging.severe('JSON Fixer: $fixed fixed, $skipped skipped, $total total');
  }

  /// Fix double IDs in album data JSON (e.g. 1771925266.0 -> "1771925266")
  static Future<void> fixDoubleIdsInAlbumData() async {
    final db = await DatabaseHelper.instance.database;
    final albums = await db.query('albums');
    int fixed = 0, skipped = 0, total = albums.length;

    for (final album in albums) {
      // Explicitly fix the album id and collectionId in the albums table itself (not just in JSON)
      String? dbId = album['id']?.toString();
      String? dbCollectionId = album['collectionId']?.toString();
      bool dbChanged = false;

      // Remove trailing .0 from id and collectionId in the table columns
      if (dbId != null && dbId.endsWith('.0')) {
        dbId = dbId.substring(0, dbId.length - 2);
        dbChanged = true;
      }
      if (dbCollectionId != null && dbCollectionId.endsWith('.0')) {
        dbCollectionId = dbCollectionId.substring(0, dbCollectionId.length - 2);
        dbChanged = true;
      }

      // If either changed, update the row in the albums table
      if (dbChanged) {
        await db.update(
          'albums',
          {
            'id': dbId,
            if (dbCollectionId != null) 'collectionId': dbCollectionId,
          },
          where: 'id = ?',
          whereArgs: [album['id'].toString()],
        );
        Logging.severe('Fixed .0 in albums table for album $dbId');
      }

      final id = dbId ?? album['id']?.toString() ?? '';
      final dataField = album['data'];
      if (dataField == null || dataField is! String) {
        skipped++;
        continue;
      }

      try {
        final jsonData = json.decode(dataField);

        bool changed = false;

        // Forcefully update id, collectionId, album_id to string without .0
        for (final key in ['id', 'collectionId', 'album_id']) {
          if (jsonData.containsKey(key)) {
            var value = jsonData[key];
            if (value != null) {
              // Always convert to string and strip trailing .0
              String strValue = value.toString();
              if (strValue.endsWith('.0')) {
                strValue = strValue.substring(0, strValue.length - 2);
              }
              // Only update if different
              if (jsonData[key] != strValue) {
                jsonData[key] = strValue;
                changed = true;
              }
            }
          }
        }

        if (changed) {
          await db.update(
            'albums',
            {'data': json.encode(jsonData)},
            where: 'id = ?',
            whereArgs: [id],
          );
          Logging.severe('Fixed double ID in album $id');
          fixed++;
        } else {
          skipped++;
        }
      } catch (e) {
        Logging.severe('Failed to fix double ID in album $id: $e');
        skipped++;
      }
    }

    Logging.severe(
        'Double ID Fixer: $fixed fixed, $skipped skipped, $total total');
  }

  /// Fix IDs and parse metadata in album data JSON (handles .0 in JSON fields only)
  static Future<void> fixIdsAndMetadataInAlbumData() async {
    final db = await DatabaseHelper.instance.database;
    final albums = await db.query('albums');
    int fixed = 0, skipped = 0, total = albums.length;

    for (final album in albums) {
      final id = album['id']?.toString() ?? '';
      final dataField = album['data'];
      if (dataField == null || dataField is! String) {
        skipped++;
        continue;
      }

      // --- NEW: Use a SQL REPLACE to drop .0 from id/collectionId fields in the JSON string ---
      // This is a fast, DB-level fix for the most common case
      String newDataField = dataField
          .replaceAllMapped(
              RegExp(r'("id"\s*:\s*)(\d+)\.0'), (m) => '${m[1]}"${m[2]}"')
          .replaceAllMapped(RegExp(r'("collectionId"\s*:\s*)(\d+)\.0'),
              (m) => '${m[1]}"${m[2]}"');

      // Only update if changed
      if (newDataField != dataField) {
        await db.update(
          'albums',
          {'data': newDataField},
          where: 'id = ?',
          whereArgs: [id],
        );
        Logging.severe('SQL-REPLACED .0 in album $id');
        fixed++;
        continue;
      }

      // Replace all occurrences of :number.0 (not in quotes) with :"number"
      newDataField = dataField
          .replaceAllMapped(
              RegExp(r'("id"\s*:\s*)(\d+)\.0'), (m) => '${m[1]}"${m[2]}"')
          .replaceAllMapped(RegExp(r'("collectionId"\s*:\s*)(\d+)\.0'),
              (m) => '${m[1]}"${m[2]}"')
          .replaceAllMapped(
              RegExp(r'("album_id"\s*:\s*)(\d+)\.0'), (m) => '${m[1]}"${m[2]}"')
          // Also handle numbers inside quotes: "id":"1770305640.0"
          .replaceAllMapped(RegExp(r'("id"\s*:\s*")(\d+)\.0(")'),
              (m) => '${m[1]}${m[2]}${m[3]}')
          .replaceAllMapped(RegExp(r'("collectionId"\s*:\s*")(\d+)\.0(")'),
              (m) => '${m[1]}${m[2]}${m[3]}')
          .replaceAllMapped(RegExp(r'("album_id"\s*:\s*")(\d+)\.0(")'),
              (m) => '${m[1]}${m[2]}${m[3]}')
          // --- NEW: brute force any number ending with .0 not in scientific notation ---
          .replaceAllMapped(RegExp(r'(:\s*)(\d+)\.0([,\}])'),
              (m) => '${m[1]}"${m[2]}"${m[3]}')
          .replaceAllMapped(
              RegExp(r'(:\s*")(\d+)\.0(")'), (m) => '${m[1]}${m[2]}${m[3]}');

      // If anything changed, update the row
      if (newDataField != dataField) {
        await db.update(
          'albums',
          {'data': newDataField},
          where: 'id = ?',
          whereArgs: [id],
        );
        Logging.severe('BRUTE-FORCE SQL-REPLACED .0 in album $id');
        fixed++;
      } else {
        skipped++;
      }
    }

    Logging.severe(
        'ID/Metadata Fixer: $fixed fixed, $skipped skipped, $total total');
  }

  /// Brute-force: Fix all .0 IDs in the JSON data field for every album, even if already valid JSON.
  static Future<void> bruteForceFixIdsInAlbumData() async {
    final db = await DatabaseHelper.instance.database;
    final albums = await db.query('albums');
    int fixed = 0, skipped = 0, total = albums.length;

    for (final album in albums) {
      final id = album['id']?.toString() ?? '';
      final dataField = album['data'];
      if (dataField == null || dataField is! String) {
        skipped++;
        continue;
      }

      // Only fix id and collectionId keys in the JSON string (album_id is not present in your data)
      String newDataField = dataField
          .replaceAllMapped(
              RegExp(r'("id"\s*:\s*)(\d+)\.0'), (m) => '${m[1]}"${m[2]}"')
          .replaceAllMapped(RegExp(r'("collectionId"\s*:\s*)(\d+)\.0'),
              (m) => '${m[1]}"${m[2]}"')
          .replaceAllMapped(RegExp(r'("id"\s*:\s*")(\d+)\.0(")'),
              (m) => '${m[1]}${m[2]}${m[3]}')
          .replaceAllMapped(RegExp(r'("collectionId"\s*:\s*")(\d+)\.0(")'),
              (m) => '${m[1]}${m[2]}${m[3]}');

      // If anything changed, update the row
      if (newDataField != dataField) {
        await db.update(
          'albums',
          {'data': newDataField},
          where: 'id = ?',
          whereArgs: [id],
        );
        Logging.severe('BRUTE-FORCE SQL-REPLACED .0 in album $id');
        fixed++;
      } else {
        skipped++;
      }
    }

    Logging.severe(
        'BRUTE-FORCE ID Fixer: $fixed fixed, $skipped skipped, $total total');
  }

  /// Simple: Parse JSON, fix .0 for id/collectionId/album_id, re-save as JSON.
  static Future<void> simpleFixIdsInAlbumData() async {
    final db = await DatabaseHelper.instance.database;
    final albums = await db.query('albums');
    int fixed = 0, skipped = 0, total = albums.length;

    for (final album in albums) {
      final id = album['id']?.toString() ?? '';
      final dataField = album['data'];
      if (dataField == null || dataField is! String) {
        skipped++;
        continue;
      }

      try {
        final jsonData = json.decode(dataField);

        bool changed = false;
        if (jsonData is Map) {
          for (final key in ['id', 'collectionId', 'album_id']) {
            if (jsonData.containsKey(key)) {
              var value = jsonData[key];
              if (value is double && value == value.toInt().toDouble()) {
                final strValue = value.toInt().toString();
                if (jsonData[key] != strValue) {
                  jsonData[key] = strValue;
                  changed = true;
                }
              } else if (value is String && value.endsWith('.0')) {
                final strValue = value.substring(0, value.length - 2);
                if (jsonData[key] != strValue) {
                  jsonData[key] = strValue;
                  changed = true;
                }
              }
            }
          }
        }

        if (changed) {
          await db.update(
            'albums',
            {'data': json.encode(jsonData)},
            where: 'id = ?',
            whereArgs: [id],
          );
          Logging.severe('SIMPLE FIXED .0 in album $id');
          fixed++;
        } else {
          skipped++;
        }
      } catch (e) {
        Logging.severe('SIMPLE FIX: Failed to fix album $id: $e');
        skipped++;
      }
    }

    Logging.severe(
        'SIMPLE ID Fixer: $fixed fixed, $skipped skipped, $total total');
  }

  /// Safest: Parse JSON, fix .0 for id/collectionId/album_id, re-save as JSON (no regex at all).
  static Future<void> safestFixIdsInAlbumData() async {
    final db = await DatabaseHelper.instance.database;
    final albums = await db.query('albums');
    int fixed = 0, skipped = 0, total = albums.length;

    for (final album in albums) {
      final id = album['id']?.toString() ?? '';
      final dataField = album['data'];
      if (dataField == null || dataField is! String) {
        skipped++;
        continue;
      }

      try {
        final jsonData = json.decode(dataField);

        bool changed = false;
        if (jsonData is Map) {
          for (final key in ['id', 'collectionId', 'album_id']) {
            if (jsonData.containsKey(key)) {
              var value = jsonData[key];
              // Convert double like 1779334922.0 to string "1779334922"
              if (value is double && value == value.toInt().toDouble()) {
                final strValue = value.toInt().toString();
                if (jsonData[key] != strValue) {
                  jsonData[key] = strValue;
                  changed = true;
                }
              }
              // Convert string like "1779334922.0" to "1779334922"
              else if (value is String && value.endsWith('.0')) {
                final strValue = value.substring(0, value.length - 2);
                if (jsonData[key] != strValue) {
                  jsonData[key] = strValue;
                  changed = true;
                }
              }
            }
          }
        }

        if (changed) {
          await db.update(
            'albums',
            {'data': json.encode(jsonData)},
            where: 'id = ?',
            whereArgs: [id],
          );
          Logging.severe('SAFEST FIXED .0 in album $id');
          fixed++;
        } else {
          skipped++;
        }
      } catch (e) {
        Logging.severe('SAFEST FIX: Failed to fix album $id: $e');
        skipped++;
      }
    }

    Logging.severe(
        'SAFEST ID Fixer: $fixed fixed, $skipped skipped, $total total');
  }

  /// Ultimate fix: Parse JSON, fix .0 for id/collectionId at ALL levels (including inside metadata), re-save as JSON.
  static Future<void> ultimateFixIdsEverywhere() async {
    final db = await DatabaseHelper.instance.database;
    final albums = await db.query('albums');
    int fixed = 0, skipped = 0, total = albums.length;

    for (final album in albums) {
      final id = album['id']?.toString() ?? '';
      final dataField = album['data'];
      if (dataField == null || dataField is! String) {
        skipped++;
        continue;
      }

      try {
        dynamic jsonData = json.decode(dataField);

        // Recursively fix .0 for id/collectionId keys at any level
        bool changed = _fixIdsRecursive(jsonData);

        if (changed) {
          await db.update(
            'albums',
            {'data': json.encode(jsonData)},
            where: 'id = ?',
            whereArgs: [id],
          );
          Logging.severe('ULTIMATE FIXED .0 in album $id');
          fixed++;
        } else {
          skipped++;
        }
      } catch (e) {
        Logging.severe('ULTIMATE FIX: Failed to fix album $id: $e');
        skipped++;
      }
    }

    Logging.severe(
        'ULTIMATE ID Fixer: $fixed fixed, $skipped skipped, $total total');
  }

  /// Recursively fix .0 for id/collectionId keys in any map/list
  static bool _fixIdsRecursive(dynamic data) {
    bool changed = false;
    if (data is Map) {
      for (final key in data.keys) {
        if (key == 'id' || key == 'collectionId') {
          var value = data[key];
          if (value is double && value == value.toInt().toDouble()) {
            final strValue = value.toInt().toString();
            if (data[key] != strValue) {
              data[key] = strValue;
              changed = true;
            }
          } else if (value is String && value.endsWith('.0')) {
            final strValue = value.substring(0, value.length - 2);
            if (data[key] != strValue) {
              data[key] = strValue;
              changed = true;
            }
          }
        }
        // Recurse into nested maps/lists
        if (data[key] is Map || data[key] is List) {
          if (_fixIdsRecursive(data[key])) changed = true;
        }
      }
    } else if (data is List) {
      for (var item in data) {
        if (_fixIdsRecursive(item)) changed = true;
      }
    }
    return changed;
  }
}
