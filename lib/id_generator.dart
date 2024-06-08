class UniqueIdGenerator {
  static int _lastCollectionId = 1000000000;

  static int generateUniqueCollectionId() {
    _lastCollectionId++;
    return _lastCollectionId;
  }
}
