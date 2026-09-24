import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter/src/marker/marker_datastore.dart';
import 'package:mapsforge_flutter/src/marker/marker_datastore_painter.dart';
import 'package:mapsforge_flutter/src/transform_widget.dart';
import 'package:mapsforge_flutter/src/util/tile_helper.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/utils.dart';

/// A Flutter widget overlay that renders markers from a [MarkerDatastore] on a map.
///
/// This overlay provides an efficient way to display large numbers of markers by:
/// - Automatically managing marker visibility based on zoom level and viewport
/// - Caching marker queries to minimize datastore requests
/// - Using intelligent bounding box extension to reduce query frequency
/// - Integrating with the map's transformation system for smooth rendering
///
/// The overlay works by:
/// 1. Listening to map position changes via [MapModel.positionStream]
/// 2. Calculating the visible screen area as a [BoundingBox]
/// 3. Extending the bounding box by [extendMargin] to create a buffer zone
/// 4. Requesting markers from the datastore only when needed
/// 5. Rendering markers using [MarkerDatastorePainter] with proper transformations
///
/// ## Performance Optimizations
///
/// - **Zoom Level Caching**: Avoids redundant datastore queries at the same zoom level
/// - **Bounding Box Extension**: Uses [extendMargin] to create a buffer, reducing queries during small map movements
/// - **Conditional Updates**: Only updates markers when the view moves outside the cached bounding box
/// - **Transform Integration**: Leverages [TransformWidget] for efficient coordinate transformations
///
/// ## Usage Example
///
/// ```dart
/// // Create a marker datastore
/// final markerDatastore = DefaultMarkerDatastore();
/// markerDatastore.addMarker(PoiMarker(
///   position: LatLong(52.5200, 13.4050), // Berlin
///   displayName: 'Berlin',
/// ));
///
/// // Add overlay to map
/// Stack(
///   children: [
///     MapsforgeView(mapModel: mapModel),
///     MarkerDatastoreOverlay(
///       mapModel: mapModel,
///       datastore: markerDatastore,
///       zoomlevelRange: ZoomlevelRange(5, 18),
///       extendMargin: 1.5, // 50% buffer around visible area
///     ),
///   ],
/// )
/// ```
///
/// ## Best Practices
///
/// - Use [extendMargin] values between 1.2-2.0 for optimal performance
/// - Implement efficient marker filtering in your datastore based on zoom level
/// - Consider marker clustering for high-density datasets
/// - Use appropriate [ZoomlevelRange] to control marker visibility
///
/// See also:
/// - [MarkerDatastore] for implementing custom marker data sources
/// - [DefaultMarkerDatastore] for a ready-to-use marker container
/// - [SingleMarkerOverlay] for displaying individual markers
class MarkerDatastoreOverlay extends StatefulWidget {
  /// The map model providing position updates and coordinate transformations.
  ///
  /// This model's [MapModel.positionStream] is used to listen for map position
  /// changes and trigger marker updates accordingly.
  final MapModel mapModel;

  /// The marker datastore containing the markers to be displayed.
  ///
  /// The overlay will query this datastore for markers within the visible
  /// area and render them on the map. The datastore should implement
  /// efficient filtering based on zoom level and bounding box.
  final MarkerDatastore datastore;

  /// The zoom level range in which markers should be visible.
  ///
  /// Markers will only be requested and rendered when the current map
  /// zoom level falls within this range. This helps optimize performance
  /// by avoiding marker processing at inappropriate zoom levels.
  final ZoomlevelRange zoomlevelRange;

  /// Margin factor to extend the visible bounding box for marker queries.
  ///
  /// This creates a buffer zone around the visible screen area to reduce
  /// the frequency of datastore queries during map navigation. The value
  /// represents a multiplication factor:
  ///
  /// - `1.0`: No extension (query exact visible area)
  /// - `1.2`: Extend by 20% in all directions (recommended minimum)
  /// - `1.5`: Extend by 50% in all directions (good balance)
  /// - `2.0`: Double the query area (maximum recommended)
  ///
  /// **Performance Impact:**
  /// - Lower values: More frequent queries, less memory usage
  /// - Higher values: Fewer queries, more memory usage
  ///
  /// **Constraints:** Must be >= 1.0
  final double extendMargin;

