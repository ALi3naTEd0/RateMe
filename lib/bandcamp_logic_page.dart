import 'package:flutter/material.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'bandcamp_parser.dart';
import 'user_data.dart';
import 'logging.dart';

class BandcampLogicPage extends ChangeNotifier {
  List<Map<String, dynamic>> tracks = [];
  Map<int, double> ratings = {};
  double averageRating = 0.0;
  int albumDurationMillis = 0;
  bool isLoading = true;

  Future<void> fetchTracks(String url, int collectionId) async {
    try {
      final response = await http.get(Uri.parse(url));
      final document = parse(response.body);
      final extractedTracks = BandcampParser.extractTracks(document);
      tracks = extractedTracks;
      for (var track in extractedTracks) {
        ratings[track['trackId']] = 0.0;
      }
      calculateAlbumDuration();
      _loadSavedRatings(collectionId);
      isLoading = false;
      notifyListeners();
    } catch (error, stackTrace) {
      Logging.severe('Error fetching tracks', error, stackTrace);
    }
  }

  void calculateAverageRating() {
    var ratedTracks = ratings.values.where((rating) => rating > 0).toList();
    if (ratedTracks.isNotEmpty) {
      double total = ratedTracks.reduce((a, b) => a + b);
      averageRating = total / ratedTracks.length;
      averageRating = double.parse(averageRating.toStringAsFixed(2));
    } else {
      averageRating = 0.0;
    }
    notifyListeners();
  }

  void calculateAlbumDuration() {
    int totalDuration = 0;
    for (var track in tracks) {
      totalDuration += track['duration'] as int;
    }
    albumDurationMillis = totalDuration;
    notifyListeners();
  }

  Future<void> _loadSavedRatings(int albumId) async {
    List<Map<String, dynamic>> savedRatings =
        await UserData.getSavedAlbumRatings(albumId);
    for (var rating in savedRatings) {
      ratings[rating['trackId']] = rating['rating'];
    }
    calculateAverageRating();
  }

  void updateRating(int trackId, double newRating, int albumId) async {
    ratings[trackId] = newRating;
    calculateAverageRating();
    await UserData.saveRating(albumId, trackId, newRating);
    Logging.info('Updated rating for trackId $trackId', null, null);
  }
}
