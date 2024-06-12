import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'id_generator.dart';
import 'search_page.dart';
import 'footer.dart';
import 'app_theme.dart';
import 'album_details_page.dart';
import 'bandcamp_details_page.dart';
import 'saved_preferences_page.dart';
import 'saved_ratings_page.dart';
import 'shared_preferences_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MusicRatingApp());
}

class MusicRatingApp extends StatefulWidget {
  @override
  _MusicRatingAppState createState() => _MusicRatingAppState();
}

class _MusicRatingAppState extends State<MusicRatingApp> {
  Brightness? _themeBrightness;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final brightnessIndex = prefs.getInt('themeBrightness');
    setState(() {
      _themeBrightness = brightnessIndex != null ? Brightness.values[brightnessIndex] : Brightness.light;
    });
  }

  void _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final newBrightness = _themeBrightness == Brightness.light ? Brightness.dark : Brightness.light;
    await prefs.setInt('themeBrightness', newBrightness.index);
    setState(() {
      _themeBrightness = newBrightness;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_themeBrightness == null) {
      return CircularProgressIndicator();
    }
    return MaterialApp(
      title: 'Rate Me!',
      debugShowCheckedModeBanner: false,
      theme: _themeBrightness == Brightness.light ? AppTheme.lightTheme : AppTheme.darkTheme,
      home: MusicRatingHomePage(
        toggleTheme: _toggleTheme,
        themeBrightness: _themeBrightness!,
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
        leading: Tooltip(
          message: 'Saved Ratings',
          child: IconButton(
            icon: Icon(Icons.star, size: 32, color: _getStarIconColor(themeBrightness)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SavedRatingsPage()),
              );
            },
          ),
        ),
        actions: [
          Tooltip(
            message: 'Theme',
            child: Transform.scale(
              scale: 0.8,
              child: Switch(
                value: themeBrightness == Brightness.dark,
                onChanged: (_) => toggleTheme(),
                activeColor: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          Tooltip(
            message: 'Shared Preferences',
            child: IconButton(
              icon: Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SharedPreferencesPage()),
                );
              },
            ),
          ),
        ],
      ),
      body: SearchPage(),
      bottomNavigationBar: Footer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => SavedPreferencesPage()),
          );
        },
        child: Icon(Icons.delete),
      ),
    );
  }

  Color _getStarIconColor(Brightness themeBrightness) {
    return themeBrightness == Brightness.light ? AppTheme.lightTheme.colorScheme.primary : AppTheme.darkTheme.colorScheme.primary;
  }
}
