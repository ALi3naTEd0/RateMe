import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'app_theme.dart';

class SharedPreferencesPage extends StatelessWidget {
  const SharedPreferencesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SharedPreferences'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () {
                exportSharedPreferencesToJson(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.lightTheme.colorScheme
                    .primary, // Use the light purple color defined in app_theme.dart
              ),
              child: const Text(
                'Exportar',
                style: TextStyle(
                  color: Colors.white, // White text
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                importSharedPreferencesFromJson(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.lightTheme.colorScheme
                    .primary, // Use the light purple color defined in app_theme.dart
              ),
              child: const Text(
                'Importar',
                style: TextStyle(
                  color: Colors.white, // White text
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> exportSharedPreferencesToJson(BuildContext context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data = prefs.getKeys().fold({}, (previousValue, key) {
      previousValue[key] = prefs.get(key);
      return previousValue;
    });

    String jsonData = jsonEncode(data);

    String? path = await FilePicker.platform.saveFile(
      dialogTitle: 'Seleccione dónde guardar el archivo JSON',
      fileName: 'shared_preferences.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (path != null) {
      File file = File(path);
      await file.writeAsString(jsonData);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Los datos de SharedPreferences se han exportado correctamente en: $path'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se seleccionó ningún archivo para guardar.'),
        ),
      );
    }
  }

  Future<void> importSharedPreferencesFromJson(BuildContext context) async {
    // We ask the user to select the JSON file to import.
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Seleccione el archivo JSON a importar',
    );

    if (result != null) {
      PlatformFile file = result.files.first;
      String path = file.path!;

      // We read the selected JSON file.
      String jsonData = await File(path).readAsString();

      // We process the JSON and import the data into SharedPreferences.
      SharedPreferences prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> data = jsonDecode(jsonData);

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Los datos de SharedPreferences se han importado correctamente desde: $path'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se seleccionó ningún archivo para importar.'),
        ),
      );
    }
  }
}
