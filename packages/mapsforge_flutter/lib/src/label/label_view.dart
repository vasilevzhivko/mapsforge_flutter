import 'package:flutter/material.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/label/label_job_queue.dart';
import 'package:mapsforge_flutter/src/label/label_painter.dart';
import 'package:mapsforge_flutter/src/transform_widget.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';

/// A view to display the labels. The view updates itself whenever the [MapPosition] changes and new labels are available.
/// Labels are drawn separately so they keep orientation.
///
/// Set [minLabelZoom] to hide labels below a given zoom. If null, suppression is disabled.
class LabelView extends StatefulWidget {
  final MapModel mapModel;

  final Renderer renderer;

  /// Hide labels when zoomlevel < minLabelZoom. Null = feature disabled.
  final int? minLabelZoom;

  const LabelView({
    super.key,
    required this.mapModel,
    required this.renderer,
    this.minLabelZoom, // e.g. pass 10 to suppress under zoom 10
  });

  @override
  State<LabelView> createState() => _LabelViewState();
}

//////////////////////////////////////////////////////////////////////////////

class _LabelViewState extends State<LabelView> {
  late final LabelJobQueue jobQueue;

  @override
  void initState() {
    super.initState();
    jobQueue = LabelJobQueue(mapModel: widget.mapModel, renderer: widget.renderer);
  }

  @override
  void dispose() {
    jobQueue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double scale = MapsforgeSettingsMgr().getDeviceScaleFactor();

        jobQueue.setSize(constraints.maxWidth * scale, constraints.maxHeight * scale);
        // use notifier instead of stream because it should be faster.
        // Also listen to the jobQueue: when new labels arrive without a
        // position change, the translation below must be recomputed for the
        // freshly anchored raster.
        return ListenableBuilder(
          listenable: Listenable.merge([widget.mapModel, jobQueue]),
          builder: (BuildContext context, Widget? child) {
            MapPosition? position = widget.mapModel.lastPosition;
            if (position == null) {
              return const SizedBox();
            }
            if (widget.minLabelZoom != null && widget.minLabelZoom! >= position.zoomlevel) {
              return const SizedBox();
            }
            jobQueue.setPosition(position);
            // Pan = translate the CACHED label raster (see the RepaintBoundary
            // below) by the delta between the anchor the labels were painted
            // against and the current center — instead of repainting hundreds
            // of paragraphs per frame, the label layer's dominant cost in
            // dense city areas. The painter only repaints when the content,
            // rotation or pinch scale actually changes.
            Widget content = child!;
            final Mappoint? anchor = jobQueue.currentLabelCenter;
            if (anchor != null) {
              final Mappoint current = position.getCenter();
              final double dx = anchor.x - current.x, dy = anchor.y - current.y;
              if (dx != 0 || dy != 0) {
                content = Transform.translate(offset: Offset(dx, dy), child: content);
              }
            }
            return TransformWidget(
              mapCenter: position.getCenter(),
              mapPosition: position,
              screensize: Size(constraints.maxWidth, constraints.maxHeight),
              child: content,
            );
          },
          child: RepaintBoundary(child: CustomPaint(foregroundPainter: LabelPainter(jobQueue), child: const SizedBox.expand())),
        );
      },
    );
  }
}
