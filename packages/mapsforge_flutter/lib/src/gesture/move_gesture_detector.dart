import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:logging/logging.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/utils.dart';

/// Moves the map around by calling mapModel.setCenter() whenever the user drags the map. Flinging is also supported.
class MoveGestureDetector extends StatefulWidget {
  final MapModel mapModel;

  /// The absorption factor of a swipe. The lower the factor the faster swiping
  /// stops.
  final double swipeAbsorption;

  const MoveGestureDetector({super.key, required this.mapModel, this.swipeAbsorption = 0.9}) : assert(swipeAbsorption >= 0 && swipeAbsorption <= 1);

  @override
  State<MoveGestureDetector> createState() => _MoveGestureDetectorState();
}

//////////////////////////////////////////////////////////////////////////////

class _MoveGestureDetectorState extends State<MoveGestureDetector> {
  static final _log = Logger('_MoveGestureDetectorState');

  final bool doLog = false;

  _MoveEvent? _eventHandler;

  @override
  void dispose() {
    _eventHandler?.dispose();
    super.dispose();
  }

  // short click:
  // onTapDown
  // onTapUp
  //
  // long click:
  // onTapDown
  // onTapUp
  //
  // doubletap:
  // onDoubleTapDown
  // onTapDown
  // onDoubleTap
  //
  // normal drag event:
  // optionally (if the user waits a bit): onTapDown
  // onScaleStart with pointerCount 1
  // several onScaleUpdate with scale 1.0, rotation 0.0 and pointerCount: 1
  // onScaleEnd with velocity 0/0 and pointerCount: 0
  // NO onTapUp!
  //
  // zoom-in event:
  // optionally (if the user waits a bit): onTapDown
  // onScaleStart with pointerCount 2
  // several onScaleUpdate scale > 1, rotation normally != 0 and pointerCount: 2
  // onScaleEnd with velocity 0/0 and pointerCount: 1
  //
  // swipe: (similar to normal drag event)
  // optionally (if the user waits a bit): onTapDown
  // onScaleStart with pointerCount 1
  // several onScaleUpdate with scale 1.0, rotation 0.0 and pointerCount: 1
  // onScaleEnd with velocity -2324/-2699, pointerCount 0
  // velocity is in pixels per second
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: (ScaleStartDetails details) {
        if (doLog) _log.info("onScaleStart $details");
        MapPosition? lastPosition = widget.mapModel.lastPosition;
        if (details.pointerCount == 1 && lastPosition != null) {
          _eventHandler ??= _MoveEvent(
            mapModel: widget.mapModel,
            swipeAbsorption: widget.swipeAbsorption,
            startLocalFocalPoint: details.localFocalPoint,
          );
        }
      },
      onScaleUpdate: (ScaleUpdateDetails details) {
        if (doLog) _log.info("onScaleUpdate $details");
        _eventHandler?.update(details: details);
      },
      onScaleEnd: (ScaleEndDetails details) {
        if (doLog) _log.info("onScaleEnd $details");
        bool? disposeAllowed = _eventHandler?.end(details: details);
        if (disposeAllowed ?? false) _eventHandler?.dispose();
        _eventHandler = null;
      },
      child: const SizedBox.expand(),
    );
  }
}

/////////////////////////////////////////////////////////////////////////////

class _MoveEvent {
  /// Minimum pixels per second (squared) to activate flinging
  final double _swipeThresholdSquared = 20000;

  final int _swipeSleepMs = 33; // milliseconds between swipes

  final MapModel mapModel;

  final Offset startLocalFocalPoint;


  Timer? _startTimer;

  Timer? _swipeTimer;

  Offset? _swipeOffset;

  /// The absorption factor of a swipe. The lower the factor the faster swiping
  /// stops.
  final double swipeAbsorption;

  Offset? _updateLocalFocalPoint;

  int _nextManualMoveEvent = 0;

  _MoveEvent({
    required this.mapModel,
    required this.swipeAbsorption,
    required this.startLocalFocalPoint,
    int longPressDuration = 350,
  }) {
    _startTimer = Timer(Duration(milliseconds: longPressDuration), () {});
  }

  void dispose() {
    _swipeTimer?.cancel();
    _swipeTimer = null;
    _startTimer?.cancel();
    _startTimer = null;
    _swipeOffset = null;
  }

