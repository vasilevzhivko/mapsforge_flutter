import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mapsforge_flutter_core/utils.dart';
import 'package:mapsforge_flutter_renderer/src/ui/tile_picture.dart';

/// A helper class for creating placeholder and error tile bitmaps.
///
/// Every method returns a freshly recorded [TilePicture] owned by the caller —
/// recording these few draw commands is cheap, and caller ownership keeps the
/// dispose contract simple (no shared instances that a cache could dispose).
class ImageHelper {
  static final double _margin = 5;

  /// Creates a tile bitmap to indicate that the tile is currently being rendered.
  ///
  /// This is used as a placeholder until the actual tile data is available.
  Future<TilePicture> createMissingBitmap() async {
    double tileSize = MapsforgeSettingsMgr().tileSize;
    var pictureRecorder = ui.PictureRecorder();
    var canvas = ui.Canvas(pictureRecorder);
    var paint = ui.Paint();
    paint.strokeWidth = 1;
    paint.color = const ui.Color(0xffaaaaaa);
    paint.isAntiAlias = true;

    canvas.drawLine(ui.Offset(_margin, _margin), ui.Offset(tileSize - _margin, _margin), paint);
    canvas.drawLine(ui.Offset(_margin, _margin), ui.Offset(_margin, tileSize - _margin), paint);
    canvas.drawLine(ui.Offset(tileSize - _margin, _margin), ui.Offset(tileSize - _margin, tileSize - _margin), paint);
    canvas.drawLine(ui.Offset(_margin, tileSize - _margin), ui.Offset(tileSize - _margin, tileSize - _margin), paint);

    ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 10.0, textAlign: ui.TextAlign.center))
      ..pushStyle(ui.TextStyle(color: paint.color))
      ..addText("Waiting for rendering...");
    canvas.drawParagraph(builder.build()..layout(ui.ParagraphConstraints(width: tileSize.toDouble())), ui.Offset(0, tileSize / 2));

    var pic = pictureRecorder.endRecording();
    return TilePicture.fromPicture(pic);
  }

  /// Creates a tile bitmap to indicate that no map data is available for this tile.
  Future<TilePicture> createNoDataBitmap() async {
    double tileSize = MapsforgeSettingsMgr().tileSize;
    var pictureRecorder = ui.PictureRecorder();
    var canvas = ui.Canvas(pictureRecorder);
    var paint = ui.Paint();
    paint.strokeWidth = 1;
    paint.color = const ui.Color(0xffaaaaaa);
    paint.isAntiAlias = true;

    canvas.drawLine(ui.Offset(_margin, _margin), ui.Offset(tileSize - _margin, _margin), paint);
    canvas.drawLine(ui.Offset(_margin, _margin), ui.Offset(_margin, tileSize - _margin), paint);
    canvas.drawLine(ui.Offset(tileSize - _margin, _margin), ui.Offset(tileSize - _margin, tileSize - _margin), paint);
    canvas.drawLine(ui.Offset(_margin, tileSize - _margin), ui.Offset(tileSize - _margin, tileSize - _margin), paint);

    ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 14.0, textAlign: ui.TextAlign.center))
      ..pushStyle(ui.TextStyle(color: Colors.red))
      ..addText("No data available");
    canvas.drawParagraph(builder.build()..layout(ui.ParagraphConstraints(width: tileSize.toDouble())), ui.Offset(0, tileSize / 2));

    var pic = pictureRecorder.endRecording();
    return TilePicture.fromPicture(pic);
  }

  /// Creates a fully transparent tile — used as the "no data" fallback for
  /// transparent OVERLAY renderers so a missing/failed overlay tile shows the
  /// layer below instead of an opaque placeholder grid.
  Future<TilePicture> createTransparentBitmap() async {
    // An empty recorded picture paints nothing → fully transparent tile.
    var pictureRecorder = ui.PictureRecorder();
    ui.Canvas(pictureRecorder);
    var pic = pictureRecorder.endRecording();
    return TilePicture.fromPicture(pic);
  }

  /// Creates a tile bitmap to display an error message.
  Future<TilePicture> createErrorBitmap(dynamic error) async {
    double tileSize = MapsforgeSettingsMgr().tileSize;
    var pictureRecorder = ui.PictureRecorder();
    var canvas = ui.Canvas(pictureRecorder);
    var paint = ui.Paint();
    paint.strokeWidth = 1;
    paint.color = const ui.Color(0xffaaaaaa);
    paint.isAntiAlias = true;

    canvas.drawLine(ui.Offset(_margin, _margin), ui.Offset(tileSize - _margin, _margin), paint);
    canvas.drawLine(ui.Offset(_margin, _margin), ui.Offset(_margin, tileSize - _margin), paint);
    canvas.drawLine(ui.Offset(tileSize - _margin, _margin), ui.Offset(tileSize - _margin, tileSize - _margin), paint);
    canvas.drawLine(ui.Offset(_margin, tileSize - _margin), ui.Offset(tileSize - _margin, tileSize - _margin), paint);

    ui.ParagraphBuilder builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 10.0, textAlign: TextAlign.center))
      ..pushStyle(ui.TextStyle(color: Colors.black87))
      ..addText(error?.toString() ?? "Error");
    canvas.drawParagraph(builder.build()..layout(ui.ParagraphConstraints(width: tileSize - _margin * 2)), Offset(_margin, _margin));

    var pic = pictureRecorder.endRecording();
    return TilePicture.fromPicture(pic);
  }
}