  /// Creates a marker datastore overlay.
  ///
  /// [mapModel] provides map position updates and transformations
  /// [datastore] contains the markers to display
  /// [zoomlevelRange] defines the zoom levels where markers are visible
  /// [extendMargin] controls the buffer zone size (default: 1.2 = 20% extension)
  ///
  /// Throws [AssertionError] if [extendMargin] < 1.0
  const MarkerDatastoreOverlay({super.key, required this.mapModel, required this.datastore, required this.zoomlevelRange, this.extendMargin = 1.5})
    : assert(extendMargin >= 1.0, 'extendMargin must be >= 1.0');

  @override
  State<MarkerDatastoreOverlay> createState() => _MarkerDatastoreOverlayState();
}

//////////////////////////////////////////////////////////////////////////////

/// Internal state for [MarkerDatastoreOverlay].
///
/// Manages caching of bounding boxes and zoom levels to optimize
/// datastore query frequency and improve rendering performance.
class _MarkerDatastoreOverlayState extends State<MarkerDatastoreOverlay> {
  /// The last bounding box used for marker queries.
  ///
  /// Used to determine if the visible area has moved enough to warrant
  /// a new marker query. Null indicates no previous query has been made.
  BoundingBox? _cachedBoundingBox;

  /// The last zoom level for which markers were requested.
  ///
  /// When the zoom level changes, all markers need to be re-queried
  /// as different markers may be appropriate for different zoom levels.
  /// A value of -1 indicates no previous zoom level has been cached.
  int _cachedZoomlevel = -1;

  /// The position the marker painter is ANCHORED to. Markers are painted
  /// (and raster-cached behind a RepaintBoundary) against this position;
  /// pure pans translate the cached raster instead of re-rendering every
  /// marker per frame — the same recipe that fixed the label layer.
  /// Re-anchoring (a new instance here, which the painter's shouldRepaint
  /// detects by identity) happens immediately on zoom/indoor changes and at
  /// most every [_gestureAnchorInterval] on rotation/scale changes.
  MapPosition? _anchor;

  static const Duration _gestureAnchorInterval = Duration(milliseconds: 33);

  DateTime _lastGestureAnchor = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _trailingAnchor;

  @override
  void initState() {
    super.initState();
    widget.mapModel.registerMarkerDatastore(widget.datastore);
  }

  @override
  void dispose() {
    _trailingAnchor?.cancel();
    widget.mapModel.unregisterMarkerDatastore(widget.datastore);
    super.dispose();
  }

  /// Updates [_anchor] for [position]: immediately for zoom/indoor changes,
  /// throttled (with a trailing update so the final state always lands) for
  /// rotation/scale, and NOT AT ALL for pure translation — panning is
  /// expressed by translating the cached raster.
  void _updateAnchor(MapPosition position) {
    final MapPosition? anchor = _anchor;
    if (anchor == null || anchor.zoomlevel != position.zoomlevel || anchor.indoorLevel != position.indoorLevel) {
      _trailingAnchor?.cancel();
      _trailingAnchor = null;
      _anchor = position;
      return;
    }
    if (anchor.rotation == position.rotation && anchor.scale == position.scale) {
      return; // translation only — the cached raster is reused
    }
    final DateTime now = DateTime.now();
    final Duration sinceLast = now.difference(_lastGestureAnchor);
    if (sinceLast >= _gestureAnchorInterval) {
      _lastGestureAnchor = now;
      _anchor = position;
    } else {
      _trailingAnchor ??= Timer(_gestureAnchorInterval - sinceLast, () {
        _trailingAnchor = null;
        if (!mounted) return;
        setState(() {
          _lastGestureAnchor = DateTime.now();
          _anchor = widget.mapModel.lastPosition;
        });
      });
    }
  }

