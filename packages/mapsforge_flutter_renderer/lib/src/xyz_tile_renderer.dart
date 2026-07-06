import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/src/ui/tile_picture.dart';

/// The kind of online source a [CustomSourceSpec] describes. Phase 1 implements
/// only [xyz]; [wmts] and [wms] are declared as seams for later renderers.
enum RendererKind { xyz, wmts, wms }

/// Fork-side, engine-agnostic description of a user-defined online tile source.
/// The app maps its own model onto this before building a [Renderer].
class CustomSourceSpec {
  final RendererKind kind;
  final String urlTemplate;
  final int zoomMin;
  final int zoomMax;

  /// TMS Y-axis flip: false = XYZ/Google/OSM scheme (top-left origin),
  /// true = TMS (bottom-left origin).
  final bool flipY;

  /// Stable cache key (unique per source) so each source keeps its own tile cache.
  final String cacheKey;

  /// True for OVERLAY sources: a missing/failed tile must be transparent so the
  /// layers below show through, not the opaque "No data" grid.
  final bool transparentOnMiss;

  /// Future WMTS/WMS fields (unused in Phase 1).
  final String? tileMatrixSet;
  final String? crs;
  final String? bboxAxisOrder;

  const CustomSourceSpec({
    required this.kind,
    required this.urlTemplate,
    required this.cacheKey,
    this.zoomMin = 0,
    this.zoomMax = 22,
    this.flipY = false,
    this.transparentOnMiss = false,
    this.tileMatrixSet,
    this.crs,
    this.bboxAxisOrder,
  });
}

/// Builds a [Renderer] for a [CustomSourceSpec]. Phase 1 handles [RendererKind.xyz];
/// WMTS/WMS slot in here as sibling renderers without touching the app.
class CustomRendererFactory {
  static Renderer create(CustomSourceSpec spec) {
    switch (spec.kind) {
      case RendererKind.xyz:
        return XyzTileRenderer(spec);
      case RendererKind.wmts:
      case RendererKind.wms:
        throw UnimplementedError('Renderer kind ${spec.kind} is not implemented yet');
    }
  }
}

/// Renders a user-defined XYZ raster tile source (URL template with `{z}/{x}/{y}`)
/// by fetching PNG/JPEG tiles over HTTP. Web-Mercator (EPSG:3857) only.
///
/// Mirrors the built-in OsmOnlineRenderer but is fully configurable and — unlike
/// it — never throws: a network/decoding failure returns [JobResult.unsupported]
/// so the tile queue substitutes a transparent tile (overlay) or the "No data"
/// placeholder (base). This keeps failures off the global-zone FATAL path, which
/// matters because the app is offline-first and these tiles routinely fail
/// (airplane mode, throttling, server hiccups).
class XyzTileRenderer extends Renderer {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      responseType: ResponseType.bytes,
      followRedirects: true,
      // Many tile servers 403 without a real User-Agent identifying the app.
      headers: {'User-Agent': 'hikerbg/app (+https://hiker.bg)'},
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    ),
  );

  final CustomSourceSpec spec;

  XyzTileRenderer(this.spec);

  @override
  bool get transparentOnMiss => spec.transparentOnMiss;

  @override
  Future<JobResult> executeJob(JobRequest job) async {
    final int z = job.tile.zoomLevel;
    // Out of the source's zoom range → no tile, without hitting the network.
    if (z < spec.zoomMin || z > spec.zoomMax) return JobResult.unsupported();

    final int x = job.tile.tileX;
    final int y = spec.flipY ? (Tile.getMaxTileNumber(z) - job.tile.tileY) : job.tile.tileY;

    final String url = spec.urlTemplate
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y')
        // {s} subdomain placeholder is not load-balanced in Phase 1; pin to 'a'
        // so the URL is still valid.
        .replaceAll('{s}', 'a');

    try {
      final response = await _dio.get(url);
      if (response.data == null) return JobResult.unsupported();

      final codec = await ui.instantiateImageCodec(response.data);
      final frame = await codec.getNextFrame();
      final ui.Image img = frame.image;
      return JobResult.normal(TilePicture.fromBitmap(img));
    } catch (_) {
      // Network error, non-2xx, decode failure, offline — never rethrow.
      return JobResult.unsupported();
    }
  }

  @override
  Future<JobResult> retrieveLabels(JobRequest job) {
    return Future.value(JobResult.unsupported());
  }

  @override
  String getRenderKey() => spec.cacheKey;

  @override
  bool supportLabels() => false;
}
