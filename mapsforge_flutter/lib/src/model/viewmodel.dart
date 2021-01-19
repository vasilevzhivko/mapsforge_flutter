import 'package:flutter/cupertino.dart';
import 'package:mapsforge_flutter/core.dart';
import 'package:mapsforge_flutter/maps.dart';
import 'package:mapsforge_flutter/src/model/dimension.dart';
import 'package:mapsforge_flutter/src/model/mappoint.dart';
import 'package:rxdart/rxdart.dart';

class ViewModel {
  NoPositionView noPositionView;
  MapViewPosition _mapViewPosition;
  final DisplayModel displayModel;
  ContextMenuBuilder contextMenuBuilder;

  ///
  /// The width and height of the view
  ///
  Dimension _viewDimension;

  Subject<MapViewPosition> _injectPosition = PublishSubject();

  Stream<MapViewPosition> get observePosition => _injectPosition.stream;

  Subject<TapEvent> _injectTap = PublishSubject();

  Stream<TapEvent> get observeTap => _injectTap.stream;

  Subject<GestureEvent> _injectGesture = PublishSubject();

  Stream<GestureEvent> get observeGesture => _injectGesture.stream;

  ViewModel({this.contextMenuBuilder, @required this.displayModel}) : assert(displayModel != null) {
    if (noPositionView == null) noPositionView = NoPositionView();
  }

  void dispose() {
    _injectPosition.close();
    _injectTap.close();
    _injectGesture.close();
  }

  MapViewPosition get mapViewPosition => _mapViewPosition;

  void setMapViewPosition(double latitude, double longitude) {
    if (_mapViewPosition != null) {
      MapViewPosition newPosition =
          MapViewPosition(latitude, longitude, _mapViewPosition.zoomLevel, _mapViewPosition.indoorLevel, displayModel.tileSize);
      _mapViewPosition = newPosition;
      _injectPosition.add(newPosition);
    } else {
      MapViewPosition newPosition =
          MapViewPosition(latitude, longitude, displayModel.DEFAULT_ZOOM, displayModel.DEFAULT_INDOOR_LEVEL, displayModel.tileSize);
      _mapViewPosition = newPosition;
      _injectPosition.add(newPosition);
    }
  }

  void zoomIn() {
    assert(_mapViewPosition != null);
    if (_mapViewPosition.zoomLevel >= displayModel.maxZoomLevel) return;
    MapViewPosition newPosition = MapViewPosition.zoomIn(_mapViewPosition);
    _mapViewPosition = newPosition;
    _injectPosition.add(newPosition);
  }

  void zoomInAround(double latitude, double longitude) {
    assert(_mapViewPosition != null);
    if (_mapViewPosition.zoomLevel >= displayModel.maxZoomLevel) return;
    MapViewPosition newPosition = MapViewPosition.zoomInAround(_mapViewPosition, latitude, longitude);
    _mapViewPosition = newPosition;
    _injectPosition.add(newPosition);
  }

  void zoomOut() {
    assert(_mapViewPosition != null);
    MapViewPosition newPosition = MapViewPosition.zoomOut(_mapViewPosition);
    _mapViewPosition = newPosition;
    _injectPosition.add(newPosition);
  }

  MapViewPosition setZoomLevel(int zoomLevel) {
    if (zoomLevel >= displayModel.maxZoomLevel) zoomLevel = displayModel.maxZoomLevel;
    if (_mapViewPosition != null) {
      MapViewPosition newPosition = MapViewPosition.zoom(_mapViewPosition, zoomLevel);
      _mapViewPosition = newPosition;
      _injectPosition.add(newPosition);
      return newPosition;
    } else {
      MapViewPosition newPosition = MapViewPosition(null, null, zoomLevel, displayModel.DEFAULT_INDOOR_LEVEL, displayModel.tileSize);
      _mapViewPosition = newPosition;
      _injectPosition.add(newPosition);
      return newPosition;
    }
  }

  void indoorLevelUp() {
    assert(_mapViewPosition != null);
    if (_mapViewPosition.zoomLevel >= displayModel.maxZoomLevel) return;
    MapViewPosition newPosition = MapViewPosition.indoorLevelUp(_mapViewPosition);
    _mapViewPosition = newPosition;
    _injectPosition.add(newPosition);
  }