  /// Called when the widget configuration changes.
  ///
  /// Invalidates cached zoom level if the datastore or zoom level range
  /// has changed, forcing a complete marker refresh on the next build.
  @override
  void didUpdateWidget(covariant MarkerDatastoreOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.datastore != widget.datastore || oldWidget.zoomlevelRange != widget.zoomlevelRange) {
      _cachedZoomlevel = -1;
    }
  }

  /// Builds the marker overlay widget.
  ///
  /// Uses [LayoutBuilder] to get screen dimensions and [StreamBuilder] to
  /// listen for map position changes. Implements intelligent caching to
  /// minimize datastore queries while ensuring markers stay current.
  ///
  /// The build process:
  /// 1. Get screen size from layout constraints
  /// 2. Listen to map position stream
  /// 3. Calculate visible bounding box
  /// 4. Check if new marker query is needed
  /// 5. Request markers from datastore if necessary
  /// 6. Render markers using custom painter
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        Size screensize = constraints.biggest;
        // use notifier instead of stream because it should be faster
        return ListenableBuilder(
          listenable: widget.mapModel,
          builder: (BuildContext context, Widget? child) {
            MapPosition? position = widget.mapModel.lastPosition;
            if (position == null) {
              return const SizedBox();
            }
            // Handle position changes at the same zoom level
            if (_cachedZoomlevel == position.zoomlevel) {
              BoundingBox boundingBox = TileHelper.calculateBoundingBoxOfScreen(
                mapPosition: position,
                screensize: screensize * MapsforgeSettingsMgr().getDeviceScaleFactor(),
              );

              // Check if we've moved outside the cached bounding box
              if (_cachedBoundingBox == null || !_cachedBoundingBox!.containsBoundingBox(boundingBox)) {
                // Extend the bounding box to create a buffer zone
                boundingBox = boundingBox.extendMargin(widget.extendMargin);

                // Request markers for the new area
                widget.datastore.askChangeBoundingBox(_cachedZoomlevel, boundingBox);
                _cachedBoundingBox = boundingBox;
              }
            }
            // Handle zoom level changes
            if (_cachedZoomlevel != position.zoomlevel) {
              if (widget.zoomlevelRange.isWithin(position.zoomlevel)) {
                BoundingBox boundingBox = TileHelper.calculateBoundingBoxOfScreen(
                  mapPosition: position,
                  screensize: screensize * MapsforgeSettingsMgr().getDeviceScaleFactor(),
                );
                boundingBox = boundingBox.extendMargin(widget.extendMargin);

                // Notify datastore of zoom level change - this may trigger
                // marker filtering, clustering, or style changes
                widget.datastore.askChangeZoomlevel(position.zoomlevel, boundingBox, position.projection);

                // Update cache
                _cachedZoomlevel = position.zoomlevel;
                _cachedBoundingBox = boundingBox;
              } else {
                // todo maybe the datastore should be informed that it is not needed for that zoomlevel
                return const SizedBox();
              }
            }
            // Render markers with proper coordinate transformation. The
            // painter is anchored (see _updateAnchor) and raster-cached
            // behind a RepaintBoundary; pans translate the cached raster —
            // previously every position event re-rendered EVERY visible
            // marker, the remaining per-frame cost in marker-dense cities.
            _updateAnchor(position);
            final MapPosition anchor = _anchor!;
            Widget content = RepaintBoundary(
              child: CustomPaint(foregroundPainter: MarkerDatastorePainter(anchor, widget.datastore), child: const SizedBox.expand()),
            );
            final Mappoint anchorCenter = anchor.getCenter();
            final Mappoint currentCenter = position.getCenter();
            final double dx = anchorCenter.x - currentCenter.x, dy = anchorCenter.y - currentCenter.y;
            if (dx != 0 || dy != 0) {
              content = Transform.translate(offset: Offset(dx, dy), child: content);
            }
            return TransformWidget(
              mapCenter: position.getCenter(),
              mapPosition: position,
              screensize: screensize,
              child: content,
            );
          },
        );
      },
    );
  }
}
