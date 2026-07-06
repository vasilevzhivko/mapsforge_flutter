/// The protocol of a user-defined online map source. Supported: [xyz], [wmts],
/// [wms] (all Web-Mercator / EPSG:3857).
enum RendererKind { xyz, wmts, wms }

/// Engine-agnostic description of a user-defined online map source. The app maps
/// its own model onto this before building a renderer via `CustomRendererFactory`.
class CustomSourceSpec {
  final RendererKind kind;

  /// XYZ URL template, or the WMTS/WMS service endpoint base URL.
  final String urlTemplate;

  final int zoomMin;
  final int zoomMax;

  /// TMS Y-axis flip (XYZ only): false = XYZ/OSM (top-left origin).
  final bool flipY;

  /// Stable cache key (unique per source) so each source keeps its own cache.
  final String cacheKey;

  /// True for OVERLAY sources: a missing/failed tile must be transparent.
  final bool transparentOnMiss;

  // ── WMTS / WMS ──
  /// WMS `LAYERS` (comma-separated) or WMTS `LAYER`.
  final String? layers;

  /// WMTS `STYLE` / WMS `STYLES` (usually empty for default).
  final String? style;

  /// Image `FORMAT` MIME type (default image/png).
  final String? format;

  /// WMS version: '1.3.0' (default) or '1.1.1'.
  final String? version;

  /// WMTS `TILEMATRIXSET` (e.g. GoogleMapsCompatible / EPSG:3857).
  final String? tileMatrixSet;

  /// CRS/SRS code (default EPSG:3857 — the only one supported for now).
  final String? crs;

  /// Reserved for future non-3857 axis-order handling.
  final String? bboxAxisOrder;

  const CustomSourceSpec({
    required this.kind,
    required this.urlTemplate,
    required this.cacheKey,
    this.zoomMin = 0,
    this.zoomMax = 22,
    this.flipY = false,
    this.transparentOnMiss = false,
    this.layers,
    this.style,
    this.format,
    this.version,
    this.tileMatrixSet,
    this.crs,
    this.bboxAxisOrder,
  });
}
