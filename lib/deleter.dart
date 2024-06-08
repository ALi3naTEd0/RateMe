import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeleterPage extends StatefulWidget {
  @override
  _DeleterPageState createState() => _DeleterPageState();
}

class _DeleterPageState extends State<DeleterPage> {
  late SharedPreferences _prefs;
  List<String> _sharedPrefsData = [];

  @override
  void initState() {
    super.initState();
    _initSharedPreferences();
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadSharedPreferencesData();
  }

  void _loadSharedPreferencesData() {
    setState(() {
      _sharedPrefsData = _prefs.getKeys().toList();
    });
  }

  Future<void> _deleteSharedPreferences(String key) async {
    await _prefs.remove(key);
    setState(() {
      _sharedPrefsData.remove(key);
    });
    print('Datos eliminados: $key');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Borrar Datos Guardados'),
      ),
      body: ListView.builder(
        itemCount: _sharedPrefsData.length,
        itemBuilder: (context, index) {
          final key = _sharedPrefsData[index];
          final dynamicValue = _prefs.get(key);
          final value = dynamicValue is int ? dynamicValue : null;
          return ListTile(
            title: Text(key),
            subtitle: Text('Valor: ${value.toString()}'),
            trailing: IconButton(
              icon: Icon(Icons.delete),
              onPressed: () {
                _deleteSharedPreferences(key);
              },
            ),
          );
        },
      ),
    );
  }
}
