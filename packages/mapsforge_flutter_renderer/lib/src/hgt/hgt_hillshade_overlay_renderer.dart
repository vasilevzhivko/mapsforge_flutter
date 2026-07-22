import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:mapsforge_flutter_core/dart_isolate.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/src/ui/tile_picture.dart';

/// Shaded relief (hillshade) as a translucent OVERLAY tile renderer, computed
/// from HGT/SRTM elevation files. Stack it on top of a vector base map with
/// `model.addRenderer(...)`: flat terrain stays fully transparent, shadowed
/// slopes get a gentle darkening and lit slopes a faint white — so the base
/// map's colours and features stay readable, like a printed topo.
///
/// Rendering notes (each of these was a hard-won lesson):
/// - The elevation grid is sampled at the DEM's NATIVE resolution (capped),
///   never finer — oversampling makes the ~90 m cells show as a halftone grid.
///   The small image is then upscaled bilinearly to the tile size.
/// - Pixels are PREMULTIPLIED (ui.decodeImageFromPixels expects that): a
///   straight-alpha white highlight would composite at full strength and wash
///   the map out to white stripes.
/// - The light azimuth is converted to the math convention of the aspect
///   atan2: az_math = 360 − azimuth + 90 (NW 315° → 135°). Using 315 directly
///   inverts the relief — peaks read as pits.
/// - The shading fades out at high zoom, where a tile spans only a few DEM
///   cells and the "relief" would degenerate into one big uniform wash.
class HgtHillshadeOverlayRenderer extends Renderer {
  final HgtProvider hgtProvider;

  /// Cartographic light azimuth in degrees (315 = from the NW, the norm).
  final double azimuthDeg;

  /// Light altitude above the horizon in degrees.
  final double altitudeDeg;

  /// The DEM's native cell size in degrees (SRTM3 ≈ 1/1200°). Used to size the
  /// sample grid so we never sample finer than the data.
  final double cellSizeDeg;

  /// Below this zoom the overlay renders nothing. At country-scale zooms a
  /// single tile spans dozens of 1° elevation files (~3 MB each) — loading them
  /// all is a big memory spike right when the whole map is visible, and the
  /// relief is barely legible at that scale anyway.
  final int minZoom;

  /// Vertical exaggeration for the slope/aspect calculation. The ~90 m DEM
  /// under-represents how steep real terrain (ridges, cirques like Vihren) looks
  /// on screen; scaling the gradient makes the relief read with more "pop".
  /// 1.0 = true slopes; ~1.6 is a tasteful accent. Turn up for stronger relief.
  final double zFactor;

  /// Peak opacity (0–255, premultiplied) of shadowed slopes / lit slopes. Higher
  /// = stronger accent. Kept below full so the base map's colours stay readable.
  final int shadowMaxAlpha;
  final int lightMaxAlpha;

  /// Long-lived isolate running the DEM sampling + shading math off the UI
  /// thread. The request is a handful of numbers and the reply one small RGBA
  /// buffer (≤ ~37 KB), so — unlike the vector read path — the isolate
  /// boundary is cheap here. Resolves to null when unavailable (web,
  /// non-file provider, spawn failure); then the math runs in-process.
  Future<FlutterIsolateInstance?>? _shadeIsolate;

  HgtHillshadeOverlayRenderer({
    required this.hgtProvider,
    this.azimuthDeg = 315,
    this.altitudeDeg = 45,
    this.cellSizeDeg = 1 / 1200,
    this.minZoom = 9,
    this.zFactor = 1.6,
    this.shadowMaxAlpha = 104,
    this.lightMaxAlpha = 32,
  }) {
    final provider = hgtProvider;
    if (provider is HgtFileProvider) {
      // Pre-spawn so the isolate startup overlaps app/map startup. The isolate
      // opens its own HgtFileProvider from the same directory (HGT cell caches
      // then live in the isolate's heap, not the UI isolate's).
      _shadeIsolate = () async {
        try {
          final instance = FlutterIsolateInstance();
          await instance.spawn(
            _shadeIsolateEntry,
            _ShadeIsolateInit(provider.directoryPath, provider.step, provider.columnsPerDegree, provider.maxEntries),
          );
          return instance;
        } catch (_) {
          return null; // no isolate support (web) or spawn failure
        }
      }();
    }
  }

