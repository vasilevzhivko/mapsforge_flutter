import 'package:mapsforge_flutter_core/dart_isolate.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/src/datastore_reader.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';
import 'package:mapsforge_flutter_rendertheme/rendertheme.dart';

/// An implementation of `DatastoreReader` that performs the reading and processing
/// of map data in a separate isolate.
///
/// This is crucial for performance, as it prevents the UI thread from being
/// blocked by the CPU-intensive work of reading map files and matching them
/// against a render theme.
class IsolateDatastoreReader implements DatastoreReader {
  static DatastoreReaderImpl? _reader;

  /// One shared reader isolate per datastore (identity-keyed): several
  /// renderer layers over the same datastore share a single isolate — and
  /// thus a single in-isolate Mapfile with its block/index caches — instead
  /// of duplicating all of it per layer.
  static final Map<Datastore, Future<IsolateDatastoreReader>> _shared = Map.identity();

  static final Map<Datastore, int> _refCounts = Map.identity();

  /// a long-running instance of an isolate
  late final FlutterIsolateInstance _isolateInstance = FlutterIsolateInstance();

  IsolateDatastoreReader._();

  /// Creates and spawns a new `IsolateDatastoreReader`.
  static Future<IsolateDatastoreReader> create(Datastore datastore) async {
    IsolateDatastoreReader instance = IsolateDatastoreReader._();
    // The datastore is deep-copied into the isolate; open file handles cannot
    // cross the boundary.
    await datastore.prepareForIsolateSend();
    await instance._isolateInstance.spawn(_createInstanceStatic, DatastoreReaderIsolateInitRequest(datastore));
    return instance;
  }

  /// Returns the shared reader isolate for [datastore], spawning it on first
  /// use. Every call must be balanced by a [release] call.
  static Future<IsolateDatastoreReader> shared(Datastore datastore) {
    _refCounts[datastore] = (_refCounts[datastore] ?? 0) + 1;
    return _shared.putIfAbsent(datastore, () => create(datastore));
  }

