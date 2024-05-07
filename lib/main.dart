import 'package:flutter/material.dart';
import 'package:rateme/search_page.dart';
import 'footer.dart';
import 'app_theme.dart';

void main() => runApp(MusicRatingApp());

class MusicRatingApp extends StatefulWidget {
  @override
  _MusicRatingAppState createState() => _MusicRatingAppState();
}

class _MusicRatingAppState extends State<MusicRatingApp> {
  Brightness _themeBrightness = Brightness.light;

  void _toggleTheme() {
    setState(() {
      _themeBrightness =
          _themeBrightness == Brightness.light ? Brightness.dark : Brightness.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rate Me!',
      debugShowCheckedModeBanner: false,
      theme: _themeBrightness == Brightness.light ? AppTheme.lightTheme : AppTheme.darkTheme,
      home: Scaffold(
        appBar: AppBar(
          title: Text('Rate Me!'),
          centerTitle: true,
          actions: [
            Switch(
              value: _themeBrightness == Brightness.dark,
              onChanged: (_) => _toggleTheme(),
              activeColor: AppTheme.darkTheme.colorScheme.secondary, // Cambiar el color del círculo del switch cuando está activado a amarillo (tema oscuro)
              inactiveThumbColor: AppTheme.lightTheme.colorScheme.primary, // Cambiar el color del círculo del switch cuando está inactivo a morado (tema claro)
              inactiveTrackColor: AppTheme.lightTheme.colorScheme.primary.withOpacity(0.5), // Cambiar el color de la pista del switch cuando está inactivo a un tono más claro de morado (tema claro)
            ),
          ],
        ),
        body: SearchPage(),
        bottomNavigationBar: Footer(),
      ),
    );
  }
}
