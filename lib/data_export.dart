import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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

  // Solicitamos al usuario que seleccione el directorio donde se guardará el archivo.
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
    dialogTitle: 'Seleccione dónde guardar el archivo JSON',
  );

  if (result != null) {
    PlatformFile file = result.files.first;
    String path = file.path!;

    // Guardamos el archivo JSON en el directorio seleccionado.
    File(filePath).writeAsStringSync(jsonData);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Los datos de SharedPreferences se han exportado correctamente en: $path'),
      ),
    );
  } else {
    // El usuario canceló la selección del archivo.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No se seleccionó ningún directorio para guardar el archivo.'),
      ),
    );
  }
}
