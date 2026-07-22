import 'package:flutter/cupertino.dart';
import 'package:mapsforge_flutter/src/tile/tile_job_queue.dart';
import 'package:mapsforge_flutter/src/tile/tile_set.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';

class TilePainter extends CustomPainter {
  final TileJobQueue jobQueue;

  /// Opacity applied to every tile this painter draws (0.0–1.0). 1.0 = opaque.
  final double opacity;

  TilePainter(this.jobQueue, {this.opacity = 1.0}) : super(repaint: jobQueue);

  @override
  void paint(Canvas canvas, Size size) {
    // tileSet is null while the first job is pending (no previous job to show)
    final TileSet? tileSet = jobQueue.tileSet;
    if (tileSet == null) return;
    UiCanvas uiCanvas = UiCanvas(canvas, size);

    // Fill the viewport with the theme's map background first, so areas no
    // tile (current or underlay) covers — e.g. after a multi-level zoom jump —
    // read as empty land instead of holes. Coordinates are map pixels around
    // the position center at (0,0); the 2× margin covers scale-out animations
    // and rotation.
    final int? background = jobQueue.renderer.backgroundColor;
    if (background != null) {
      final double dsf = MapsforgeSettingsMgr().getDeviceScaleFactor();
      // During a pinch-out the whole painter output is scaled DOWN by the
      // gesture transform — divide by the live scale so the fill keeps
      // covering the screen however far the fingers pinch.
      final double scale = tileSet.mapPosition.scale;
      final double inv = scale < 1 ? 1 / scale : 1.0;
      final double w = size.width * dsf * inv, h = size.height * dsf * inv;
      canvas.drawRect(Rect.fromLTRB(-w, -h, w, h), Paint()..color = Color(background));
    }

    // Zoom-change underlay: while the current set is still filling, draw the
    // previous zoom's tiles scaled to the current zoom underneath, so the
    // areas rendered last (the edges) show stretched imagery instead of
    // flickering blank. Skipped for translucent overlays — drawing them twice
    // where both sets overlap would double their opacity.
    final TileSet? previous = jobQueue.previousTileSet;
    if (previous != null && !jobQueue.renderer.transparentOnMiss) {
      final int dz = tileSet.mapPosition.zoomlevel - previous.mapPosition.zoomlevel;
      final double f = dz >= 0 ? (1 << dz).toDouble() : 1.0 / (1 << -dz);
      // Mercator pixel coordinates double per zoom level, so the current
      // center in previous-zoom space is simply center / f.
      final Mappoint currentCenter = tileSet.getCenter();
      final double cx = currentCenter.x / f, cy = currentCenter.y / f;
      canvas.save();
      canvas.scale(f);
      previous.images.forEach((Tile tile, TilePicture picture) {
        Mappoint leftUpper = tile.getLeftUpper();
        try {
          uiCanvas.drawTilePicture(picture: picture, left: leftUpper.x - cx, top: leftUpper.y - cy, opacity: opacity);
        } catch (error, stacktrace) {
          print(error);
          print(stacktrace);
          print(tile);
        }
      });
      canvas.restore();
    }

    Mappoint center = tileSet.getCenter();
    tileSet.images.forEach((Tile tile, TilePicture picture) {
      Mappoint leftUpper = tile.getLeftUpper();
      try {
        uiCanvas.drawTilePicture(picture: picture, left: leftUpper.x - center.x, top: leftUpper.y - center.y, opacity: opacity);
      } catch (error, stacktrace) {
        print(error);
        print(stacktrace);
        print(tile);
      }
    });
  }

  @override
  bool shouldRepaint(covariant TilePainter oldDelegate) {
    if (oldDelegate.jobQueue.tileSet != jobQueue.tileSet) return true;
    if (oldDelegate.opacity != opacity) return true;
    return false;
  }
}
