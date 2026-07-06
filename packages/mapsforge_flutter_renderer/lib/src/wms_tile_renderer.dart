import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/src/tile_http.dart';

/// Renders a WMS source by turning each map tile into a `GetMap` request: the
/// tile's Web-Mercator (EPSG:3857) bounding box is computed and a tile-sized
/// image is requested for it. Supports WMS 1.1.1 (`SRS`) and 1.3.0 (`CRS`).
/// EPSG:3857 only — for that CRS the axis order is X,Y in both versions, which
/// side-steps the classic 1.3.0/EPSG:4326 lat,lon axis-swap.
///
/// Never throws — failures return [JobResult.unsupported].
class WmsTileRenderer extends Renderer {
  /// Half the Web-Mercator world extent in metres (π · 6378137).
  static const double _originShift = 20037508.342789244;

  final CustomSourceSpec spec;

  WmsTileRenderer(this.spec);

  @override
  bool get transparentOnMiss => spec.transparentOnMiss;

  @override
  Future<JobResult> executeJob(JobRequest job) async {
    final int z = job.tile.zoomLevel;
    if (z < spec.zoomMin || z > spec.zoomMax) return JobResult.unsupported();

    // Web-Mercator tile bbox in metres (XYZ scheme: top-left origin).
    final int n = 1 << z; // 2^z
    final double span = (2 * _originShift) / n;
    final double minX = -_originShift + job.tile.tileX * span;
    final double maxX = minX + span;
    final double maxY = _originShift - job.tile.tileY * span;
    final double minY = maxY - span;

    final bool is111 = spec.version == '1.1.1';
    final int size = MapsforgeSettingsMgr().tileSize.round();
    final String crs = (spec.crs != null && spec.crs!.isNotEmpty) ? spec.crs! : 'EPSG:3857';

    final uri = buildKvpUri(spec.urlTemplate, {
      'SERVICE': 'WMS',
      'VERSION': is111 ? '1.1.1' : '1.3.0',
      'REQUEST': 'GetMap',
      'LAYERS': spec.layers ?? '',
      'STYLES': spec.style ?? '',
      // 1.1.1 uses SRS, 1.3.0 uses CRS. For EPSG:3857 the bbox axis order is X,Y
      // in both, so a single bbox string works.
      is111 ? 'SRS' : 'CRS': crs,
      'BBOX': '$minX,$minY,$maxX,$maxY',
      'WIDTH': '$size',
      'HEIGHT': '$size',
      'FORMAT': spec.format ?? 'image/png',
      'TRANSPARENT': spec.transparentOnMiss ? 'TRUE' : 'FALSE',
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
