import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

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
    // El usuario canceló la selección del archivo.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No se seleccionó ningún archivo para importar.'),
      ),
    );
  }
}
