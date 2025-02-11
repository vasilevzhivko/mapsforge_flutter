import 'package:mapsforge_flutter/src/model/maprectangle.dart';

import '../../core.dart';
import '../../datastore.dart';
import '../../maps.dart';
import '../rendertheme/rendercontext.dart';
import '../rendertheme/wayproperties.dart';

/// Reads the content of a datastore - e.g. MapFile - either via isolate or direct
/// in the main thread.
class DatastoreReader {
  DatastoreReader();

  Future<DatastoreReadResult?> read(
      Datastore datastore,
      Tile tile,
      PixelProjection projection,
      RenderContext renderContext,
      RenderthemeLevel renderthemeLevel) async {
    // read the mapdata directly in this thread
    await datastore.lateOpen();
    if (!datastore.supportsTile(tile, projection)) {
      return null;
    }
    DatastoreReadResult? mapReadResult =
        await datastore.readMapDataSingle(tile);
    if (mapReadResult != null)
      processMapReadResult(
          renderContext, tile, renderthemeLevel, mapReadResult);
    return mapReadResult;
  }

  Future<DatastoreReadResult?> readLabels(
      Datastore datastore,
      Tile tile,
      PixelProjection projection,
      RenderContext renderContext,
      RenderthemeLevel renderthemeLevel) async {
    await datastore.lateOpen();
    if (!datastore.supportsTile(tile, projection)) {
      return null;
    }
    DatastoreReadResult? mapReadResult = await datastore.readLabelsSingle(tile);
    if (mapReadResult != null)
      processMapReadResult(
          renderContext, tile, renderthemeLevel, mapReadResult);
    return mapReadResult;
  }

  /// Creates rendering instructions based on the given ways and nodes and the defined rendertheme
  void processMapReadResult(final RenderContext renderContext, Tile tile,
      RenderthemeLevel renderthemeLevel, DatastoreReadResult mapReadResult) {
    for (PointOfInterest pointOfInterest in mapReadResult.pointOfInterests) {
      NodeProperties nodeProperties = NodeProperties(pointOfInterest);
      List<Shape> shapes = _retrieveShapesForPoi(
          renderContext, tile, renderthemeLevel, nodeProperties);
      for (Shape shape in shapes) {
        shape.renderNode(renderContext, nodeProperties);
      }
    }

    // never ever call an async method 44000 times. It takes 2 seconds to do so!
//    Future.wait(mapReadResult.ways.map((way) => _renderWay(renderContext, PolylineContainer(way, renderContext.job.tile))));
    for (Way way in mapReadResult.ways) {
      WayProperties wayProperties = WayProperties(way);
      MapRectangle rectangle =
          wayProperties.getBoundary(renderContext.projection);
      // filter small ways
      if (rectangle.getWidth() < 5 && rectangle.getHeight() < 5) continue;
      List<Shape> shapes = _retrieveShapesForWay(
          renderContext, tile, renderthemeLevel, wayProperties);
      for (Shape shape in shapes) {
        shape.renderWay(renderContext, wayProperties);
      }
    }
    if (mapReadResult.isWater) {
      _renderWaterBackground(renderContext);
    }
  }

  List<Shape> _retrieveShapesForPoi(
      final RenderContext renderContext,
      Tile tile,
      RenderthemeLevel renderthemeLevel,
      NodeProperties nodeProperties) {
    renderContext.setDrawingLayers(nodeProperties.layer);
    List<Shape> shapes = renderthemeLevel.matchNode(tile, nodeProperties);
    return shapes;
  }

  List<Shape> _retrieveShapesForWay(
      final RenderContext renderContext,
      Tile tile,
      RenderthemeLevel renderthemeLevel,
      WayProperties wayProperties) {
    if (wayProperties.getCoordinatesAbsolute(renderContext.projection).length ==
        0) return [];
    renderContext.setDrawingLayers(wayProperties.getLayer());
    if (wayProperties.isClosedWay) {
      List<Shape> shapes =
          renderthemeLevel.matchClosedWay(tile, wayProperties.way);
      return shapes;
    } else {
      List<Shape> shapes =
          renderthemeLevel.matchLinearWay(tile, wayProperties.way);
      return shapes;
    }
  }

  void _renderWaterBackground(final RenderContext renderContext) {
    // renderContext.setDrawingLayers(0);
    // List<Mappoint> coordinates =
    //     getTilePixelCoordinates(renderContext.job.tileSize);
    // Mappoint tileOrigin =
    //     renderContext.projection.getLeftUpper(renderContext.job.tile);
    // for (int i = 0; i < coordinates.length; i++) {
    //   coordinates[i] = coordinates[i].offset(tileOrigin.x, tileOrigin.y);
    // }
    // Watercontainer way = Watercontainer(
    //     coordinates, renderContext.job.tile, [TAG_NATURAL_WATER]);
    //renderContext.renderTheme.matchClosedWay(databaseRenderer, renderContext, way);
  }
}
