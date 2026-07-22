import 'dart:math';

/// Preset memory budgets for the caches, selectable by the app at startup
/// depending on the device class (see [MapsforgeSettingsMgr.setMemoryProfile]).
enum MemoryProfile {
  /// Old/low-RAM phones: 16MB mapfile block cache, 32MB rendered-tile budget.
  low,

  /// Default: 32MB block cache, 64MB rendered-tile budget.
  normal,

  /// Plenty of RAM: 64MB block cache, 128MB rendered-tile budget.
  high,
}

/// Singleton settings manager for Mapsforge rendering configuration.
///
/// This class manages global settings that affect map rendering behavior,
/// including tile sizes, scaling factors, stroke properties, and text rendering.
/// Uses the singleton pattern to ensure consistent settings across the application.
///
/// Key configuration areas:
/// - Tile rendering (size, scale factors)
/// - Stroke rendering (thickness, zoom-dependent scaling)
/// - Font and text rendering (scale factors, maximum widths)
/// - Device-specific adaptations (DPI scaling)
class MapsforgeSettingsMgr {
  static MapsforgeSettingsMgr? _instance;

  /// The size of a tile in pixels. Default is 256 pixels.
  ///
  /// Changing this value is discouraged as most online tile services
  /// provide tiles in 256x256 pixel format.
  double tileSize = 256;

  /// Minimum zoom level at which stroke thickening begins.
  /// Below this level, strokes maintain their base thickness.
  int strokeMinZoomlevel = 13;

  /// Minimum zoom level at which dashed-line thickening begins.
  /// Below this level, dashed-lines maintain their base thickness.
  int dashMinZoomlevel = 20;

  /// Minimum zoom level at which text stroke thickening begins.
  /// Text strokes start scaling at higher zoom levels than regular strokes.
  int strokeMinZoomlevelText = 18;

  /// Multiplicative factor for stroke thickness increase per zoom level.
  /// Applied when zoom level exceeds strokeMinZoomlevel.
  double _strokeIncreaseFactor = 1.4;

  /// Maximum allowed stroke scale factor to prevent excessive thickness.
  /// Caps the stroke scaling regardless of zoom level.
  double _strokeMaxScaleFactor = 5;

  /// Scale factor for fonts and symbols rendering.
  ///
  /// Final font/symbol size = base size × fontScaleFactor.
  /// Works in conjunction with render theme definitions.
  double _fontScaleFactor = 1;

  /// Device pixel density scale factor for crisp rendering.
  ///
  /// - Value 1.0: tile spans exactly tileSize pixels on screen
  /// - Value 2.0: tile appears half-size (higher DPI displays)
  /// Used to adapt rendering for different screen densities.
  double _deviceScaleFactor = 1;

  /// User-requested scale factor for tile rendering.
  ///
  /// Higher values make tiles appear larger, showing more detail at a given zoom level.
  /// Note: This does not affect text rendering, only map elements.
  double _userScaleFactor = 1;

  /// Maximum text width factor relative to tile size.
  ///
  /// Prevents text from spanning too many neighboring tiles, which could
  /// cause truncation issues in tile-based rendering.
  final double maxTextWidthFactor = 0.95;

  late double maxTextWidth;

  /// Default maximum zoom level supported by the rendering system.
  /// Can be overridden by specific map implementations.
  static const int defaultMaxZoomlevel = 25;

  /// Byte budget for a mapfile's block cache (raw data blocks read from the
  /// .map file). Set via [setMemoryProfile] or directly, BEFORE opening a
  /// mapfile — the value is read when the cache is created.
  int blockCacheBytes = 32 << 20;

  /// Global byte budget for rendered tile bitmaps, shared by all tile layers
  /// (each layer takes its `tileCacheShare` of this). Set via
  /// [setMemoryProfile] or directly, BEFORE creating the map widget.
  int tileBitmapBudgetBytes = 64 << 20;

  /// Applies the cache budgets of [profile]. Call at app startup, before any
  /// mapfile or map widget is created.
  void setMemoryProfile(MemoryProfile profile) {
    switch (profile) {
      case MemoryProfile.low:
        blockCacheBytes = 16 << 20;
        tileBitmapBudgetBytes = 32 << 20;
      case MemoryProfile.normal:
        blockCacheBytes = 32 << 20;
        tileBitmapBudgetBytes = 64 << 20;
      case MemoryProfile.high:
        blockCacheBytes = 64 << 20;
        tileBitmapBudgetBytes = 128 << 20;
    }
  }

  factory MapsforgeSettingsMgr() {
    if (_instance != null) return _instance!;
    _instance = MapsforgeSettingsMgr._();
    return _instance!;
  }

  MapsforgeSettingsMgr._() {
    _setMaxTextWidth();
  }

  void _setMaxTextWidth() {
    maxTextWidth = tileSize * maxTextWidthFactor;
  }

  void setDeviceScaleFactor(double deviceScaleFactor) {
    assert(deviceScaleFactor > 0);
    _deviceScaleFactor = deviceScaleFactor;
  }

  void setUserScaleFactor(double userScaleFactor) {
    _userScaleFactor = userScaleFactor;
  }

  void setFontScaleFactor(double fontScaleFactor) {
    _fontScaleFactor = fontScaleFactor;
  }

  /// Returns the scale factor for font-related items.
  double getFontScaleFactor() {
    return _fontScaleFactor;
  }

  double getUserScaleFactor() => _userScaleFactor;

  double getDeviceScaleFactor() => _deviceScaleFactor;

  /// Returns the maximum width of text beyond which the text is broken into lines. This should be
  /// used in the graphicsFactory but is currently not used at all
  ///
  /// @return the maximum text width
  double getMaxTextWidth() {
    return maxTextWidth;
  }

  set strokeMaxScaleFactor(double strokeMaxScaleFactor) => _strokeMaxScaleFactor = strokeMaxScaleFactor;

  set strokeIncreaseFactor(double strokeIncreaseFactor) {
    assert(strokeIncreaseFactor > 1);
    _strokeIncreaseFactor = strokeIncreaseFactor;
  }

  /// Calculates zoom-dependent scale factor for rendering elements.
  ///
  /// Elements scale progressively larger as zoom level increases beyond minZoomlevel.
  /// Uses exponential scaling based on strokeIncreaseFactor.
  ///
  /// [zoomlevel] Current zoom level
  /// [minZoomlevel] Zoom level at which scaling begins
  /// Returns the calculated scale factor
  double calculateScaleFactor(int zoomlevel, int minZoomlevel) {
    int zoomLevelDiff = zoomlevel - minZoomlevel + 1;
    double scaleFactor = pow(_strokeIncreaseFactor, zoomLevelDiff) as double;
    return scaleFactor;
    //return min(scaleFactor, _strokeMaxScaleFactor);
  }
}