  @override
  void dispose() {
    unawaited(_shadeIsolate?.then((instance) => instance?.dispose()));
    super.dispose();
  }

  @override
  Future<JobResult> executeJob(JobRequest jobRequest) async {
    final tile = jobRequest.tile;
    final tileSize = MapsforgeSettingsMgr().tileSize.ceil();
    // Skip entirely at low zoom (see [minZoom]) — no HGT load, no compute.
    if (tile.zoomLevel < minZoom) {
      return JobResult.normal(await _transparentTile(tileSize));
    }
    final bbox = tile.getBoundingBox();
    final s = bbox.minLatitude,
        n = bbox.maxLatitude,
        w = bbox.minLongitude,
        e = bbox.maxLongitude;

    // Gentle fade at the highest zooms, where a tile spans only a couple of
    // DEM cells — the shading turns into one soft wash there. Kept mild: a
    // dense vector map reads fine with relief still clearly visible up close.
    final z = tile.zoomLevel;
    final double fade;
    if (z >= 18) {
      fade = 0.72;
    } else if (z == 17) {
      fade = 0.85;
    } else if (z == 16) {
      fade = 0.95;
    } else {
      fade = 1.0;
    }

    // Grid resolution. `cells` is how many native DEM cells the tile spans.
    final cells =
        math.max(((e - w) / cellSizeDeg).ceil(), ((n - s) / cellSizeDeg).ceil());
    var g = cells;
    // Floor the grid higher when zoomed in: the DEM has no more real detail, but
    // a denser bicubic-interpolated grid removes the coarse, "pixelated" gradient
    // steps you otherwise see over steep peaks up close. Only high-zoom tiles hit
    // this floor (few on screen), so the extra compute is cheap.
    if (g < 64) g = 64;
    if (g > 96) g = 96; // cap: the small grid is upscaled to the tile anyway
    // Bicubic (16 lookups/sample, C1-smooth) is only needed when we OVERSAMPLE
    // the DEM — i.e. zoomed in, where cells < g and bilinear's per-cell gradient
    // steps would show as "pixelated" squares. When zoomed out we UNDERSAMPLE
    // (cells >= g): bicubic buys nothing but costs 4× the lookups, and low zoom
    // is exactly where the many large-span tiles make the UI lag. So: bilinear
    // when undersampling, bicubic when oversampling.
    final bicubic = cells < g;

    final request = _ShadeGridRequest(
      s: s,
      n: n,
      w: w,
      e: e,
      g: g,
      bicubic: bicubic,
      fade: fade,
      azimuthDeg: azimuthDeg,
      altitudeDeg: altitudeDeg,
      zFactor: zFactor,
      shadowMaxAlpha: shadowMaxAlpha,
      lightMaxAlpha: lightMaxAlpha,
    );
    // Compute the shading grid in the dedicated isolate when available; the
    // in-process path is the fallback (web, tests, non-file providers).
    Uint8List? out;
    final FlutterIsolateInstance? isolate = _shadeIsolate == null ? null : await _shadeIsolate;
    if (isolate != null) {
      out = await isolate.compute(request);
    } else {
      out = _computeShadeGrid(hgtProvider, request);
    }
    if (out == null) return JobResult.normal(await _transparentTile(tileSize));

    // Upscale the small native-res grid to the tile size with bilinear
    // filtering (drawing it 1:1 would show hard blocky stair-steps), then
    // rasterize to a bitmap up front. Returning a Picture that references
    // `small` would either keep the small image alive in every cached tile or
    // (if we dispose it) risk a use-after-free; a self-contained bitmap avoids
    // both. One 256² tile ≈ 256 KB — see tileCacheShare for the bound.
    final small = await _imageFromRgba(out, g, g);
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec,
        ui.Rect.fromLTWH(0, 0, tileSize.toDouble(), tileSize.toDouble()));
    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.high
      ..isAntiAlias = true;
    canvas.drawImageRect(
      small,
      ui.Rect.fromLTWH(0, 0, g.toDouble(), g.toDouble()),
      ui.Rect.fromLTWH(0, 0, tileSize.toDouble(), tileSize.toDouble()),
      paint,
    );
    final picture = rec.endRecording();
    final tileImg = picture.toImageSync(tileSize, tileSize);
    picture.dispose();
    small.dispose();
    return JobResult.normal(TilePicture.fromBitmap(tileImg));
  }

  /// A small slice of the global tile-bitmap budget: enough for the visible
  /// viewport plus a pan buffer so tiles aren't evicted and re-rendered (which
  /// flickers), but far below the base map's share so a second full-size cache
  /// doesn't blow memory.
  @override
  double get tileCacheShare => 0.25;

  /// Skip zoom±1 prefetch: an overlay doesn't need instant zoom, and prefetched
  /// off-zoom tiles would evict the visible ones from this smaller cache and
  /// make the relief flicker while panning.
  @override
  bool get prefetchAdjacentZooms => false;

  @override
  bool get transparentOnMiss => true;

  Future<TilePicture> _transparentTile(int tileSize) async {
    final rec = ui.PictureRecorder();
    ui.Canvas(rec,
        ui.Rect.fromLTWH(0, 0, tileSize.toDouble(), tileSize.toDouble()));
    final img = rec.endRecording().toImageSync(tileSize, tileSize);
    return TilePicture.fromBitmap(img);
  }

  Future<ui.Image> _imageFromRgba(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888,
        (img) => completer.complete(img));
    return completer.future;
  }

  @override
  Future<JobResult> retrieveLabels(JobRequest jobRequest) {
    return Future.value(JobResult.unsupported());
  }

  @override
  String getRenderKey() {
    return 'hillshade_overlay_${azimuthDeg}_${altitudeDeg}_${zFactor}_'
        '${shadowMaxAlpha}_$lightMaxAlpha';
  }

  @override
  bool supportLabels() {
    return false;
  }

  /// The isolate's own HGT provider, created once from the init message.
  static HgtFileProvider? _isolateProvider;

  @pragma('vm:entry-point')
  static Future<void> _shadeIsolateEntry(IsolateInitInstanceParams params) async {
    final init = params.initObject as _ShadeIsolateInit;
    _isolateProvider ??= HgtFileProvider(
      directoryPath: init.directoryPath,
      step: init.step,
      columnsPerDegree: init.columnsPerDegree,
      maxEntries: init.maxEntries,
    );
    await FlutterIsolateInstance.isolateInit(params, _acceptShadeRequest);
  }

  @pragma('vm:entry-point')
  static Future _acceptShadeRequest(Object request) async {
    try {
      return _computeShadeGrid(_isolateProvider!, request as _ShadeGridRequest);
    } catch (error, stacktrace) {
      // Never let an error escape into the isolate's zone: it would be
      // unhandled there AND leave the main-side compute() future hanging.
      // A transparent tile (null) is the correct degraded result.
      print('hillshade isolate: $error');
      print(stacktrace);
      return null;
    }
  }

  /// Samples the DEM, smooths it and computes the premultiplied-RGBA shading
  /// grid (g×g). Pure math — runs identically in the shade isolate and (as
  /// fallback) in-process. Returns null when the tile has no DEM coverage.
  static Uint8List? _computeShadeGrid(HgtProvider provider, _ShadeGridRequest r) {
    final s = r.s, n = r.n, w = r.w, e = r.e;
    final g = r.g;
    final gw = g + 2, gh = g + 2;
    final elev = Float32List(gw * gh);
    final has = Uint8List(gw * gh);
    var any = false;
    var sum = 0.0;
    for (var y = 0; y < gh; y++) {
      final lat = n - (y - 0.5) / g * (n - s);
      for (var x = 0; x < gw; x++) {
        final lng = w + (x - 0.5) / g * (e - w);
        final file = provider.getForLatLon(lat, lng);
        final ev = r.bicubic ? file.elevationBicubic(lat, lng) : file.elevationBilinear(lat, lng);
        if (ev != null) {
          elev[y * gw + x] = ev;
          has[y * gw + x] = 1;
          sum += ev;
          any = true;
        }
      }
    }
    if (!any) return null;
    final mean = sum / has.fold<int>(0, (a, b) => a + b);
    for (var i = 0; i < elev.length; i++) {
      if (has[i] == 0) elev[i] = mean;
    }
    // Light 3×3 smoothing so DEM cell steps don't read as aspect banding.
    final sm = Float32List(gw * gh);
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        var acc = 0.0;
        var cnt = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= gh) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= gw) continue;
            acc += elev[yy * gw + xx];
            cnt++;
          }
        }
        sm[y * gw + x] = acc / cnt;
      }
    }

    final mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * math.cos((s + n) / 2 * math.pi / 180.0);
    final cellX = (e - w) / g * mPerDegLng;
    final cellY = (n - s) / g * mPerDegLat;
    // Azimuth → math convention (see class docs).
    final az = (360.0 - r.azimuthDeg + 90.0) * math.pi / 180.0;
    final zenith = r.altitudeDeg * math.pi / 180.0;
    final cosZen = math.cos(zenith), sinZen = math.sin(zenith);
    final zFactor = r.zFactor;
    final fade = r.fade;

    final out = Uint8List(g * g * 4);
    for (var y = 0; y < g; y++) {
      for (var x = 0; x < g; x++) {
        final gx = x + 1, gy = y + 1;
        final zL = sm[gy * gw + gx - 1], zR = sm[gy * gw + gx + 1];
        final zU = sm[(gy - 1) * gw + gx], zD = sm[(gy + 1) * gw + gx];
        // zFactor exaggerates the slope so the relief reads with more accent.
        final dzdx = zFactor * (zR - zL) / (2 * cellX);
        final dzdy = zFactor * (zD - zU) / (2 * cellY);
        final slope = math.atan(math.sqrt(dzdx * dzdx + dzdy * dzdy));
        final aspect = math.atan2(dzdy, -dzdx);
        var hs = cosZen * math.cos(slope) + sinZen * math.sin(slope) * math.cos(az - aspect);
        if (hs < 0) hs = 0;
        final dev = hs - cosZen; // flat → 0 → fully transparent
        final i = (y * g + x) * 4;
        if (dev < 0) {
          // Manual min instead of num.clamp — this runs per pixel and clamp
          // showed up hot in CPU profiles. The value is non-negative here.
          double v = -dev * 235;
          if (v > r.shadowMaxAlpha) v = r.shadowMaxAlpha.toDouble();
          final a = (v * fade).toInt();
          out[i] = 0;
          out[i + 1] = 0;
          out[i + 2] = 0;
          out[i + 3] = a;
        } else {
          double v = dev * 110;
          if (v > r.lightMaxAlpha) v = r.lightMaxAlpha.toDouble();
          final a = (v * fade).toInt();
          out[i] = a; // premultiplied white
          out[i + 1] = a;
          out[i + 2] = a;
          out[i + 3] = a;
        }
      }
    }
    return out;
  }
}

//////////////////////////////////////////////////////////////////////////////

/// Init message for the shade isolate: enough to rebuild the HgtFileProvider.
class _ShadeIsolateInit {
  final String directoryPath;
  final int step;
  final int columnsPerDegree;
  final int maxEntries;

  _ShadeIsolateInit(this.directoryPath, this.step, this.columnsPerDegree, this.maxEntries);
}

//////////////////////////////////////////////////////////////////////////////

/// Per-tile request for the shade isolate — plain numbers only.
class _ShadeGridRequest {
  final double s, n, w, e;
  final int g;
  final bool bicubic;
  final double fade;
  final double azimuthDeg;
  final double altitudeDeg;
  final double zFactor;
  final int shadowMaxAlpha;
  final int lightMaxAlpha;

  _ShadeGridRequest({
    required this.s,
    required this.n,
    required this.w,
    required this.e,
    required this.g,
    required this.bicubic,
    required this.fade,
    required this.azimuthDeg,
    required this.altitudeDeg,
    required this.zFactor,
    required this.shadowMaxAlpha,
    required this.lightMaxAlpha,
  });
}
