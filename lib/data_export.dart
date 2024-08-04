import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

Future<void> exportSharedPreferencesToJson(BuildContext context) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  Map<String, dynamic> data = prefs.getKeys().fold({}, (previousValue, key) {
    previousValue[key] = prefs.get(key);
    return previousValue;
  });

  String jsonData = jsonEncode(data);

  // We ask the user to select the directory where the file will be saved.
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
    dialogTitle: 'Seleccione dónde guardar el archivo JSON',
  );

  if (result != null) {
    PlatformFile file = result.files.first;
    String path = file.path!;

    // We save the JSON file in the selected directory.
    File(path).writeAsStringSync(jsonData);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Los datos de SharedPreferences se han exportado correctamente en: $path'),
      ),
    );
  } else {
    // The user deselected the file.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('No se seleccionó ningún directorio para guardar el archivo.'),
      ),
    );
  }
}
