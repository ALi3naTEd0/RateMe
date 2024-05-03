import 'package:flutter/material.dart';
import 'package:rateme/search_page.dart';
import 'footer.dart';

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
      theme: ThemeData.light().copyWith(
        colorScheme: ThemeData.light().colorScheme.copyWith(
          primary: Color(0xFFFFEB3B), // Amarillo pastel como color primario
          secondary: Color(0xFFFFEB3B), // Amarillo pastel como color secundario
        ),
        brightness: _themeBrightness,
        toggleableActiveColor: Colors.deepPurple, // Cambia el color de activación del botón switch a morado oscuro
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ThemeData.dark().colorScheme.copyWith(
          primary: Color(0xFFFFC107), // Amarillo oscuro como color primario del tema oscuro
          secondary: Color(0xFFFFC107), // Amarillo oscuro como color secundario del tema oscuro
        ),
        brightness: _themeBrightness,
        scaffoldBackgroundColor: Colors.grey[900], // Fondo gris oscuro para el tema oscuro
      ),
      themeMode: _themeBrightness == Brightness.light ? ThemeMode.light : ThemeMode.dark,
      home: Scaffold(
        appBar: AppBar(
          title: Text('Rate Me!'),
          centerTitle: true,
          actions: [
            Switch(
              value: _themeBrightness == Brightness.dark,
              onChanged: (_) => _toggleTheme(),
            ),
          ],
        ),
        body: SearchPage(),
        bottomNavigationBar: Footer(),
      ),
    );
  }
}
