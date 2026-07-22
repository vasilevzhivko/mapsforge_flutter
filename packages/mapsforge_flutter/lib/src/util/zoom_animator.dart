import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapsforge_flutter/mapsforge.dart';

/// Google-Maps-style animated zoom for programmatic zoom changes (double-tap,
/// zoom buttons): eases the map scale — and for zoom-in also the center —
/// over ~250ms, then commits the discrete zoom level. The tile pipeline's
/// zoom underlay keeps the old tiles painted (scaled) while the new zoom
/// level renders, so the whole transition is seamless.
///
/// Owned by a State with a [TickerProvider]; call [dispose] from its dispose.
class ZoomAnimator {
  final MapModel mapModel;

  late final AnimationController _controller;

  late final Animation<double> _progress;

  void Function()? _onTick;

  void Function()? _onComplete;

  ZoomAnimator({required this.mapModel, required TickerProvider vsync, Duration duration = const Duration(milliseconds: 250)}) {
    _controller = AnimationController(vsync: vsync, duration: duration);
    _progress = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _progress.addListener(() => _onTick?.call());
    _controller.addStatusListener((AnimationStatus status) {
      if (status != AnimationStatus.completed) return;
      final void Function()? complete = _onComplete;
      _onTick = null;
      _onComplete = null;
      complete?.call();
    });
  }

  void dispose() {
    _controller.dispose();
  }

  bool get isAnimating => _controller.isAnimating;

  /// Zoom in one level, gliding the center toward ([targetLat], [targetLng])
  /// — pass the midpoint between the current center and the tapped location
  /// for the classic double-tap feel. Scale eases 1→2 while the center moves,
  /// and the end state is pixel-identical to the committed zoom: no jump.
  void animateZoomIn(double targetLat, double targetLng) {
    _finishActive();
    final MapPosition? start = mapModel.lastPosition;
    if (start == null) return;
    final double startLat = start.latitude, startLng = start.longitude;
    final int targetZoom = start.zoomlevel + 1;
    _onTick = () {
      final double p = _progress.value;
      final double lat = startLat + (targetLat - startLat) * p;
      final double lng = startLng + (targetLng - startLng) * p;
      mapModel.setPosition(mapModel.lastPosition!.moveTo(lat, lng).scaleAround(null, 1 + p));
    };
    _onComplete = () => mapModel.zoomToAround(targetLat, targetLng, targetZoom);
    unawaited(_controller.forward(from: 0));
  }

  /// Zoom in one level around the current center (the "+" button).
  void animateZoomInCentered() {
    final MapPosition? start = mapModel.lastPosition;
    if (start == null) return;
    animateZoomIn(start.latitude, start.longitude);
  }

  /// Zoom out one level around the current center. The zoom level is
  /// committed IMMEDIATELY at double scale — visually identical to the state
  /// before — then the scale eases 2→1 while the newly visible edges render
  /// in (covered meanwhile by the old tiles kept as underlay).
  void animateZoomOut() {
    _finishActive();
    final MapPosition? start = mapModel.lastPosition;
    if (start == null || start.zoomlevel <= 0) return;
    mapModel.setPosition(start.zoomOut().scaleAround(null, 2));
    _onTick = () {
      mapModel.scaleAround(null, 2 - _progress.value);
    };
    _onComplete = () => mapModel.zoomTo(mapModel.lastPosition!.zoomlevel);
    unawaited(_controller.forward(from: 0));
  }

  /// Commits any in-flight animated zoom instantly so a new gesture (e.g. a
  /// rapid second double-tap) chains from the settled state.
  void _finishActive() {
    if (!_controller.isAnimating) return;
    _controller.stop();
    final void Function()? complete = _onComplete;
    _onTick = null;
    _onComplete = null;
    complete?.call();
  }
}