  void indoorLevelDown() {
    assert(_mapViewPosition != null);
    MapViewPosition newPosition = MapViewPosition.indoorLevelDown(_mapViewPosition);
    _mapViewPosition = newPosition;
    _injectPosition.add(newPosition);
  }

  MapViewPosition setIndoorLevel(int indoorLevel) {
    if (_mapViewPosition != null) {
      MapViewPosition newPosition = MapViewPosition.setIndoorLevel(_mapViewPosition, indoorLevel);
      _mapViewPosition = newPosition;
      _injectPosition.add(newPosition);
      return newPosition;
    } else {
      MapViewPosition newPosition = MapViewPosition(null, null, displayModel.DEFAULT_ZOOM, indoorLevel, displayModel.tileSize);
      _mapViewPosition = newPosition;
      _injectPosition.add(newPosition);
      return newPosition;
    }
  }

  MapViewPosition setScale(Mappoint focalPoint, double scale) {
    assert(scale != null);
    assert(scale > 0);
    if (_mapViewPosition != null) {
      //print("Scaling ${_mapViewPosition.zoomLevel} * $scale");
      if (MercatorProjectionImpl.zoomLevelToScaleFactor(_mapViewPosition.zoomLevel) * scale < 1) {
        scale = 1 / MercatorProjectionImpl.zoomLevelToScaleFactor(_mapViewPosition.zoomLevel);
      } else {
        double scaleFactor = MercatorProjectionImpl.zoomLevelToScaleFactor(_mapViewPosition.zoomLevel) * scale;
        if (scaleFactor > MercatorProjectionImpl.zoomLevelToScaleFactor(displayModel.maxZoomLevel)) {
          scale = MercatorProjectionImpl.zoomLevelToScaleFactor(displayModel.maxZoomLevel) /
              MercatorProjectionImpl.zoomLevelToScaleFactor(_mapViewPosition.zoomLevel);
        }
      }
      MapViewPosition newPosition = MapViewPosition.scale(_mapViewPosition, focalPoint, scale);
      _mapViewPosition = newPosition;
      _injectPosition.add(newPosition);
      return newPosition;
    } else {
      MapViewPosition newPosition =
          MapViewPosition(null, null, displayModel.DEFAULT_ZOOM, displayModel.DEFAULT_INDOOR_LEVEL, displayModel.tileSize);
      newPosition = MapViewPosition.scale(newPosition, null, scale);
      _mapViewPosition = newPosition;
      _injectPosition.add(newPosition);
      return newPosition;
    }
  }

  void setLeftUpper(double left, double upper) {
    if (_mapViewPosition != null) {
      MapViewPosition newPosition = MapViewPosition.setLeftUpper(_mapViewPosition, left, upper, _viewDimension);
      _mapViewPosition = newPosition;
      _injectPosition.add(newPosition);
    } else {
      MapViewPosition newPosition =
          MapViewPosition(null, null, displayModel.DEFAULT_ZOOM - 1, displayModel.DEFAULT_INDOOR_LEVEL, displayModel.tileSize);
      _mapViewPosition = newPosition;
      _injectPosition.add(newPosition);
    }
  }

  void tapEvent(double left, double upper) {
    if (_mapViewPosition == null) return;
    _mapViewPosition.calculateBoundingBox(_viewDimension);
    TapEvent event = TapEvent(_mapViewPosition.mercatorProjection.pixelYToLatitude(_mapViewPosition.leftUpper.y + upper),
        _mapViewPosition.mercatorProjection.pixelXToLongitude(_mapViewPosition.leftUpper.x + left), left, upper);
    _injectTap.add(event);
  }

  void gestureEvent() {
    _injectGesture.add(GestureEvent());
  }

  Dimension get viewDimension => _viewDimension;

  Dimension setViewDimension(double width, double height) {
    if (_viewDimension != null && _viewDimension.width == width && _viewDimension.height == height) return _viewDimension;
    _viewDimension = Dimension(width, height);
    return _viewDimension;
  }
}

/////////////////////////////////////////////////////////////////////////////

class TapEvent {
  final double latitude;

  final double longitude;

  final double x;

  final double y;

  TapEvent(this.latitude, this.longitude, this.x, this.y)
      : assert(latitude != null),
        assert(longitude != null),
        assert(x != null),
        assert(y != null);
}

/////////////////////////////////////////////////////////////////////////////

class GestureEvent {}