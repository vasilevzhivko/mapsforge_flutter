import 'dart:math';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/util/rotate_helper.dart';

/// Two‐finger rotation overlay that never blocks pan/zoom,
/// and uses ViewModel.rotateDelta() to apply each twist incrementally.
class ScaleGestureDetector extends StatefulWidget {
  final MapModel mapModel;

  /// degrees of twist before we start rotating
  final double thresholdDeg;

  const ScaleGestureDetector({super.key, required this.mapModel, this.thresholdDeg = 10.0});

  @override
  State<ScaleGestureDetector> createState() => _ScaleGestureDetectorState();
}

//////////////////////////////////////////////////////////////////////////////

class _ScaleGestureDetectorState extends State<ScaleGestureDetector> with SingleTickerProviderStateMixin {
  static final _log = Logger('_Scale2GestureDetectorState');

  final bool doLog = false;

  _Handler? _handler;

  late final AnimationController _snapController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );
  late final Animation<double> _snapProgress = CurvedAnimation(
    parent: _snapController,
    curve: Curves.easeOut,
  );

  // State for the current snap animation
  double _snapFrom = 1.0;
  double _snapTo = 1.0;
  Offset _snapFocalPoint = Offset.zero;
  VoidCallback? _snapCommit;

  @override
  void initState() {
    super.initState();
    _snapProgress.addListener(_onSnapTick);
    _snapController.addStatusListener(_onSnapStatus);
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _onSnapTick() {
    final scale = _snapFrom + (_snapTo - _snapFrom) * _snapProgress.value;
    widget.mapModel.scaleAround(_snapFocalPoint, scale);
  }

  void _onSnapStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final commit = _snapCommit;
    _snapCommit = null;
    commit?.call();
  }

  void _animateSnapAndCommit({
    required double fromScale,
    required double toScale,
    required Offset focalPoint,
    required VoidCallback commit,
  }) {
    _snapFrom = fromScale;
    _snapTo = toScale;
    _snapFocalPoint = focalPoint;
    _snapCommit = commit;
    _snapController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            if (doLog) _log.info("onPointerDown $event ${event.pointer}");
            if (widget.mapModel.lastPosition == null) return;
            _handler ??= _Handler(
              size: constraints.biggest,
              lastPosition: widget.mapModel.lastPosition!,
              mapModel: widget.mapModel,
              animateSnap: _animateSnapAndCommit,
            );
            _handler!._addOffset(event.pointer, event.position);
          },
          onPointerMove: (event) {
            if (doLog) _log.info("onPointerMove $event ${event.pointer}");
            _handler?._movePointer(event.pointer, event.position);
          },
          onPointerUp: (event) {
            if (doLog) _log.info("onPointerUp $event ${event.pointer}");
            bool cancel = _handler?._removeOffset(event.pointer) ?? false;
            if (cancel) _handler = null;
          },
          onPointerCancel: (event) {
            if (doLog) _log.info("onPointerCancel $event ${event.pointer}");
            _handler?._cancel();
            _handler = null;
          },
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

//////////////////////////////////////////////////////////////////////////////

class _Handler {
  /// Gesture-start position; rebased after every mid-gesture zoom commit.
  MapPosition lastPosition;

  final MapModel mapModel;

  final Size size;

  /// Scale already committed as zoom-level changes during this gesture
  /// (powers of 2). The displayed scale is the raw pinch scale divided by
  /// this, so the view stays continuous across mid-gesture commits.
  double _committedFactor = 1;

  final void Function({
    required double fromScale,
    required double toScale,
    required Offset focalPoint,
    required VoidCallback commit,
  }) animateSnap;

  final Map<int, Offset> _points = {};

  _Vector? _startVector;

  _Vector? _lastVector;

  double _lastScale = 1;

  _Handler({
    required this.lastPosition,
    required this.mapModel,
    required this.size,
    required this.animateSnap,
  });

  void _addOffset(int id, Offset offset) {
    _points[id] = offset;
    if (_points.length != 2) {
      return;
    }
    _startVector = _Vector(_points.values.first, _points.values.last);
  }

  bool _removeOffset(int id) {
    _points.remove(id);
    if (_points.length == 1) {
      if (_startVector != null) _sendEnd();
    }
    if (_points.isEmpty) return true;
    return false;
  }

  void _cancel() {
    _points.clear();
    if (_startVector != null) _sendEnd();
  }

