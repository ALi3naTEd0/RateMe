import 'package:flutter/material.dart';
import 'package:rateme/app_theme.dart';
import 'package:rateme/user_data.dart';

class SavedRatingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final savedRatings = UserData.savedRatings;

    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Ratings'),
      ),
      body: savedRatings.isEmpty
          ? Center(
              child: Text('No ratings saved.'),
            )
          : ListView.builder(
              itemCount: savedRatings.length,
              itemBuilder: (context, index) {
                final savedRating = savedRatings[index];
                // Suma los ratings de todas las pistas
                final totalRating = savedRating.tracks
                    .map((track) => track.rating)
                    .reduce((value, element) => value + element);
                // Calcula el rating promedio
                final averageRating = totalRating / savedRating.tracks.length;
                return ListTile(
                  title: Text(savedRating.albumName),
                  subtitle: Text(savedRating.artistName),
                  trailing: Text(averageRating.toString()),
                  onTap: () {
                    // TODO: Implement navigation to the detailed rating page
                  },
                );
              },
            ),
    );
  }
}
