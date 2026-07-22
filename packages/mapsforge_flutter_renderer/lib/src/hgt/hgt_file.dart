import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_core/utils.dart';

class HgtFile {
  static final _log = Logger('HgtFile');

  static const int ocean = -500;

  static const int invalid = -32767;

  // minimum lat/lon of this file
  final int baseLat;
  final int baseLon;

  /// width of this file in degree lon
  final int lonWidth;
  final int latHeight;

  // number of data rows of this file
  final int rows;
  final int columns;

  /// elevation data in int16 (meters)
  final Int16List _elevations;

  final Map<int, HgtRastering> _zoomRasterings = {};

  HgtFile._({
    required this.baseLat,
    required this.baseLon,
    required this.lonWidth,
    required this.latHeight,
    required this.rows,
    required this.columns,
    required Int16List elevations,
  }) : assert(lonWidth > 0),
       assert(latHeight > 0),
       assert(rows > 0),
       assert(columns > 0),
       _elevations = elevations;

  HgtFile._noFile({required this.baseLat, required this.baseLon, required this.lonWidth, required this.latHeight})
    : assert(lonWidth > 0),
      assert(latHeight > 0),
      _elevations = Int16List(0),
      rows = 0,
      columns = 0;

  static HgtFile readFromFile(File file, {required int baseLat, required int baseLon, required int tileWidth, required int tileHeight, required int rows}) {
    if (!file.existsSync()) {
      _log.warning("HGT file not found: ${file.path}");
      return HgtFile._noFile(baseLat: baseLat, baseLon: baseLon, lonWidth: tileWidth, latHeight: tileHeight);
    }

    final Uint8List bytes = file.readAsBytesSync();
    final int columns = bytes.lengthInBytes ~/ 2 ~/ rows;
    if (bytes.lengthInBytes % 2 != 0 || columns < 2) {
      // A truncated/corrupt file (e.g. interrupted download) must behave like
      // a missing one — a throw here escalated to an unhandled error in the
      // shade isolate and left tile futures hanging.
      _log.warning('Corrupt/truncated HGT file (${bytes.lengthInBytes} bytes): ${file.path}');
      return HgtFile._noFile(baseLat: baseLat, baseLon: baseLon, lonWidth: tileWidth, latHeight: tileHeight);
    }

    // HGT stores signed 16-bit big-endian.
    final ByteData bd = ByteData.sublistView(bytes);
    final elevations = Int16List(rows * columns);
    for (int i = 0; i < rows * columns; i++) {
      elevations[i] = bd.getInt16(i * 2, Endian.big);
    }

    return HgtFile._(baseLat: baseLat, baseLon: baseLon, lonWidth: tileWidth, latHeight: tileHeight, rows: rows, columns: columns, elevations: elevations);
  }

  HgtRastering? raster(PixelProjection projection) {
    if (rows == 0) {
      return null;
    }
    HgtRastering? hgtRastering = _zoomRasterings[projection.scalefactor.zoomlevel];
    if (hgtRastering != null) {
      if (hgtRastering.xPositions.length < 2 || hgtRastering.yPositions.length < 2) return null;
      return hgtRastering;
    }

    MapRectangle rectangle = MapRectangle(
      projection.longitudeToPixelX(baseLon.toDouble()),
      projection.latitudeToPixelY((baseLat + latHeight).toDouble()),
      projection.longitudeToPixelX((baseLon + lonWidth).toDouble()),
      projection.latitudeToPixelY(baseLat.toDouble()),
    );

    double latStep = latHeight / (rows - 1);
    double lonStep = rectangle.getWidth() / (columns - 1);

    double factorX = max(4 / lonStep * MapsforgeSettingsMgr().getDeviceScaleFactor(), 1);
    double factorY = max(4 / rectangle.getHeight() * (columns - 1) * MapsforgeSettingsMgr().getDeviceScaleFactor(), 1);
    //print("Factor for $projection: $factor, $baseLat, $baseLon, $lonWidth, $latHeight, $rows, $columns");
    if (factorX > 1) {
      lonStep *= factorX;
    }
    if (factorY > 1) {
      latStep *= factorY;
    }

    List<double> xPositions = [];
    for (double x = rectangle.left; x <= rectangle.right; x += lonStep) {
      xPositions.add(x);
    }
    // possible precision error may prevent the last column. We need the last column for visual perfect borders to the next file
    if (xPositions.last != rectangle.right) {
      if (xPositions.last > rectangle.right - lonStep / 2) xPositions.removeLast();
      xPositions.add(rectangle.right);
    }
    // assert(
    //   (xPositions.length * factor).floor() <= columns,
    //   "xPositions.length: ${xPositions.length}, factor: $factor, _hgtFile.columns: ${columns}, right: ${rectangle.right}, lastPos: ${xPositions.last}, lonStep: $lonStep",
    // );

    List<double> yPositions = [];
    for (double lat = (baseLat + latHeight).toDouble(); lat >= (baseLat).toDouble(); lat -= latStep) {
      double yPosition = projection.latitudeToPixelY(lat);
      yPositions.add(yPosition);
    }
    if (yPositions.last != rectangle.bottom) {
      if (yPositions.last >= rectangle.bottom - latStep / 2) yPositions.removeLast();
      yPositions.add(rectangle.bottom);
    }
    //    assert((yPositions.length * factor).floor() <= rows, "yPositions.length: ${yPositions.length}, factor: $factor, hgtFile.rows: $rows");

    Int16List elevations = _elevations;
    if (factorX > 1 || factorY > 1) {
      elevations = Int16List(xPositions.length * yPositions.length);
      for (int y = 0; y < yPositions.length; ++y) {
        for (int x = 0; x < xPositions.length; ++x) {
          int realX = (x * factorX).floor();
          if (x == xPositions.length - 1) realX = columns - 1;
          int realY = (y * factorY).floor();
          if (y == yPositions.length - 1) realY = rows - 1;
          elevations[y * xPositions.length + x] = elevation(realX, realY);
        }
      }
    }

    hgtRastering = HgtRastering(xPositions, yPositions, elevations);
    _zoomRasterings[projection.scalefactor.zoomlevel] = hgtRastering;
    if (hgtRastering.xPositions.length < 2 || hgtRastering.yPositions.length < 2) return null;
    return hgtRastering;
  }

