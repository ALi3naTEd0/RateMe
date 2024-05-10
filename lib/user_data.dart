class UserData {
  static List<UserData> savedRatings = []; // Static list to store saved ratings

  String albumName; // Name of the album
  String artistName; // Name of the artist
  String releaseDate; // Release date of the album
  String imageUrl; // URL of the album cover image
  String searchUrl; // URL of the search query
  List<TrackData> tracks; // List of tracks in the album
  
  UserData({
    required this.albumName,
    required this.artistName,
    required this.releaseDate,
    required this.imageUrl,
    required this.searchUrl, // Initialize searchUrl in the constructor
    required this.tracks,
  });

  // Method to add a UserData instance to the saved ratings list
  static void addSavedRating(UserData userData) {
    savedRatings.add(userData);
  }
}

class TrackData {
  int trackNumber; // Track number
  String trackName; // Name of the track
  int trackTimeMillis; // Duration of the track in milliseconds
  double rating; // Rating of the track

  TrackData({
    required this.trackNumber,
    required this.trackName,
    required this.trackTimeMillis,
    required this.rating,
  });
}
