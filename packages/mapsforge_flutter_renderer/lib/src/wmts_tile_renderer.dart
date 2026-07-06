import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/src/tile_http.dart';

/// Renders a WMTS source via the KVP `GetTile` request. Assumes a Web-Mercator
/// tile matrix set (GoogleMapsCompatible / EPSG:3857), so the map's tile z/x/y
/// map directly to `TILEMATRIX`/`TILECOL`/`TILEROW` (`TILEMATRIX` = the zoom
/// number). RESTful WMTS (a `{z}/{y}/{x}` URL template) should be added as an
/// XYZ source instead.
///
/// Never throws — failures return [JobResult.unsupported].
class WmtsTileRenderer extends Renderer {
  final CustomSourceSpec spec;

  WmtsTileRenderer(this.spec);

  @override
  bool get transparentOnMiss => spec.transparentOnMiss;

  @override
  Future<JobResult> executeJob(JobRequest job) async {
    final int z = job.tile.zoomLevel;
    if (z < spec.zoomMin || z > spec.zoomMax) return JobResult.unsupported();

    final uri = buildKvpUri(spec.urlTemplate, {
      'SERVICE': 'WMTS',
      'REQUEST': 'GetTile',
      'VERSION': '1.0.0',
      'LAYER': spec.layers ?? '',
      'STYLE': spec.style ?? '',
      'FORMAT': spec.format ?? 'image/png',
      'TILEMATRIXSET': spec.tileMatrixSet ?? '',
      'TILEMATRIX': '$z',
      'TILEROW': '${job.tile.tileY}',
      'TILECOL': '${job.tile.tileX}',
    });

    return fetchTileImage(uri);
  }

  @override
  Future<JobResult> retrieveLabels(JobRequest job) => Future.value(JobResult.unsupported());

  @override
  String getRenderKey() => spec.cacheKey;

  @override
  bool supportLabels() => false;
}