  /// Returns the elevation in meters for the given lat/lon.
  ///
  /// The coordinates must lie within [baseLat..baseLat+width] and [baseLon..baseLon+width].
  ///
  /// Uses bilinear interpolation between surrounding samples.
  int? elevationAt(double latitude, double longitude) {
    if (rows == 0) {
      // file not found
      return null;
    }
    if (latitude < baseLat || latitude > baseLat + latHeight || longitude < baseLon || longitude > baseLon + lonWidth) {
      return null;
    }

    // HGT rows are north-to-south.
    // u, v are fractions of lat/lon coordinates inbetween the current file-boundaries
    final double u = (longitude - baseLon) / lonWidth;
    final double v = ((baseLat + latHeight) - latitude) / latHeight;

    // x,y are indices into the elevation data in double digits
    double x = u * (columns - 1);
    double y = v * (rows - 1);

    assert(x >= 0 && x < columns, 'x: $x, columns: $columns');
    assert(y >= 0 && y < rows, 'y: $y, rows: $rows');

    final q00 = elevation(x.round(), y.round());
    return q00;
  }

  /// Bilinearly interpolated elevation (meters), or null if outside coverage.
  ///
  /// Unlike [elevationAt] (nearest-neighbour), this returns a smooth value
  /// between the four surrounding SRTM samples. Nearest-neighbour produces a
  /// staircase when a GPS track is sampled more densely than the ~90m DEM grid,
  /// and the steps at cell boundaries inflate accumulated ascent/descent. Use
  /// this method when measuring elevation gain along a recorded track.
  double? elevationBilinear(double latitude, double longitude) {
    if (rows == 0) return null;
    if (latitude < baseLat ||
        latitude > baseLat + latHeight ||
        longitude < baseLon ||
        longitude > baseLon + lonWidth) {
      return null;
    }

    final double u = (longitude - baseLon) / lonWidth;
    final double v = ((baseLat + latHeight) - latitude) / latHeight;
    final double x = u * (columns - 1);
    final double y = v * (rows - 1);

    // Manual clamping: `num.clamp` showed up hot in CPU profiles of the
    // hillshade sampling loop.
    final int maxC = columns - 1, maxR = rows - 1;
    int x0 = x.floor();
    if (x0 < 0) {
      x0 = 0;
    } else if (x0 > maxC) {
      x0 = maxC;
    }
    int y0 = y.floor();
    if (y0 < 0) {
      y0 = 0;
    } else if (y0 > maxR) {
      y0 = maxR;
    }
    final int x1 = x0 + 1 > maxC ? maxC : x0 + 1;
    final int y1 = y0 + 1 > maxR ? maxR : y0 + 1;
    final double fx = x - x0;
    final double fy = y - y0;

    final int e00 = elevation(x0, y0);
    final int e10 = elevation(x1, y0);
    final int e01 = elevation(x0, y1);
    final int e11 = elevation(x1, y1);

    // If any corner is a void/ocean sentinel, fall back to nearest valid sample.
    bool bad(int e) => e == invalid || e == ocean;
    if (bad(e00) || bad(e10) || bad(e01) || bad(e11)) {
      int xr = x.round();
      if (xr > maxC) xr = maxC;
      int yr = y.round();
      if (yr > maxR) yr = maxR;
      final nn = elevation(xr, yr);
      return bad(nn) ? null : nn.toDouble();
    }

    final double top = e00 * (1 - fx) + e10 * fx;
    final double bot = e01 * (1 - fx) + e11 * fx;
    return top * (1 - fy) + bot * fy;
  }

