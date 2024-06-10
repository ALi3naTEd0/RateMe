import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'export_service.dart';
// import 'import_service.dart';

class PreferencesPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Preferences'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () async {
                await ExportService.exportData('JSON');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Data exported successfully')),
                );
              },
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.all<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              child: Text(
                'Export Data (JSON)',
                style: TextStyle(color: Colors.white),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await ExportService.exportData('CSV');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Data exported successfully')),
                );
              },
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.all<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              child: Text(
                'Export Data (CSV)',
                style: TextStyle(color: Colors.white),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await ImportService.importData('JSON');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Data imported successfully')),
                );
              },
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.all<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              child: Text(
                'Import Data (JSON)',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
