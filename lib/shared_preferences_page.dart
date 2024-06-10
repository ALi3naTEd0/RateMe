import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'app_theme.dart';

class SharedPreferencesPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SharedPreferences'),
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
                backgroundColor: AppTheme.lightTheme.colorScheme.primary, // Usa el color morado claro definido en app_theme.dart
              ),
              child: Text(
                'Exportar',
                style: TextStyle(
                  color: Colors.white, // Texto en blanco
                ),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                importSharedPreferencesFromJson(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.lightTheme.colorScheme.primary, // Usa el color morado claro definido en app_theme.dart
              ),
              child: Text(
                'Importar',
                style: TextStyle(
                  color: Colors.white, // Texto en blanco
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
          content: Text('Los datos de SharedPreferences se han exportado correctamente en: $path'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se seleccionó ningún archivo para guardar.'),
        ),
      );
    }
  }

  Future<void> importSharedPreferencesFromJson(BuildContext context) async {
    // Solicitamos al usuario que seleccione el archivo JSON a importar.
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Seleccione el archivo JSON a importar',
    );

    if (result != null) {
      PlatformFile file = result.files.first;
      String path = file.path!;

      // Leemos el archivo JSON seleccionado.
      String jsonData = await File(path).readAsString();

      // Procesamos el JSON e importamos los datos en SharedPreferences.
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
          content: Text('Los datos de SharedPreferences se han importado correctamente desde: $path'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se seleccionó ningún archivo para importar.'),
        ),
      );
    }
  }
}
