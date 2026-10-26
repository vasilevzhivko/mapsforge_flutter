import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/src/tile_http.dart';
import 'package:mapsforge_flutter_renderer/src/ui/tile_picture.dart';

/// Renders a user-defined XYZ raster tile source (URL template with `{z}/{x}/{y}`)
/// by fetching PNG/JPEG tiles over HTTP. Web-Mercator (EPSG:3857) only. Also
/// covers RESTful WMTS, whose tile URLs are XYZ templates.
///
/// Above [CustomSourceSpec.nativeZoomMax] it overzooms: the ancestor tile at the
/// native zoom is fetched once (kept in a small LRU, in-flight requests shared)
/// and the matching sub-square is scaled up to a full tile.
///
/// Never throws — a network/decoding failure returns [JobResult.unsupported] so
/// the tile queue substitutes a transparent tile (overlay) or the "No data"
/// placeholder (base), keeping failures off the global-zone FATAL path.
class XyzTileRenderer extends Renderer {
  final CustomSourceSpec spec;

  /// Ancestor tiles used for overzoom, keyed "z/x/y". Futures, so the 4–16
  /// child tiles requested together share one download.
  final LinkedHashMap<String, Future<Uint8List?>> _parents = LinkedHashMap();
  static const int _maxParents = 48;

  XyzTileRenderer(this.spec);

  @override
  bool get transparentOnMiss => spec.transparentOnMiss;

  String _url(int z, int x, int y) {
    final int yy = spec.flipY ? (Tile.getMaxTileNumber(z) - y) : y;
    return spec.urlTemplate
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$yy')
        // {s} subdomain placeholder is not load-balanced; pin to 'a' so the URL
        // stays valid.
        .replaceAll('{s}', 'a');
  }

  @override
  Future<JobResult> executeJob(JobRequest job) async {
    final int z = job.tile.zoomLevel;
    if (z < spec.zoomMin || z > spec.zoomMax) return JobResult.unsupported();
    final int x = job.tile.tileX;
    final int y = job.tile.tileY;

    final int? native = spec.nativeZoomMax;
    if (native == null || z <= native) {
      return fetchTileImage(Uri.parse(_url(z, x, y)), headers: spec.headers);
    }
    return _overzoom(z, x, y, native);
  }

  Future<JobResult> _overzoom(int z, int x, int y, int native) async {
    try {
      final int dz = z - native;
      final int px = x >> dz;
      final int py = y >> dz;
      final bytes = await _parentBytes(native, px, py);
      if (bytes == null) return JobResult.unsupported();

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ui.Image parent = frame.image;
      try {
        final int n = 1 << dz;
        final double sw = parent.width / n;
        final double sh = parent.height / n;
        final src = ui.Rect.fromLTWH((x - (px << dz)) * sw, (y - (py << dz)) * sh, sw, sh);
        final int size = MapsforgeSettingsMgr().tileSize.round();
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          parent,
          src,
          ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.medium,
        );
        final picture = recorder.endRecording();
        final ui.Image out = await picture.toImage(size, size);
        picture.dispose();
        return JobResult.normal(TilePicture.fromBitmap(out));
      } finally {
        parent.dispose();
      }
    } catch (_) {
      return JobResult.unsupported();
    }
  }

  Future<Uint8List?> _parentBytes(int z, int x, int y) {
    final key = '$z/$x/$y';
    final cached = _parents.remove(key);
    if (cached != null) {
      _parents[key] = cached; // most recently used
      return cached;
    }
    final future = fetchTileBytes(Uri.parse(_url(z, x, y)), headers: spec.headers);
    _parents[key] = future;
    // A failed fetch must not stick — the next request retries.
    unawaited(future.then((b) {
      if (b == null && identical(_parents[key], future)) _parents.remove(key);
    }));
    while (_parents.length > _maxParents) {
      _parents.remove(_parents.keys.first);
    }
    return future;
  }

  @override
  Future<JobResult> retrieveLabels(JobRequest job) => Future.value(JobResult.unsupported());

  @override
  String getRenderKey() => spec.cacheKey;

  @override
  bool supportLabels() => false;

  @override
  void dispose() {
    _parents.clear();
    super.dispose();
  }
}
