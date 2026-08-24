import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_rendertheme/src/model/map_cap.dart';
import 'package:mapsforge_flutter_rendertheme/src/model/map_join.dart';

mixin StrokeSrcMixin {
  int _strokeColor = transparent();

  double _strokeWidth = 0;

  MapCap _strokeCap = MapCap.ROUND;

  MapJoin _strokeJoin = MapJoin.ROUND;

  List<double>? _strokeDashArray;

  int _strokeMinZoomLevel = MapsforgeSettingsMgr().strokeMinZoomlevel;

  int _dashMinZoomlevel = MapsforgeSettingsMgr().dashMinZoomlevel;

  void setStrokeColorFromNumber(int color) {
    _strokeColor = color;
  }

  void setStrokeWidth(double strokeWidth) {
    assert(strokeWidth >= 0);
    // Device ratio keeps lines crisp per-DPI; the line factor is the user's
    // "map line thickness" preference (1.0 = as authored).
    _strokeWidth = strokeWidth *
        MapsforgeSettingsMgr().getDeviceScaleFactor() *
        MapsforgeSettingsMgr().getLineScaleFactor();
  }

  double get strokeWidth => _strokeWidth;

  MapCap get strokeCap => _strokeCap;

  MapJoin get strokeJoin => _strokeJoin;

  List<double>? get strokeDashArray => _strokeDashArray;

  int get strokeMinZoomLevel => _strokeMinZoomLevel;

  void strokeSrcMixinClone(StrokeSrcMixin base) {
    _strokeColor = base._strokeColor;
    _strokeWidth = base._strokeWidth;
    _strokeCap = base._strokeCap;
    _strokeJoin = base._strokeJoin;
    _strokeDashArray = base._strokeDashArray;
    _strokeMinZoomLevel = base._strokeMinZoomLevel;
    _dashMinZoomlevel = base._dashMinZoomlevel;
  }

  void strokeSrcMixinScale(StrokeSrcMixin base, int zoomlevel) {
    strokeSrcMixinClone(base);
    if (zoomlevel >= _strokeMinZoomLevel) {
      double scaleFactor = MapsforgeSettingsMgr().calculateScaleFactor(zoomlevel, _strokeMinZoomLevel);
      _strokeWidth = _strokeWidth * scaleFactor;
    }
    if (zoomlevel >= _dashMinZoomlevel) {
      if (_strokeDashArray != null) {
        double scaleFactor = MapsforgeSettingsMgr().calculateScaleFactor(zoomlevel, _dashMinZoomlevel);
        List<double> newStrokeDashArray = [];
        for (var element in _strokeDashArray!) {
          newStrokeDashArray.add(element * scaleFactor);
        }
        _strokeDashArray = newStrokeDashArray;
      }
    }
  }

  bool isStrokeTransparent() {
    return _strokeColor == transparent();
  }

  static int transparent() => 0x00000000;

  int get strokeColor => _strokeColor;

  void setStrokeCap(MapCap cap) {
    _strokeCap = cap;
  }

  void setStrokeJoin(MapJoin join) {
    _strokeJoin = join;
  }

  void setStrokeDashArray(List<double>? strokeDashArray) {
    if (strokeDashArray != null) {
      // Scale the dash pattern by the user's "map line thickness" preference, the
      // same factor setStrokeWidth applies to the width. Otherwise the coloured
      // route "ties" (dashed overlays) keep their authored length/spacing while
      // the line width shrinks/grows — so they visibly don't scale together.
      final double lineFactor = MapsforgeSettingsMgr().getLineScaleFactor();
      if (lineFactor != 1.0) {
        strokeDashArray =
            strokeDashArray.map((element) => element * lineFactor).toList();
      }
    }
    _strokeDashArray = strokeDashArray;
  }

  void setStrokeMinZoomLevel(int strokeMinZoomLevel) {
    _strokeMinZoomLevel = strokeMinZoomLevel;
  }
}
