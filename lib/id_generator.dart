class UniqueIdGenerator {
  static int _lastCollectionId = 1000000000;
  static int _lastTrackId = 2000000000;

  static int generateUniqueCollectionId() {
    _lastCollectionId++;
    return _lastCollectionId;
  }

  static int generateUniqueTrackId() {
    _lastTrackId++;
    return _lastTrackId;
  }
}
