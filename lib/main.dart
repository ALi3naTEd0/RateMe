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
          primary: Color(0xFF864AF9), // Primario: 864AF9 (Morado)
          secondary: Color(0xFFF8E559), // Secundario: F8E559 (Amarillo)
        ),
        brightness: _themeBrightness,
        scaffoldBackgroundColor: Colors.white, // Cambiar el color de fondo del Scaffold en tema claro
        sliderTheme: SliderThemeData(
          thumbColor: Color(0xFF864AF9), // Slider tema claro: 864AF9 (Morado)
          activeTrackColor: Color(0xFF864AF9), // Slider tema claro: 864AF9 (Morado)
          valueIndicatorTextStyle: TextStyle(
            color: Colors.white, // Texto del valor seleccionado del slider en tema claro: blanco
            fontWeight: FontWeight.bold, // Texto del valor seleccionado del slider en tema claro: bold
          ),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ThemeData.dark().colorScheme.copyWith(
          primary: Color(0xFFF8E559), // Primario: F8E559 (Amarillo)
          secondary: Color(0xFF864AF9), // Secundario: 864AF9 (Morado)
        ),
        brightness: _themeBrightness,
        sliderTheme: SliderThemeData(
          thumbColor: Color(0xFFF8E559), // Slider tema oscuro: F8E559 (Amarillo)
          activeTrackColor: Color(0xFFF8E559), // Slider tema oscuro: F8E559 (Amarillo)
          valueIndicatorTextStyle: TextStyle(
            color: Colors.black, // Texto del valor seleccionado del slider en tema oscuro: negro
            fontWeight: FontWeight.bold, // Texto del valor seleccionado del slider en tema oscuro: bold
          ),
        ),
        scaffoldBackgroundColor: Color(0xFF332941), // Fondo en tema oscuro: 332941 (Gris oscuro)
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
              activeColor: Color(0xFFF8E559), // Cambiar el color del círculo del switch cuando está activado a amarillo
              inactiveTrackColor: Theme.of(context).colorScheme.secondary, // Color de la pista del switch cuando está desactivado
            ),
          ],
        ),
        body: SearchPage(),
        bottomNavigationBar: Footer(),
      ),
    );
  }
}
