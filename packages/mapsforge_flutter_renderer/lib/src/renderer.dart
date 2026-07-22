import 'package:mapsforge_flutter_renderer/src/job/job_request.dart';
import 'package:mapsforge_flutter_renderer/src/job/job_result.dart';

/// Abstract base class for tile rendering implementations.
///
/// This class defines the contract for rendering map tiles from various data sources.
/// Implementations handle specific data sources (local files, online services) and
/// provide both tile rendering and label extraction capabilities.
///
/// Key responsibilities:
/// - Execute rendering jobs to generate tile bitmaps
/// - Extract labels for separate rendering (rotation support)
/// - Provide cache keys for optimization
/// - Manage renderer lifecycle and resources
abstract class Renderer {
  /// Disposes of renderer resources and cleans up.
  ///
  /// Called when the renderer is no longer needed to free up resources
  /// such as caches, network connections, or file handles.
  void dispose() {}

  /// Executes a rendering job to generate a tile bitmap.
  ///
  /// Processes the job request and generates the corresponding tile image
  /// based on the renderer's data source and configuration.
  ///
  /// [jobRequest] Request containing tile coordinates and rendering parameters
  /// Returns JobResult with tile bitmap or null if no data available
  /// Throws exception if rendering fails (e.g., server unreachable)
  Future<JobResult> executeJob(JobRequest jobRequest);

  /// Retrieves labels for separate rendering to support map rotation.
  ///
  /// For rotation-enabled maps, labels are rendered separately from the base
  /// map to prevent text distortion. This method extracts label information
  /// that can be rendered dynamically with proper orientation.
  ///
  /// [jobRequest] Request containing tile coordinates and rendering parameters
  /// Returns JobResult with label rendering instructions
  Future<JobResult> retrieveLabels(JobRequest jobRequest);

  /// Returns a unique cache key for this renderer configuration.
  ///
  /// The cache key identifies the renderer's current configuration to enable
  /// proper cache separation. Keys should be identical for configurations that
  /// produce the same output and different for configurations that produce
  /// different results (e.g., different themes, font sizes, or data sources).
  ///
  /// Returns unique string identifier for cache management
  String getRenderKey();

  /// Returns whether this renderer supports separate label rendering.
  ///
  /// Indicates if the renderer can extract labels separately from the base
  /// map rendering, which is required for rotation support.
  ///
  /// Returns true if separate label rendering is supported
  bool supportLabels();

  /// Whether a tile with no data should fall back to a fully transparent tile
  /// instead of the opaque "No data available" placeholder.
  ///
  /// Base renderers (the offline vector map, a base online source) want the
  /// opaque placeholder so gaps are visible. A transparent OVERLAY source
  /// stacked on top of a base must NOT paint an opaque grid over it — it returns
  /// true so missing/failed tiles simply show nothing and the layer below shows
  /// through. Defaults to false.
  bool get transparentOnMiss => false;

  /// This renderer's share (0..1) of the global rendered-tile byte budget
  /// ([MapsforgeSettingsMgr.tileBitmapBudgetBytes]). Every renderer layer has
  /// its OWN tile cache of full-tile rasterized images, so the budget is split
  /// between layers instead of multiplying: the base map takes the lion's
  /// share; a lightweight OVERLAY (e.g. hillshade) should override this with a
  /// small share. Defaults to 0.75.
  double get tileCacheShare => 0.75;

  /// The map background color (ARGB) to paint underneath this renderer's
  /// tiles, or null for no fill. For a base map this makes not-yet-rendered
  /// areas (e.g. right after a multi-level zoom jump) read as empty land in
  /// the theme's color instead of holes showing the app background.
  int? get backgroundColor => null;

  /// Whether the tile queue should speculatively render zoom±1 tiles into this
  /// renderer's cache after the current zoom is filled. Great for a base map
  /// (instant zoom), but a lightweight overlay with a small cache should opt out
  /// — the off-zoom tiles would evict the visible ones and cause flicker while
  /// panning. Defaults true.
  bool get prefetchAdjacentZooms => true;
}
