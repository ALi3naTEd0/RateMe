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
              activeColor: AppTheme.darkTheme.colorScheme.secondary, // Change the color of the switch circle when active to yellow (dark theme)
              inactiveThumbColor: AppTheme.lightTheme.colorScheme.primary, // Change the color of the switch circle when inactive to purple (light theme)
              inactiveTrackColor: AppTheme.lightTheme.colorScheme.primary.withOpacity(0.5), // Change the color of the switch track when inactive to a lighter shade of purple (light theme)
            ),
          ],
        ),
        body: SearchPage(),
        bottomNavigationBar: Footer(),
      ),
    );
  }
}