  void _movePointer(int id, Offset offset) {
    if (!_points.containsKey(id)) {
      return;
    }
    _points[id] = offset;
    if (_points.length != 2) {
      return;
    }
    _Vector newVector = _Vector(_points.values.first, _points.values.last);
    if (newVector.getLength().isNaN) return;
    double effective = newVector.getLength() / _startVector!.getLength() / _committedFactor;
    // Progressive commit (Google-Maps-style): once the pinch crosses a full
    // zoom level, commit it NOW and rebase, so fresh tiles render DURING a
    // long pinch instead of only at release — otherwise a deep pinch-out
    // just shrinks the old tiles into a dot on the background.
    if (effective >= 2.0 || effective <= 0.5) {
      final int zoomLevelDiff = (log(effective) / log(2)).truncate();
      final int achieved = _commitZoomStep(zoomLevelDiff, newVector.getFocalPoint());
      if (achieved != 0) {
        _committedFactor *= pow(2, achieved);
        effective = newVector.getLength() / _startVector!.getLength() / _committedFactor;
      }
    }
    _lastScale = effective;
    mapModel.scaleAround(newVector.getFocalPoint(), effective);
    _lastVector = newVector;
  }

  /// Commits [zoomLevelDiff] levels around [focalPoint] mid-gesture, exactly
  /// like the release commit. Returns the zoom delta actually achieved (the
  /// model may clamp at its zoom bounds).
  int _commitZoomStep(int zoomLevelDiff, Offset focalPoint) {
    final num mult = pow(2, zoomLevelDiff);
    final PositionInfo positionInfo = RotateHelper.normalize(lastPosition, size, focalPoint.dx, focalPoint.dy);
    final int before = mapModel.lastPosition!.zoomlevel;
    mapModel.zoomToAround(
      positionInfo.latitude + (mapModel.lastPosition!.latitude - positionInfo.latitude) / mult,
      positionInfo.longitude + (mapModel.lastPosition!.longitude - positionInfo.longitude) / mult,
      before + zoomLevelDiff,
    );
    lastPosition = mapModel.lastPosition!;
    return lastPosition.zoomlevel - before;
  }

  void _sendEnd() {
    // no zoom: 0, double zoom: 1, half zoom: -1
    double zoomLevelOffset = log(_lastScale) / log(2);
    int zoomLevelDiff = zoomLevelOffset.round();

    // Fall back to screen centre if we never got a move event with 2 fingers
    final focalPoint = _lastVector?.getFocalPoint() ?? Offset(size.width / 2, size.height / 2);

    if (zoomLevelDiff != 0) {
      num mult = pow(2, zoomLevelDiff);
      double targetScale = pow(2, zoomLevelDiff).toDouble();
      PositionInfo positionInfo = RotateHelper.normalize(lastPosition, size, focalPoint.dx, focalPoint.dy);

      animateSnap(
        fromScale: _lastScale,
        toScale: targetScale,
        focalPoint: focalPoint,
        commit: () {
          mapModel.zoomToAround(
            positionInfo.latitude + (mapModel.lastPosition!.latitude - positionInfo.latitude) / mult,
            positionInfo.longitude + (mapModel.lastPosition!.longitude - positionInfo.longitude) / mult,
            mapModel.lastPosition!.zoomlevel + zoomLevelDiff,
          );
        },
      );
    } else if (_lastScale != 1) {
      // No significant zoom — animate back to original scale then restore zoom level
      animateSnap(
        fromScale: _lastScale,
        toScale: 1.0,
        focalPoint: focalPoint,
        commit: () {
          mapModel.zoomTo(mapModel.lastPosition!.zoomlevel);
        },
      );
    }
  }
}

//////////////////////////////////////////////////////////////////////////////

class _Vector {
  final Offset start;

  final Offset end;

  double? _length;

  Offset? _focalPoint;

  _Vector(this.start, this.end);

  double getLength() {
    if (_length != null) return _length!;
    _length = sqrt((end.dx - start.dx) * (end.dx - start.dx) + (end.dy - start.dy) * (end.dy - start.dy));
    return _length!;
  }

  Offset getFocalPoint() {
    if (_focalPoint != null) return _focalPoint!;
    _focalPoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    return _focalPoint!;
  }

  @override
  String toString() {
    return '_Vector{_length: $_length, _focalPoint: $_focalPoint}';
  }
}
