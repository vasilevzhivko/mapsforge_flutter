import 'dart:math';

import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';
import 'package:mapsforge_flutter_rendertheme/src/model/nodewayproperties.dart';
import 'package:mapsforge_flutter_rendertheme/src/util/douglas_peucker_mappoint.dart';
import 'package:mapsforge_flutter_rendertheme/src/util/map_path_helper.dart';

/// Properties for one Way as read from the datastore. Note that the properties are
/// dependent on the zoomLevel. Therefore one instance of WayProperties can be used for one zoomlevel only.
class WayProperties implements NodeWayProperties {
  final double maxGap = 5;

  final Way way;

  final int layer;

  final bool isClosedWay;

  /// cache for the absolute center of the way in mappixels
  Mappoint? center;

  /// cache for absolute coordinates in mappixels
  late List<List<Mappoint>> coordinatesAbsolute;

  /// cache for the boundary of the way in absolute mappixels
  MapRectangle? _boundaryAbsolute;

  /// [isClosedWay] can be passed in when the caller has already computed it
  /// (the datastore reader does, for rule matching) to avoid recomputation.
  WayProperties(this.way, PixelProjection projection, {bool? isClosedWay})
    : layer = max(0, way.layer),
      isClosedWay = isClosedWay ?? LatLongUtils.isClosedWay(way.latLongs[0]) {
    _calculateCoordinatesAbsolute(projection);
  }

  List<List<Mappoint>> getCoordinatesAbsolute() {
    return coordinatesAbsolute;
  }

  List<List<Mappoint>> _calculateCoordinatesAbsolute(PixelProjection projection) {
    coordinatesAbsolute = [];
    final List<List<ILatLong>> rings = way.latLongs;
    for (int idx = 0; idx < rings.length; idx++) {
      final List<ILatLong> ring = rings[idx];
      final int length = ring.length;
      if (length == 0) {
        if (idx == 0) _boundaryAbsolute = const MapRectangle.zero();
        continue;
      }
      // Single pass: project each point and fold the bbox in the same loop.
      // The previous closure-based map().toList() + MapRectangle.from()
      // iterated everything twice and was a top CPU cost of tile production.
      List<Mappoint> mp1 = List<Mappoint>.filled(length, const Mappoint(0, 0), growable: false);
      double minX = double.maxFinite, minY = double.maxFinite;
      double maxX = -1, maxY = -1;
      for (int i = 0; i < length; i++) {
        final ILatLong position = ring[i];
        final double x = projection.longitudeToPixelX(position.longitude);
        final double y = projection.latitudeToPixelY(position.latitude);
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        mp1[i] = Mappoint(x, y);
      }
      final MapRectangle minMaxMappoint = MapRectangle(minX, minY, maxX, maxY);
      if (idx == 0) _boundaryAbsolute = minMaxMappoint;
      if (minMaxMappoint.getWidth() > maxGap || minMaxMappoint.getHeight() > maxGap) {
        if (mp1.length > 6) mp1 = DouglasPeuckerMappoint().simplify(mp1, maxGap);
        // check if the area to draw is too small. This saves 100ms for complex structures
        coordinatesAbsolute.add(mp1);
      }
    }
    return coordinatesAbsolute;
  }

  Mappoint getCenterAbsolute(PixelProjection projection) {
    if (center != null) return center!;

    if (way.labelPosition != null) {
      center = projection.latLonToPixel(way.labelPosition!);
    }
    return _boundaryAbsolute!.getCenter();
  }

  int getLayer() {
    return layer;
  }

  TagCollection getTags() {
    return way.tags;
  }

  MapRectangle getBoundaryAbsolute() {
    if (_boundaryAbsolute != null) return _boundaryAbsolute!;
    List<List<Mappoint>> coordinates = getCoordinatesAbsolute();
    if (coordinates.isEmpty) return const MapRectangle.zero();
    if (_boundaryAbsolute != null) return _boundaryAbsolute!;
    _boundaryAbsolute = MapRectangle.from(coordinates[0]);
    return _boundaryAbsolute!;
  }

  /// Calculates the center of the minimum bounding rectangle for the given coordinates.
  ///
  /// @param coordinates the coordinates for which calculation should be done.
  /// @return the center coordinates of the minimum bounding rectangle.
  static Mappoint _calculateCenterOfBoundingBox(List<Mappoint> coordinates) {
    double pointXMin = coordinates[0].x;
    double pointXMax = coordinates[0].x;
    double pointYMin = coordinates[0].y;
    double pointYMax = coordinates[0].y;

    for (Mappoint immutablePoint in coordinates) {
      if (immutablePoint.x < pointXMin) {
        pointXMin = immutablePoint.x;
      } else if (immutablePoint.x > pointXMax) {
        pointXMax = immutablePoint.x;
      }

      if (immutablePoint.y < pointYMin) {
        pointYMin = immutablePoint.y;
      } else if (immutablePoint.y > pointYMax) {
        pointYMax = immutablePoint.y;
      }
    }

    return Mappoint((pointXMin + pointXMax) / 2, (pointYMax + pointYMin) / 2);
  }

  LineSegmentPath? calculateStringPath(double dy) {
    List<List<Mappoint>> coordinatesAbsolute = getCoordinatesAbsolute();

    if (coordinatesAbsolute.isEmpty || coordinatesAbsolute[0].length < 2) {
      return null;
    }
    List<Mappoint> c;
    if (dy.abs() < 2) {
      // dy is very small, use the fast method
      c = coordinatesAbsolute[0];
    } else {
      c = MapPathHelper.parallelPath(coordinatesAbsolute[0], dy);
    }

    if (c.length < 2) {
      return null;
    }

    LineSegmentPath fullPath = LineSegmentPath();
    for (int i = 1; i < c.length; i++) {
      LineSegment segment = LineSegment(c[i - 1], c[i]);
      fullPath.segments.add(segment);
    }
    return fullPath;
  }
}