  /// Releases one [shared] reference; the isolate is disposed when the last
  /// user releases it. Never throws (a failed spawn is silently discarded).
  static Future<void> release(Datastore datastore) async {
    final int refs = (_refCounts[datastore] ?? 0) - 1;
    if (refs > 0) {
      _refCounts[datastore] = refs;
      return;
    }
    _refCounts.remove(datastore);
    final Future<IsolateDatastoreReader>? future = _shared.remove(datastore);
    if (future == null) return;
    try {
      (await future)._isolateInstance.dispose();
    } catch (_) {
      // spawn had failed; nothing to dispose
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _createInstanceStatic(IsolateInitInstanceParams request) async {
    _reader = DatastoreReaderImpl((request.initObject as DatastoreReaderIsolateInitRequest).datastore);
    await FlutterIsolateInstance.isolateInit(request, _acceptRequestsStatic);
  }

  @pragma('vm:entry-point')
  static Future _acceptRequestsStatic(Object request) async {
    DatastoreReaderIsolateRequest r = request as DatastoreReaderIsolateRequest;
    if (r.rightLower == null) return _reader!.read(r.tile, r.renderthemeLevel);
    return _reader!.readLabels(r.tile, r.rightLower!, r.renderthemeLevel);
  }

  @override
  Future<LayerContainerCollection?> read(Tile tile, RenderthemeZoomlevel renderthemeLevel) async {
    return _isolateInstance.compute(DatastoreReaderIsolateRequest(tile, renderthemeLevel));
  }

  @override
  Future<LayerContainerCollection?> readLabels(Tile leftUpper, Tile rightLower, RenderthemeZoomlevel renderthemeLevel) async {
    return _isolateInstance.compute(DatastoreReaderIsolateRequest(leftUpper, renderthemeLevel, rightLower: rightLower));
  }
}

//////////////////////////////////////////////////////////////////////////////

/// A message to initialize the `DatastoreReaderImpl` in the isolate.
class DatastoreReaderIsolateInitRequest {
  final Datastore datastore;

  DatastoreReaderIsolateInitRequest(this.datastore);
}
//////////////////////////////////////////////////////////////////////////////

/// A message to request the reading of map data in the isolate.
class DatastoreReaderIsolateRequest {
  final Tile tile;
  final Tile? rightLower;
  final RenderthemeZoomlevel renderthemeLevel;

  DatastoreReaderIsolateRequest(this.tile, this.renderthemeLevel, {this.rightLower});
}

//////////////////////////////////////////////////////////////////////////////

/// An implementation of `DatastoreReader` that performs the reading and processing
/// of map data in the same thread.
///
/// This class reads data from a `Datastore` (e.g., a .map file), matches it
/// against a `RenderTheme`, and produces a `LayerContainerCollection` that can
/// be rendered.
class DatastoreReaderImpl implements DatastoreReader {
  final Datastore datastore;

  DatastoreReaderImpl(this.datastore);

  /// Reads the map data for a single [tile] and processes it against the
  /// [renderthemeLevel].
  @override
  Future<LayerContainerCollection?> read(Tile tile, RenderthemeZoomlevel renderthemeLevel) async {
    if (!(await datastore.supportsTile(tile))) {
      return null;
    }
    DatastoreBundle? datastoreBundle = await datastore.readMapDataSingle(tile);
    if (datastoreBundle == null) {
      return null;
    }
    LayerContainerCollection layerContainerCollection = LayerContainerCollection(renderthemeLevel.maxLevels);
    _processMapReadResult(layerContainerCollection, tile, renderthemeLevel, datastoreBundle);
    layerContainerCollection.clashingInfoCollection.collisionFreeOrdered();
    return layerContainerCollection;
  }

  /// Reads the label data for a given tile range and processes it against the
  /// [renderthemeLevel].
  @override
  Future<LayerContainerCollection?> readLabels(Tile leftUpper, Tile rightLower, RenderthemeZoomlevel renderthemeLevel) async {
    // if (!(await datastore.supportsTile(leftUpper))) {
    //   return null;
    // }
    DatastoreBundle? datastoreBundle = await datastore.readLabels(leftUpper, rightLower);
    if (datastoreBundle == null) return null;
    LayerContainerCollection layerContainerCollection = LayerContainerCollection(renderthemeLevel.maxLevels);
    _processMapReadResult(layerContainerCollection, leftUpper, renderthemeLevel, datastoreBundle);
    layerContainerCollection.drawings.clear();
    layerContainerCollection.clashingInfoCollection.clear();
    layerContainerCollection.labels.collisionFreeOrdered();
    return layerContainerCollection;
  }

  /// Creates rendering instructions based on the given ways and nodes and the defined rendertheme
  void _processMapReadResult(
    LayerContainerCollection layerContainerCollection,
    Tile tile,
    RenderthemeZoomlevel renderthemeLevel,
    DatastoreBundle datastoreBundle,
  ) {
    PixelProjection projection = PixelProjection(tile.zoomLevel);
    for (PointOfInterest pointOfInterest in datastoreBundle.pointOfInterests) {
      List<Renderinstruction> renderinstructions = renderthemeLevel.matchNode(tile.indoorLevel, pointOfInterest);
      if (renderinstructions.isEmpty) continue;
      LayerContainer layerContainer = layerContainerCollection.getLayer(pointOfInterest.layer);
      NodeProperties nodeProperties = NodeProperties(pointOfInterest, projection);
      for (Renderinstruction renderinstruction in renderinstructions) {
        renderinstruction.matchNode(layerContainer, nodeProperties);
      }
    }

    // never ever call an async method 44000 times. It takes 2 seconds to do so!
    //    Future.wait(mapReadResult.ways.map((way) => _renderWay(renderContext, PolylineContainer(way, renderContext.job.tile))));
    for (Way way in datastoreBundle.ways) {
      if (way.latLongs.isEmpty || way.latLongs[0].isEmpty) continue;
      // Rule matching FIRST: it is tag-cached (one map lookup for repeated
      // tag sets) and way-count bound, while geometry projection is
      // point-count bound and allocates per coordinate. Ways without rules
      // at this zoom die here for free.
      final bool closedWay = LatLongUtils.isClosedWay(way.latLongs[0]);
      final List<Renderinstruction> renderinstructions = closedWay ? renderthemeLevel.matchClosedWay(tile, way) : renderthemeLevel.matchOpenWay(tile, way);
      if (renderinstructions.isEmpty) continue;

      // Same "smaller than 5x5 px" filter as always, but computed on the RAW
      // coordinates before any projection/allocation: Mercator x is linear in
      // longitude and y monotonic in latitude, so the exact pixel extent
      // needs only a min/max scan plus two latitude projections. At low zoom
      // this rejects the vast majority of ways almost for free.
      final List<ILatLong> outer = way.latLongs[0];
      double minLat = outer[0].latitude, maxLat = minLat;
      double minLon = outer[0].longitude, maxLon = minLon;
      for (int i = 1; i < outer.length; i++) {
        final ILatLong p = outer[i];
        final double lat = p.latitude;
        final double lon = p.longitude;
        if (lat < minLat) {
          minLat = lat;
        } else if (lat > maxLat) {
          maxLat = lat;
        }
        if (lon < minLon) {
          minLon = lon;
        } else if (lon > maxLon) {
          maxLon = lon;
        }
      }
      if ((maxLon - minLon) / 360 * projection.mapsize < 5 && projection.latitudeToPixelY(minLat) - projection.latitudeToPixelY(maxLat) < 5) {
        continue;
      }

      final WayProperties wayProperties = WayProperties(way, projection, isClosedWay: closedWay);
      if (wayProperties.getCoordinatesAbsolute().isEmpty) continue;
      final LayerContainer layerContainer = layerContainerCollection.getLayer(way.layer);
      for (Renderinstruction renderinstruction in renderinstructions) {
        renderinstruction.matchWay(layerContainer, wayProperties);
      }
    }
    // if (mapReadResult.isWater) {
    //   _renderWaterBackground(renderContext);
    // }
    layerContainerCollection.reduce();
  }
}
