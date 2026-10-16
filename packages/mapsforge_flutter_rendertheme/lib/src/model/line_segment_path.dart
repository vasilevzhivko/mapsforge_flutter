import 'dart:math';

import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_rendertheme/src/model/line_segment.dart';

/// A list of Linesegments which consists of segments in screen-pixels.
class LineSegmentPath {
  final List<LineSegment> segments = [];

  MapRectangle? _bounds;

  /// Creates a new LineString that consists of only the part between startDistance and endDistance.
  LineSegmentPath extractPart(double startDistance, double endDistance) {
    LineSegmentPath result = LineSegmentPath();

    for (int i = 0; i < segments.length; startDistance -= segments.elementAt(i).length(), endDistance -= segments.elementAt(i).length(), i++) {
      LineSegment segment = segments.elementAt(i);

      // Skip first segments that we don't need
      double length = segment.length();
      if (length < startDistance) {
        continue;
      }

      Mappoint? startPoint, endPoint;
      if (startDistance >= 0) {
        // This will be our starting point
        startPoint = segment.pointAlongLineSegment(startDistance);
      }
      if (endDistance < length) {
        // this will be our ending point
        endPoint = segment.pointAlongLineSegment(endDistance);
      }

      if (startPoint != null && endPoint == null) {
        // This ist the starting segment, end will come in a later segment
        result.segments.add(LineSegment(startPoint, segment.end));
      } else if (startPoint == null && endPoint == null) {
        // Center segment between start and end segment, add completely
        result.segments.add(segment);
      } else if (startPoint == null && endPoint != null) {
        // End segment, start was in earlier segment
        result.segments.add(LineSegment(segment.start, endPoint));
      } else if (startPoint != null && endPoint != null) {
        // Start and end on same segment
        result.segments.add(LineSegment(startPoint, endPoint));
      }

      if (endPoint != null) break;
    }

    return result;
  }

  MapRectangle getBounds() {
    if (_bounds != null) return _bounds!;

    double minX = double.maxFinite;
    double minY = double.maxFinite;
    double maxX = double.minPositive;
    double maxY = double.minPositive;

    for (LineSegment segment in segments) {
      minX = min(minX, min(segment.start.x, segment.end.x));
      minY = min(minY, min(segment.start.y, segment.end.y));
      maxX = max(maxX, max(segment.start.x, segment.end.x));
      maxY = max(maxY, max(segment.start.y, segment.end.y));
    }
    _bounds = MapRectangle(minX, minY, maxX, maxY);
    return _bounds!;
  }

  /// Interpolates on the segment and returns the coordinate of the interpolation result.
  /// Returns null if distance is < 0 or > length().
  Mappoint? interpolate(double distance) {
    if (distance < 0) {
      return null;
    }

    for (LineSegment segment in segments) {
      double length = segment.length();
      if (distance <= length) {
        return segment.pointAlongLineSegment(distance);
      }
      distance -= length;
    }
    return null;
  }

  double length() {
    double result = 0;
    for (LineSegment segment in segments) {
      result += segment.length();
    }
    return result;
  }

  /// Largest direction change (degrees) between two consecutive segments that
  /// still counts as "the same stretch" for placing a label along it. Text is
  /// drawn glyph by glyph along the stretch (see [textPaths]), so moderate
  /// bends read fine; sharper corners split the path into separate stretches.
  /// (mapsforge-java uses 45.)
  static final double MAX_LABEL_CORNER_ANGLE = 35;

  /// A stretch may bend in total by at most this much (degrees) before it is
  /// cut, so glyphs never end up upside down relative to the first glyph.
  static final double MAX_LABEL_TOTAL_TURN = 80;

