import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SharedPreferencesPage extends StatefulWidget {
  const SharedPreferencesPage({super.key});

  @override
  _SharedPreferencesPageState createState() => _SharedPreferencesPageState();
}

class _SharedPreferencesPageState extends State<SharedPreferencesPage> {
  String? appVersion;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        appVersion = packageInfo.version;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SharedPreferences'),
      ),
      body: ListView(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ElevatedButton(
                  onPressed: () => exportSharedPreferencesToJson(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  child: const Text('Exportar', style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => importSharedPreferencesFromJson(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  child: const Text('Importar', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('About'),
            subtitle: Text('Version $appVersion'),
            leading: const Icon(Icons.info_outline),
          ),
        ],
      ),
    );
  }

  Future<void> exportSharedPreferencesToJson(BuildContext context) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data = prefs.getKeys().fold({}, (previousValue, key) {
      previousValue[key] = prefs.get(key);
      return previousValue;
    });

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final defaultFileName = 'rateme_preferences_$timestamp.json';

    String? filePath;
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      filePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save preferences as',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        lockParentWindow: true,
      );
    } else {
      final defaultDir = await getExternalStorageDirectory();
      filePath = path.join(defaultDir?.path ?? '/storage/emulated/0/Download', defaultFileName);
    }

    if (filePath != null) {
      File file = File(filePath);
      await file.writeAsString(jsonEncode(data));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Preferences exported successfully!'),
                      Text(
                        filePath,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
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
      String? path = file.path;

      if (path != null) {
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

        if (context.mounted) {
          // Check if the widget is still mounted
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Los datos de SharedPreferences se han importado correctamente desde: $path'),
            ),
          );
        }
      }
    } else {
      if (context.mounted) {
        // Check if the widget is still mounted
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se seleccionó ningún archivo para importar.'),
          ),
        );
      }
    }
  }
}
