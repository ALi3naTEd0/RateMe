import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

Future<void> exportSharedPreferencesToJson(BuildContext context) async {
  try {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data = prefs.getKeys().fold({}, (previousValue, key) {
      previousValue[key] = prefs.get(key);
      return previousValue;
    });

    String jsonData = jsonEncode(data);
    
    // Obtener el directorio Documents del usuario
    String homeDirectory = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    String documentsPath = path.join(homeDirectory, 'Documents');
    Directory documentsDir = Directory(documentsPath);
    if (!documentsDir.existsSync()) {
      documentsDir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File(path.join(documentsPath, 'rateme_backup_$timestamp.json'));
    
    await file.writeAsString(jsonData, flush: true);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup saved to: ${file.path}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating backup: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}
