
class PlatformDataAnalyzer {
  static Map<String, dynamic> analyzeItunesData(Map<String, dynamic> data) {
    final analysis = <String, dynamic>{};
    
    analysis['id'] = data['collectionId'];
    analysis['name'] = data['collectionName'];
    analysis['artist'] = data['artistName'];
    analysis['artworkUrl'] = data['artworkUrl100'];
    analysis['releaseDate'] = data['releaseDate'];
    analysis['platform'] = 'itunes';
    
    // Analyze track structure
    if (data['tracks'] != null) {
      analysis['hasTrackData'] = true;
      analysis['trackFields'] = [
        'trackId',
        'trackName',
        'trackNumber',
        'trackTimeMillis',
      ];
    }
    
    return analysis;
  }

  static Map<String, dynamic> analyzeBandcampData(Map<String, dynamic> data) {
    final analysis = <String, dynamic>{};
    
    analysis['id'] = data['id'] ?? data['url']?.hashCode ?? DateTime.now().millisecondsSinceEpoch;
    analysis['name'] = data['title'] ?? 'Unknown Album';
    analysis['artist'] = data['artist'] ?? 'Unknown Artist';
    analysis['artworkUrl'] = data['artwork'] ?? data['artworkUrl'] ?? '';
    analysis['releaseDate'] = data['releaseDate'] ?? data['published_date'] ?? DateTime.now().toIso8601String();
    analysis['platform'] = 'bandcamp';
    
    // Analyze track structure
    if (data['tracks'] != null) {
      analysis['hasTrackData'] = true;
      analysis['trackFields'] = [
        'id',
        'title',
        'position',
        'duration',
      ];
    }
    
    return analysis;
  }

  static String detectPlatform(Map<String, dynamic> data) {
    // First check for iTunes identifiers
    if (data.containsKey('collectionId')) {
      return 'itunes';
    }
    
    // Then check URL for Bandcamp
    final url = data['url'];
    if (url != null && url.toString().contains('bandcamp.com')) {
      return 'bandcamp';
    }
    
    // Finally check other fields that might indicate the platform
    if (data.containsKey('trackTimeMillis')) {
      return 'itunes';
    }
    
    if (data.containsKey('bandcampId') || data['platform'] == 'bandcamp') {
      return 'bandcamp';
    }
    
    return 'unknown';
  }
}
