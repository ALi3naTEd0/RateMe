import 'package:flutter/material.dart';
import 'package:rateme/search_page.dart';

void main() => runApp(MusicRatingApp());

class MusicRatingApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rate Me!',
      debugShowCheckedModeBanner: false,
      home: SearchPage(),
    );
  }
}
