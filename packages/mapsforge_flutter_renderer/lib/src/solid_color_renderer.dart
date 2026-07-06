import 'dart:ui' as ui;

import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/offline_renderer.dart';
import 'package:mapsforge_flutter_renderer/src/ui/tile_picture.dart';

/// A minimal base renderer that fills every tile with a single flat color.
///
/// Useful as the *base* under a marker-only data source (e.g. a Garmin `.img`
/// map rendered as contour/area/point markers): there is no tile imagery to
/// draw, so the base just needs a neutral background. Defaults to a light
/// "paper topo" cream.
class SolidColorRenderer extends Renderer {
  /// ARGB fill color for every tile.
  final int color;

  /// Optional key suffix so distinct-colored instances get distinct cache keys.
  final String keySuffix;

  SolidColorRenderer({this.color = 0xFFF3EEE3, this.keySuffix = ''});

  @override
  Future<JobResult> executeJob(JobRequest job) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final tileSize = MapsforgeSettingsMgr().tileSize;
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, tileSize, tileSize),
      ui.Paint()..color = ui.Color(color),
    );
    final pic = recorder.endRecording();
    return JobResult.normal(TilePicture.fromPicture(pic));
  }

  @override
  Future<JobResult> retrieveLabels(JobRequest job) =>
      Future.value(JobResult.unsupported());

  @override
  String getRenderKey() => 'solid$keySuffix';

  @override
  bool supportLabels() => false;
}
