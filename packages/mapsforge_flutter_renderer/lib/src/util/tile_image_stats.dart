/// Process-wide diagnostics for tile bitmap memory.
///
/// Every rendered tile is kept as a rasterized `ui.Image` in a [TileJobQueue]'s
/// LRU cache — these do NOT show up in Flutter's `PaintingBinding.imageCache`,
/// so they're invisible to the usual memory log. This counter makes the total
/// visible so we can tell whether tile bitmaps are the memory hog.
class TileImageStats {
  static int _tiles = 0;
  static int _pixels = 0;

  /// Number of tile bitmaps currently held across ALL tile caches (approximate:
  /// carry-forward tiles that outlive their cache entry can make the raw counter
  /// undershoot, so it's clamped at 0).
  static int get liveTiles => _tiles < 0 ? 0 : _tiles;

  static void add(int width, int height) {
    _tiles++;
    _pixels += width * height;
  }

  static void remove(int width, int height) {
    _tiles--;
    _pixels -= width * height;
  }

  /// Approximate megabytes of tile bitmaps (RGBA).
  static double get megabytes => (_pixels < 0 ? 0 : _pixels) * 4 / 1024 / 1024;
}
