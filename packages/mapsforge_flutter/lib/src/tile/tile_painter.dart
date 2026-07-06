import 'package:flutter/cupertino.dart';
import 'package:mapsforge_flutter/src/tile/tile_job_queue.dart';
import 'package:mapsforge_flutter/src/tile/tile_set.dart';
import 'package:mapsforge_flutter_core/model.dart';
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
