import 'package:flutter/material.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/tile/tile_job_queue.dart';
import 'package:mapsforge_flutter/src/tile/tile_painter.dart';
import 'package:mapsforge_flutter/src/transform_widget.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';

/// A view to display the tiles. The view updates itself whenever the [MapPosition] changes and new tiles are available.
class TileView extends StatefulWidget {
  final MapModel mapModel;

  final Renderer renderer;

  /// Paint opacity for this renderer's tiles, 0.0–1.0. Used to blend a custom
  /// overlay/base source over the layers below. Defaults to 1.0 (fully opaque),
  /// which keeps the vector base byte-identical.
  final double opacity;

  const TileView({super.key, required this.mapModel, required this.renderer, this.opacity = 1.0});

  @override
  State<TileView> createState() => _TileViewState();
}

//////////////////////////////////////////////////////////////////////////////

class _TileViewState extends State<TileView> {
  late final TileJobQueue jobQueue;

  @override
  void initState() {
    super.initState();
    jobQueue = TileJobQueue(mapModel: widget.mapModel, renderer: widget.renderer);
  }

  @override
  void dispose() {
    jobQueue.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mapModel != widget.mapModel) {
      throw Exception("MapModel cannot be changed, recreate all classes which uses MapModel.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        /// Multiply the mappixels of the view with the scalefactor because the images will be shrinked by that factor in [TransformWidget].
        final double scaleFactor = MapsforgeSettingsMgr().getDeviceScaleFactor();
        jobQueue.setSize(
          constraints.maxWidth * scaleFactor,
          constraints.maxHeight * scaleFactor,
        );
        // Also inform the model so it can keep the whole viewport within bounds.
        widget.mapModel.setViewSize(
          constraints.maxWidth * scaleFactor,
          constraints.maxHeight * scaleFactor,
        );
        // use notifier instead of stream because it should be faster
        return ListenableBuilder(
          listenable: widget.mapModel,
          builder: (BuildContext context, Widget? child) {
            MapPosition? position = widget.mapModel.lastPosition;
            //print("Position change $position for renderer ${widget.renderer.getRenderKey()}");
            if (position == null) {
              return const SizedBox();
            }
            jobQueue.setPosition(position);
            return TransformWidget(
              mapCenter: position.getCenter(),
              mapPosition: position,
              screensize: Size(constraints.maxWidth, constraints.maxHeight),
              child: child!,
            );
            //            }
            // We do not have a position yet or we wait for processing of the first tiles
            //          return const SizedBox.expand();
          },
          child: CustomPaint(foregroundPainter: TilePainter(jobQueue, opacity: widget.opacity), child: const SizedBox.expand()),
        );
      },
    );
  }
}
