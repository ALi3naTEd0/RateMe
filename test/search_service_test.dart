import 'package:flutter_test/flutter_test.dart';
import 'package:rateme/core/services/search_service.dart';

void main() {
  group('RateYourMusic URL import', () {
    test('creates a manual album result without changing numeric titles',
        () async {
      final result = await SearchService.searchAlbum(
        'https://rateyourmusic.com/release/album/two-shell/infinite-now-2/',
        '',
      );

      expect(result, isNotNull);
      final album = (result!['results'] as List).single;
      expect(album['collectionName'], 'Infinite Now 2');
      expect(album['artistName'], 'Two Shell');
      expect(album['platform'], 'rateyourmusic');
      expect(album['manualEntry'], isTrue);
      expect(album['tracks'], isEmpty);
    });
  });
}