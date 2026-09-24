import 'package:flutter/cupertino.dart';
import 'package:mapsforge_flutter/src/label/label_job_queue.dart';
import 'package:mapsforge_flutter/src/label/label_set.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_renderer/ui.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';

class LabelPainter extends CustomPainter {
  final LabelJobQueue labelJobQueue;

  LabelPainter(this.labelJobQueue) : super(repaint: labelJobQueue);

  @override
  void paint(Canvas canvas, Size size) {
    UiCanvas uiCanvas = UiCanvas(canvas, size);
    LabelSet labelSet = labelJobQueue.labelSet;
    Mappoint center = labelSet.getCenter();
    PixelProjection projection = labelSet.mapPosition.projection;
    UiRenderContext renderContext = UiRenderContext(
      canvas: uiCanvas,
      reference: center,
      projection: projection,
      rotationRadian: labelSet.mapPosition.rotationRadian,
      // So point symbols counter-scale and stay a constant on-screen size under
      // the persistent fractional-zoom residual (they were magnified up to ~2×).
      scale: labelSet.mapPosition.scale,
      // Render-theme (Elevate) POI symbols read a touch smaller than the raw
      // theme size. App markers use their own painters (factor stays 1.0). Tune.
      symbolSizeFactor: 0.8,
    );
    for (RenderInfoCollection renderInfoCollection in labelSet.renderInfos) {
      for (var renderInfo in renderInfoCollection.renderInfos) {
        renderInfo.render(renderContext);
      }
    }
  }

  @override
  bool shouldRepaint(covariant LabelPainter oldDelegate) {
    if (oldDelegate.labelJobQueue.labelSet != labelJobQueue.labelSet) return true;
    return false;
  }
}