  /// Bicubic (Catmull-Rom) interpolated elevation in meters, or null outside
  /// coverage. Unlike [elevationBilinear] — whose GRADIENT is discontinuous at
  /// cell borders, which makes hillshading show every ~90 m cell as a
  /// flat-shaded square when sampled finer than the grid — the bicubic surface
  /// has a continuous first derivative, so shading derived from it stays
  /// smooth at any zoom. Falls back to bilinear near voids/ocean sentinels.
  double? elevationBicubic(double latitude, double longitude) {
    if (rows == 0) return null;
    if (latitude < baseLat ||
        latitude > baseLat + latHeight ||
        longitude < baseLon ||
        longitude > baseLon + lonWidth) {
      return null;
    }

    final double u = (longitude - baseLon) / lonWidth;
    final double v = ((baseLat + latHeight) - latitude) / latHeight;
    final double x = u * (columns - 1);
    final double y = v * (rows - 1);
    final int maxC = columns - 1, maxR = rows - 1;
    int x1 = x.floor();
    if (x1 < 0) {
      x1 = 0;
    } else if (x1 > maxC) {
      x1 = maxC;
    }
    int y1 = y.floor();
    if (y1 < 0) {
      y1 = 0;
    } else if (y1 > maxR) {
      y1 = maxR;
    }
    final double fx = x - x1;
    final double fy = y - y1;

    // Clamped 4×4 neighbourhood indices, computed ONCE. The previous version
    // clamped per lookup and read every sample twice (void pre-scan + fit) —
    // 64 clamps and 32 array reads per call, which dominated CPU profiles of
    // the hillshade loop. Now: 16 reads, sentinel check inlined in the same
    // pass.
    final int c0 = x1 - 1 < 0 ? 0 : x1 - 1;
    final int c1 = x1;
    final int c2 = x1 + 1 > maxC ? maxC : x1 + 1;
    final int c3 = x1 + 2 > maxC ? maxC : x1 + 2;
    final int r0i = y1 - 1 < 0 ? 0 : y1 - 1;
    final int r1i = y1;
    final int r2i = y1 + 1 > maxR ? maxR : y1 + 1;
    final int r3i = y1 + 2 > maxR ? maxR : y1 + 2;

    final Int16List elevations = _elevations;
    final int b0 = r0i * columns, b1 = r1i * columns, b2 = r2i * columns, b3 = r3i * columns;

    final p = _bicubicScratch;
    p[0] = elevations[b0 + c0];
    p[1] = elevations[b0 + c1];
    p[2] = elevations[b0 + c2];
    p[3] = elevations[b0 + c3];
    p[4] = elevations[b1 + c0];
    p[5] = elevations[b1 + c1];
    p[6] = elevations[b1 + c2];
    p[7] = elevations[b1 + c3];
    p[8] = elevations[b2 + c0];
    p[9] = elevations[b2 + c1];
    p[10] = elevations[b2 + c2];
    p[11] = elevations[b2 + c3];
    p[12] = elevations[b3 + c0];
    p[13] = elevations[b3 + c1];
    p[14] = elevations[b3 + c2];
    p[15] = elevations[b3 + c3];

    // A void anywhere in the 4×4 neighbourhood would drag the sentinel value
    // into the fit; defer to bilinear (it has its own void handling).
    for (var i = 0; i < 16; i++) {
      final int e = p[i];
      if (e == invalid || e == ocean) {
        return elevationBilinear(latitude, longitude);
      }
    }

    final r0 = _cat(p[0].toDouble(), p[1].toDouble(), p[2].toDouble(), p[3].toDouble(), fx);
    final r1 = _cat(p[4].toDouble(), p[5].toDouble(), p[6].toDouble(), p[7].toDouble(), fx);
    final r2 = _cat(p[8].toDouble(), p[9].toDouble(), p[10].toDouble(), p[11].toDouble(), fx);
    final r3 = _cat(p[12].toDouble(), p[13].toDouble(), p[14].toDouble(), p[15].toDouble(), fx);
    return _cat(r0, r1, r2, r3, fy);
  }

  /// Scratch buffer for [elevationBicubic] — safe because all callers run
  /// synchronously on one isolate; avoids a 16-element allocation per sample.
  static final Int16List _bicubicScratch = Int16List(16);

  /// Catmull-Rom interpolation at parameter [t].
  static double _cat(double p0, double p1, double p2, double p3, double t) =>
      p1 + 0.5 * t * (p2 - p0 + t * (2 * p0 - 5 * p1 + 4 * p2 - p3 + t * (3 * (p1 - p2) + p3 - p0)));

  int elevation(int col, int row) {
    return _elevations[row * columns + col];
  }

  @override
  String toString() {
    return 'HgtFile{baseLat: $baseLat, baseLon: $baseLon, lonWidth: $lonWidth, latHeight: $latHeight, rows: $rows, columns: $columns}';
  }
}

//////////////////////////////////////////////////////////////////////////////

class HgtRastering {
  final List<double> xPositions;

  final List<double> yPositions;

  final Int16List elevations;

  HgtRastering(this.xPositions, this.yPositions, this.elevations)
    : assert(
        elevations.length == xPositions.length * yPositions.length,
        "elevations.length: ${elevations.length}, xPositions.length: ${xPositions.length}, yPositions.length: ${yPositions.length}",
      );

  int elevation(int col, int row) {
    return elevations[row * xPositions.length + col];
  }
}
