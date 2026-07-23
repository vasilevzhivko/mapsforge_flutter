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

  /// Finishes a still-running release snap INSTANTLY (committing its pending
  /// zoom) so a new two-finger gesture starts from a settled state. Without
  /// this the snap's ticker kept fighting the new gesture's scaleAround and
  /// its deferred commit fired mid-gesture on top of the new gesture's zoom.
  void _finishSnap() {
    if (_snapController.isAnimating) _snapController.stop();
    final commit = _snapCommit;
    _snapCommit = null;
    commit?.call();
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
              finishSnap: _finishSnap,
            );
            // localPosition, NOT position: the focal point feeds normalize()
            // and the transform origin, which both work in this widget's own
            // coordinate space. The global position is offset by everything
            // above/around the map (app bar etc.), which skewed every
            // focal-anchored zoom commit.
            _handler!._addOffset(event.pointer, event.localPosition);
          },
          onPointerMove: (event) {
            if (doLog) _log.info("onPointerMove $event ${event.pointer}");
            _handler?._movePointer(event.pointer, event.localPosition);
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

  /// Minimum spacing between mid-gesture zoom commits. Each commit starts a
  /// full tile render for its level; a FAST pinch crossing many levels would
  /// otherwise flood the render pipeline with levels that are abandoned
  /// milliseconds later, starving the level the user actually lands on.
  /// A fast pinch thus commits at most every [_commitInterval] and the
  /// release commit covers the remaining levels in one jump.
  static const Duration _commitInterval = Duration(milliseconds: 350);

  DateTime _lastCommitAt = DateTime.fromMillisecondsSinceEpoch(0);

  final void Function({
    required double fromScale,
    required double toScale,
    required Offset focalPoint,
    required VoidCallback commit,
  }) animateSnap;

  /// Instantly completes a pending release-snap (see state._finishSnap).
  final VoidCallback finishSnap;

  final Map<int, Offset> _points = {};

  _Vector? _startVector;

  _Vector? _lastVector;

  double _lastScale = 1;

  _Handler({
    required this.lastPosition,
    required this.mapModel,
    required this.size,
    required this.animateSnap,
    required this.finishSnap,
  });

  void _addOffset(int id, Offset offset) {
    _points[id] = offset;
    if (_points.length != 2) {
      return;
    }
    // A (re)formed two-finger contact is a NEW scale baseline. Users zoom in
    // slow "ratchets" (spread, lift one finger, replant, spread again):
    // carrying the committed factor / reference position over from the
    // previous contact made every replant fire spurious commits from stale
    // state and run the zoom away. Settle any pending release-snap first,
    // then re-baseline everything.
    finishSnap();
    _startVector = _Vector(_points.values.first, _points.values.last);
    _lastVector = null;
    lastPosition = mapModel.lastPosition!;
    _committedFactor = 1;
    _lastScale = 1;
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
    // A pinch-IN often starts with the fingers almost touching: a base length
    // of a few pixels turns finger noise into huge jittery scale factors.
    // Re-anchor until the fingers are meaningfully apart.
    if (_startVector!.getLength() < 30) {
      _startVector = newVector;
      _lastVector = newVector;
      return;
    }
    double effective = newVector.getLength() / _startVector!.getLength() / _committedFactor;
    // Cap the visual stretch at the zoom bounds: past max zoom the scale
    // would keep growing with nothing left to commit, and the release commit
    // would then recentre with a factor that can never be applied.
    final int zoom = mapModel.lastPosition!.zoomlevel;
    final double maxEffective = pow(2, mapModel.zoomlevelRange.zoomlevelMax - zoom).toDouble();
    final double minEffective = pow(2, mapModel.zoomlevelRange.zoomlevelMin - zoom).toDouble();
    if (effective > maxEffective) effective = maxEffective;
    if (effective < minEffective) effective = minEffective;
    // Progressive commit (Google-Maps-style): once the pinch crosses a full
    // zoom level, commit it NOW and rebase, so fresh tiles render DURING a
    // long pinch instead of only at release — otherwise a deep pinch-out
    // just shrinks the old tiles into a dot on the background.
    // The time throttle protects the render pipeline from fast pinches, but
    // is BYPASSED once the gesture runs 2+ levels past the last commit:
    // unlike a pinch-out (physically bounded at ~1/4), a pinch-in from
    // nearly-touching fingers can reach 20-30x — without the bypass the view
    // magnifies into a giant blur while waiting for the throttle.
    final bool crossed = effective >= 2.0 || effective <= 0.5;
    final bool farCrossed = effective >= 4.0 || effective <= 0.25;
    if (crossed && (farCrossed || DateTime.now().difference(_lastCommitAt) >= _commitInterval)) {
      final int zoomLevelDiff = (log(effective) / log(2)).truncate();
      final int achieved = _commitZoomStep(zoomLevelDiff, newVector.getFocalPoint());
      if (achieved != 0) {
        _committedFactor *= pow(2, achieved);
        effective = newVector.getLength() / _startVector!.getLength() / _committedFactor;
        _lastCommitAt = DateTime.now();
      }
    }
    _lastScale = effective;
    mapModel.scaleAround(newVector.getFocalPoint(), effective);
    _lastVector = newVector;
  }

  /// Commits [zoomLevelDiff] levels around [focalPoint] mid-gesture, exactly
  /// like the release commit. Returns the zoom delta actually achieved.
  int _commitZoomStep(int zoomLevelDiff, Offset focalPoint) {
    final int before = mapModel.lastPosition!.zoomlevel;
    // Clamp to the model's zoom bounds FIRST. Calling zoomToAround past the
    // bounds clamps the zoom but still applies the recentering — at max zoom
    // that recentred the map over and over (once per retry) while never
    // zooming, walking the view away under the user's fingers.
    final int achievable = mapModel.zoomlevelRange.ensureBounds(before + zoomLevelDiff) - before;
    if (achievable == 0) return 0;
    final num mult = pow(2, achievable);
    final PositionInfo positionInfo = RotateHelper.normalize(lastPosition, size, focalPoint.dx, focalPoint.dy);
    mapModel.zoomToAround(
      positionInfo.latitude + (mapModel.lastPosition!.latitude - positionInfo.latitude) / mult,
      positionInfo.longitude + (mapModel.lastPosition!.longitude - positionInfo.longitude) / mult,
      before + achievable,
    );
    lastPosition = mapModel.lastPosition!;
    return lastPosition.zoomlevel - before;
  }

  void _sendEnd() {
    // no zoom: 0, double zoom: 1, half zoom: -1
    double zoomLevelOffset = log(_lastScale) / log(2);
    int zoomLevelDiff = zoomLevelOffset.round();
    // Same clamp as _commitZoomStep: never recentre for zoom levels the
    // model's bounds won't actually apply.
    final int beforeZoom = mapModel.lastPosition!.zoomlevel;
    zoomLevelDiff = mapModel.zoomlevelRange.ensureBounds(beforeZoom + zoomLevelDiff) - beforeZoom;

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
