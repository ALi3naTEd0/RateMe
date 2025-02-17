import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

Future<void> importSharedPreferencesFromJson(BuildContext context) async {
  try {
    // Obtener el directorio Documents del usuario
    String homeDirectory = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    String documentsPath = path.join(homeDirectory, 'Documents');
    Directory documentsDir = Directory(documentsPath);
    
    if (!documentsDir.existsSync()) {
      throw Exception('Documents directory not found');
    }

    final List<FileSystemEntity> files = documentsDir.listSync();
    
    // Filtrar solo archivos de backup de RateMe
    final backupFiles = files.whereType<File>()
        .where((file) => file.path.contains('rateme_backup_') && file.path.endsWith('.json'))
        .toList();

    if (backupFiles.isEmpty) {
      throw Exception('No backup files found in Documents folder');
    }

    // Obtener el backup más reciente
    final latestBackup = backupFiles.reduce((a, b) => 
      a.lastModifiedSync().isAfter(b.lastModifiedSync()) ? a : b);
    
    String jsonData = await latestBackup.readAsString();
    Map<String, dynamic> data = jsonDecode(jsonData);
    SharedPreferences prefs = await SharedPreferences.getInstance();

    data.forEach((key, value) {
      if (value is int) {
        prefs.setInt(key, value);
      } else if (value is double) {
        prefs.setDouble(key, value);
      } else if (value is bool) {
        prefs.setBool(key, value);
      } else if (value is String) {
        prefs.setString(key, value);
      } else if (value is List<String>) {
        prefs.setStringList(key, value);
      }
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Data imported from: ${latestBackup.path}')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error importing backup: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}
