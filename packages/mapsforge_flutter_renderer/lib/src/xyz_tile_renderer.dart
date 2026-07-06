import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/src/tile_http.dart';

/// Renders a user-defined XYZ raster tile source (URL template with `{z}/{x}/{y}`)
/// by fetching PNG/JPEG tiles over HTTP. Web-Mercator (EPSG:3857) only. Also
/// covers RESTful WMTS, whose tile URLs are XYZ templates.
///
/// Never throws — a network/decoding failure returns [JobResult.unsupported] so
/// the tile queue substitutes a transparent tile (overlay) or the "No data"
/// placeholder (base), keeping failures off the global-zone FATAL path.
class XyzTileRenderer extends Renderer {
  final CustomSourceSpec spec;

  XyzTileRenderer(this.spec);

  @override
  bool get transparentOnMiss => spec.transparentOnMiss;

  @override
  Future<JobResult> executeJob(JobRequest job) async {
    final int z = job.tile.zoomLevel;
    if (z < spec.zoomMin || z > spec.zoomMax) return JobResult.unsupported();

    final int x = job.tile.tileX;
    final int y = spec.flipY ? (Tile.getMaxTileNumber(z) - job.tile.tileY) : job.tile.tileY;

    final String url = spec.urlTemplate
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y')
        // {s} subdomain placeholder is not load-balanced; pin to 'a' so the URL
        // stays valid.
        .replaceAll('{s}', 'a');

    return fetchTileImage(Uri.parse(url));
  }

  @override
  Future<JobResult> retrieveLabels(JobRequest job) => Future.value(JobResult.unsupported());

  @override
  String getRenderKey() => spec.cacheKey;

  @override
  bool supportLabels() => false;
}