  void update({required ScaleUpdateDetails details}) {
    // Move INCREMENTALLY from the model's current position, by the finger's
    // delta since the previous update. The old form kept the centre captured
    // at finger-down in absolute map pixels and re-applied it on every update
    // (setCenter(startCenter - totalDelta)). Absolute pixels only mean
    // something at the zoom they were taken at: when anything else changed the
    // position mid-drag (the app's "centre on my location" at z18 arriving
    // while the user was still panning at z17), the next update pushed z17
    // pixels into a z18 world — half the coordinates — which threw the map to
    // the far north-west, i.e. onto the bounding-box corner / into the sea.
    final Offset previous = _updateLocalFocalPoint ?? startLocalFocalPoint;
    _updateLocalFocalPoint = details.localFocalPoint;
    double diffX = (details.localFocalPoint.dx - previous.dx) * MapsforgeSettingsMgr().getDeviceScaleFactor();
    double diffY = (details.localFocalPoint.dy - previous.dy) * MapsforgeSettingsMgr().getDeviceScaleFactor();
    if (diffX == 0 && diffY == 0) return;
    if (mapModel.lastPosition?.rotation != 0) {
      double hyp = sqrt(diffX * diffX + diffY * diffY);
      double rad = atan2(diffY, diffX);
      double rot = mapModel.lastPosition!.rotationRadian;
      diffX = cos(-rot + rad) * hyp;
      diffY = sin(-rot + rad) * hyp;
    }
    if (_nextManualMoveEvent == 0 || _nextManualMoveEvent < DateTime.now().millisecondsSinceEpoch) {
      _nextManualMoveEvent = DateTime.now().millisecondsSinceEpoch + 1000;
      mapModel.manualMove(Object());
    }
    mapModel.moveCenter(-diffX, -diffY);
  }

  bool end({required ScaleEndDetails details}) {
    if (details.velocity.pixelsPerSecond.distanceSquared < _swipeThresholdSquared) {
      return true;
    }
    if (_updateLocalFocalPoint != null) {
      // check the direction of velocity. If velocity points to wrong direction do not swipe
      if (details.velocity.pixelsPerSecond.dx.abs() > details.velocity.pixelsPerSecond.dy.abs() &&
          (_updateLocalFocalPoint!.dx - startLocalFocalPoint.dx).sign != details.velocity.pixelsPerSecond.dx.sign) {
        return true;
      }
      if (details.velocity.pixelsPerSecond.dx.abs() < details.velocity.pixelsPerSecond.dy.abs() &&
          (_updateLocalFocalPoint!.dy - startLocalFocalPoint.dy).sign != details.velocity.pixelsPerSecond.dy.sign) {
        return true;
      }
    }
    // calculate the offset per iteration
    _swipeOffset = details.velocity.pixelsPerSecond / 1000 * _swipeSleepMs.toDouble();
    if (mapModel.lastPosition?.rotation != 0) {
      double hyp = sqrt(_swipeOffset!.dx * _swipeOffset!.dx + _swipeOffset!.dy * _swipeOffset!.dy);
      double rad = atan2(_swipeOffset!.dy, _swipeOffset!.dx);
      double rot = mapModel.lastPosition!.rotationRadian;
      _swipeOffset = Offset(cos(-rot + rad) * hyp, sin(-rot + rad) * hyp);
      // print(
      //     "diff: $diffX/$diffY @ ${widget.viewModel.mapViewPosition!.rotation}($rad) from ${(details.localFocalPoint.dx - _startLocalFocalPoint!.dx) * widget.viewModel.viewScaleFactor}/${(details.localFocalPoint.dy - _startLocalFocalPoint!.dy) * widget.viewModel.viewScaleFactor}");
    }
    // if there is still a timer running, stop it now
    _swipeTimer?.cancel();
    _swipeTimer = Timer.periodic(Duration(milliseconds: _swipeSleepMs), (timer) {
      _swipeTimerProcess();
    });
    return false;
  }

  void _swipeTimerProcess() {
    // if (!mounted || _swipeOffset == null) {
    //   // we should stop swiping
    //   _swipeTimer?.cancel();
    //   _swipeTimer = null;
    //   _swipeOffset = null;
    //   return;
    // }
    //if (doLog) _log.info("Swiping ${_swipeOffset!.distance}");
    Mappoint? center = mapModel.lastPosition?.getCenter();
    if (center != null) {
      if (_nextManualMoveEvent == 0 || _nextManualMoveEvent < DateTime.now().millisecondsSinceEpoch) {
        _nextManualMoveEvent = DateTime.now().millisecondsSinceEpoch + 1000;
        mapModel.manualMove(Object());
      }
      mapModel.setCenter(center.x - _swipeOffset!.dx, center.y - _swipeOffset!.dy);
    }
    // slow down after each iteration
    _swipeOffset = _swipeOffset! * swipeAbsorption;
    if (_swipeOffset!.distanceSquared < 5) {
      // only 2 pixels for the next iteration, now lets stop swiping
      _swipeTimer?.cancel();
      _swipeTimer = null;
      _swipeOffset = null;
    }
  }
}
