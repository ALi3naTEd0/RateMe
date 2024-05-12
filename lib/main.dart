import 'package:flutter/material.dart';
import 'search_page.dart';
import 'footer.dart';
import 'app_theme.dart';
import 'album_details_page.dart';
import 'saved_ratings_page.dart';

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
      home: MusicRatingHomePage(
        toggleTheme: _toggleTheme,
        themeBrightness: _themeBrightness,
      ),
    );
  }
}

class MusicRatingHomePage extends StatelessWidget {
  final Function toggleTheme;
  final Brightness themeBrightness;

  MusicRatingHomePage({
    required this.toggleTheme,
    required this.themeBrightness,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Rate Me!'),
        centerTitle: true,
        actions: [
          Tooltip(
            message: 'Saved Ratings',
            child: IconButton(
              icon: Icon(Icons.star, size: 28),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SavedRatingsPage()),
                );
              },
            ),
          ),
          Tooltip(
            message: 'Theme',
            child: Switch(
              value: themeBrightness == Brightness.dark,
              onChanged: (_) => toggleTheme(),
              activeColor: Theme.of(context).colorScheme.secondary, // Use the secondary color from the theme
            ),
          ),
        ],
      ),
      body: SearchPage(),
      bottomNavigationBar: Footer(),
    );
  }
}
