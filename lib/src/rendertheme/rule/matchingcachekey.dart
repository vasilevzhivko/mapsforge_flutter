import '../../model/tag.dart';

class MatchingCacheKey {
  final List<Tag> _tags;
  final int _zoomLevel;
  final int _indoorLevel;

  const MatchingCacheKey(this._tags, this._zoomLevel, this._indoorLevel);

  @override
  String toString() {
    return 'MatchingCacheKey{_tags: $_tags, _zoomLevel: $_zoomLevel, _indoorLevel: $_indoorLevel}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchingCacheKey &&
          runtimeType == other.runtimeType &&
          _tags.fold(
                  15,
                  (dynamic previousValue, element) =>
                      previousValue ^ element.hashCode) ==
              other._tags.fold(
                  15,
                  (dynamic previousValue, element) =>
                      previousValue ^ element.hashCode) &&
          _zoomLevel == other._zoomLevel &&
          _indoorLevel == other._indoorLevel;

  @override
  int get hashCode {
    int tagHash = _tags.fold<int>(
        15, ((previousValue, element) => previousValue ^ element.hashCode));
    return tagHash ^ _zoomLevel.hashCode ^ _indoorLevel.hashCode << 5;
  }
}
