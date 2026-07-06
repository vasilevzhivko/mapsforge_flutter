import 'package:mapsforge_flutter_renderer/offline_renderer.dart';

/// Builds a [Renderer] for a [CustomSourceSpec] (XYZ / WMTS / WMS).
class CustomRendererFactory {
  static Renderer create(CustomSourceSpec spec) {
    switch (spec.kind) {
      case RendererKind.xyz:
        return XyzTileRenderer(spec);
      case RendererKind.wmts:
        return WmtsTileRenderer(spec);
      case RendererKind.wms:
        return WmsTileRenderer(spec);
    }
  }
}
