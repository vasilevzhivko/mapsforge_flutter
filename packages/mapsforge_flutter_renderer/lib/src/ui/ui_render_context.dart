import 'package:mapsforge_flutter_rendertheme/model.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_renderer/src/ui/ui_canvas.dart';

/// A render context that holds all the necessary information for rendering a map tile.
///
/// This includes the canvas to draw on, the projection for converting geo-coordinates
/// to pixel coordinates, and the current map rotation.
class UiRenderContext extends RenderContext {
  static final int MAX_DRAWING_LAYERS = 11;

  /// The canvas for this rendering
  final UiCanvas canvas;

  /// The reference mappoint for this rendering. This is usualy the center of the canvas in map pixel coordinates
  final Mappoint reference;

  /// The pixel projection for the current zoom level.
  final PixelProjection projection;

  /// The current map rotation in radians.
  double rotationRadian;

  /// The live fractional-zoom scale of the enclosing view (`MapPosition.scale`,
  /// range [1,2) at rest with persistent fractional zoom). For TILE rendering
  /// this stays 1.0 — tiles are bitmaps and are scaled by the view's
  /// TransformWidget. For the LIVE symbol/marker layers it is set to the view
  /// scale so point symbols can COUNTER-scale by 1/scale around their anchor:
  /// the TransformWidget then re-applies `scale`, leaving symbols a constant
  /// on-screen size (positions still track the map) instead of being magnified
  /// up to ~2× by the fractional residual.
  double scale;

  /// Extra on-screen size factor for POINT SYMBOLS drawn with this context,
  /// applied on top of the fractional-zoom counter-scale. <1 renders symbols a
  /// touch smaller than the raw render-theme size. Set below 1 only for the
  /// render-theme (label-layer) symbols; left at 1.0 for app MARKERS so those
  /// keep their intended size, and for tiles.
  double symbolSizeFactor;

  /// Creates a new `UiRenderContext`.
  UiRenderContext(
      {required this.canvas,
      required this.reference,
      required this.projection,
      this.rotationRadian = 0,
      this.scale = 1.0,
      this.symbolSizeFactor = 1.0});

  @override
  String toString() {
    return 'UiRenderContext{reference: $reference, projection: $projection, rotationRadian: $rotationRadian}';
  }
}