  /// Direction change in degrees (0..180) from [a] to [b], travelling along them.
  static double turnAngle(LineSegment a, LineSegment b) {
    double diff = (b.getAngle() - a.getAngle()).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  /// Splits this path into gently curving stretches: consecutive segments whose
  /// direction changes by less than [MAX_LABEL_CORNER_ANGLE] per vertex and
  /// [MAX_LABEL_TOTAL_TURN] in total. Zero-length segments are dropped; very
  /// short ones (< 2px, digitising noise) join a stretch without an angle test.
  List<LineSegmentPath> straightishRuns() {
    final List<LineSegmentPath> runs = [];
    LineSegmentPath current = LineSegmentPath();
    LineSegment? lastSignificant;
    LineSegment? firstOfRun;
    for (LineSegment segment in segments) {
      if (segment.length() <= 0) continue;
      bool tiny = segment.length() < 2;
      if (!tiny && lastSignificant != null && firstOfRun != null) {
        if (turnAngle(lastSignificant, segment) >= MAX_LABEL_CORNER_ANGLE || turnAngle(firstOfRun, segment) >= MAX_LABEL_TOTAL_TURN) {
          if (current.segments.isNotEmpty) runs.add(current);
          current = LineSegmentPath();
          firstOfRun = null;
        }
      }
      current.segments.add(segment);
      if (!tiny) {
        lastSignificant = segment;
        firstOfRun ??= segment;
      }
    }
    if (current.segments.isNotEmpty) runs.add(current);
    return runs;
  }

  /// Where to draw a label of [textWidth] pixels along this path: each
  /// returned sub-path is exactly one label long (except in the fallback
  /// below) and lies on a stretch that is straight enough to letter along.
  /// Labels start [repeatStart] in from a stretch's ends and repeat every
  /// [repeatGap] while [repeat] is set; the group is centred on the stretch.
  ///
  /// Fallback: if no stretch is long enough but the longest one covers at
  /// least 2/3 of the label, that whole stretch is returned so the caller can
  /// letter beyond its ends (see [pointAt]) — a river crossing one tile would
  /// otherwise never be named.
  List<LineSegmentPath> textPaths(double textWidth, double repeatStart, double repeatGap, {bool repeat = true}) {
    if (textWidth <= 0) return const [];
    final List<LineSegmentPath> result = [];
    LineSegmentPath? longest;
    for (LineSegmentPath run in straightishRuns()) {
      double runLength = run.length();
      if (longest == null || longest.length() < runLength) longest = run;
      double edge = min(repeatStart, max(0, (runLength - textWidth) / 2));
      double usable = runLength - 2 * edge;
      if (usable < textWidth) continue;
      int count = repeat ? max(1, ((usable + repeatGap) / (textWidth + repeatGap)).floor()) : 1;
      double total = count * textWidth + (count - 1) * repeatGap;
      double offset = (runLength - total) / 2;
      for (int i = 0; i < count; i++) {
        double start = offset + i * (textWidth + repeatGap);
        result.add(run.extractPart(start, start + textWidth));
      }
      if (!repeat && result.isNotEmpty) break;
    }
    if (result.isEmpty && longest != null && longest.length() >= textWidth * 2 / 3) {
      result.add(longest);
    }
    return result;
  }

  /// Straight chords of [textPaths], for callers that draw the whole label as
  /// one rotated string instead of lettering along the curve.
  LineSegmentPath reducePathForText(double textWidth, double repeatStart, double repeatGap) {
    LineSegmentPath result = LineSegmentPath();
    for (LineSegmentPath path in textPaths(textWidth, repeatStart, repeatGap)) {
      if (path.first != path.last) result.segments.add(LineSegment(path.first, path.last));
    }
    return result;
  }

  Mappoint get first => segments.first.start;

  Mappoint get last => segments.last.end;

  /// Same path travelled the other way (so text reads left to right).
  LineSegmentPath reversed() {
    LineSegmentPath result = LineSegmentPath();
    for (LineSegment segment in segments.reversed) {
      result.segments.add(LineSegment(segment.end, segment.start));
    }
    return result;
  }

  /// The point [distance] pixels along the path. Unlike [interpolate] this
  /// extrapolates along the first/last segment when the distance falls before
  /// the start or beyond the end, so text may overhang a short stretch.
  Mappoint pointAt(double distance) {
    if (segments.isEmpty) return Mappoint(0, 0);
    if (distance < 0) return _extrapolate(segments.first, 0, distance);
    double remaining = distance;
    for (LineSegment segment in segments) {
      double length = segment.length();
      if (remaining <= length) return segment.pointAlongLineSegment(remaining);
      remaining -= length;
    }
    LineSegment lastSegment = segments.last;
    return _extrapolate(lastSegment, lastSegment.length(), lastSegment.length() + remaining);
  }

  Mappoint _extrapolate(LineSegment segment, double from, double to) {
    double length = segment.length();
    if (length <= 0) return segment.start;
    double fraction = (to - from) / length;
    double dx = (segment.end.x - segment.start.x) * fraction;
    double dy = (segment.end.y - segment.start.y) * fraction;
    Mappoint base = from == 0 ? segment.start : segment.end;
    return Mappoint(base.x + dx, base.y + dy);
  }

  /// Travel direction (radians, atan2 convention) of the segment that contains
  /// [distance]; clamped to the first/last segment outside the path.
  double directionAt(double distance) {
    if (segments.isEmpty) return 0;
    double remaining = distance;
    for (LineSegment segment in segments) {
      double length = segment.length();
      if (remaining <= length) return atan2(segment.end.y - segment.start.y, segment.end.x - segment.start.x);
      remaining -= length;
    }
    LineSegment lastSegment = segments.last;
    return atan2(lastSegment.end.y - lastSegment.start.y, lastSegment.end.x - lastSegment.start.x);
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is LineSegmentPath && runtimeType == other.runtimeType && segments == other.segments;

  @override
  int get hashCode => segments.hashCode;
}
