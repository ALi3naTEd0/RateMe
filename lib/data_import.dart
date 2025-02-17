import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

Future<bool> importSharedPreferencesFromJson(BuildContext context) async {
  try {
    String homeDirectory = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    String documentsPath = path.join(homeDirectory, 'Documents');
    Directory documentsDir = Directory(documentsPath);
    
    if (!documentsDir.existsSync()) {
      throw Exception('Documents directory not found');
    }

    final List<FileSystemEntity> files = documentsDir.listSync();
    
    final backupFiles = files.whereType<File>()
        .where((file) => file.path.contains('rateme_backup_') && file.path.endsWith('.json'))
        .toList();

    if (backupFiles.isEmpty) {
      throw Exception('No backup files found in Documents folder');
    }

    final latestBackup = backupFiles.reduce((a, b) => 
      a.lastModifiedSync().isAfter(b.lastModifiedSync()) ? a : b);
    
    String jsonData = await latestBackup.readAsString();
    Map<String, dynamic> data = jsonDecode(jsonData);
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // 1. Limpiar datos existentes
    await prefs.clear();

    // 2. Primero guardar el orden de los álbumes
    if (data.containsKey('savedAlbumsOrder')) {
      await prefs.setStringList('saved_album_order', List<String>.from(data['savedAlbumsOrder']));
    }

    // 3. Luego guardar los álbumes
    if (data.containsKey('saved_albums')) {
      await prefs.setStringList('saved_albums', List<String>.from(data['saved_albums']));
    }

    // 4. Finalmente guardar los ratings y otros datos
    for (var entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      
      // Saltar las claves que ya procesamos
      if (key == 'savedAlbumsOrder' || key == 'saved_albums') continue;
      
      if (value is List) {
        if (value.every((item) => item is String)) {
          await prefs.setStringList(key, List<String>.from(value));
        }
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      }
    }

    // Verificar que los datos se guardaron
    print('DEBUG: Restored data:');
    print('Albums: ${prefs.getStringList('saved_albums')?.length ?? 0} albums');
    print('Order: ${prefs.getStringList('saved_album_order')?.length ?? 0} entries');
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Data restored from: ${latestBackup.path}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
    return true;

  } catch (e, stackTrace) {
    print('ERROR during import: $e');
    print('Stack trace: $stackTrace');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error importing backup: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
    return false;
  }
}
