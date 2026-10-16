import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/task_queue.dart';
import 'package:mapsforge_flutter_renderer/shape_painter.dart';
import 'package:mapsforge_flutter_renderer/src/ui/paragraph_cache_mgr.dart';
import 'package:mapsforge_flutter_renderer/src/ui/ui_paint.dart';
import 'package:mapsforge_flutter_renderer/src/ui/ui_render_context.dart';
import 'package:mapsforge_flutter_renderer/src/ui/ui_shape_painter.dart';
import 'package:mapsforge_flutter_renderer/src/ui/ui_text_paint.dart';
import 'package:mapsforge_flutter_rendertheme/model.dart';
import 'package:mapsforge_flutter_rendertheme/renderinstruction.dart';

/// Shape painter for rendering text along a polyline.
///
/// This painter is responsible for drawing text that follows the path of a line,
/// such as a street name. It handles text styling, including fill and stroke
/// (for halo effects), and calculates the correct position and rotation for the
/// text along the line.
class ShapePainterPolylineText extends UiShapePainter<RenderinstructionPolylineText> {
  /// The paint used for the text stroke (halo). Null if the stroke is transparent.
  late final UiPaint? paintBack;

  /// The paint used for the text fill. Null if the fill is transparent.
  late final UiPaint? paintFront;

  late final UiTextPaint textPaint;

  static final TaskQueue _taskQueue = SimpleTaskQueue(name: "ShapePainterPolylineText");

  /// Creates a new polyline text shape painter.
  ShapePainterPolylineText._(RenderinstructionPolylineText renderinstruction) : super(renderinstruction) {
    if (!renderinstruction.isFillTransparent()) {
      paintFront = UiPaint.fill(color: renderinstruction.fillColor);
    } else {
      paintFront = null;
    }
    if (!renderinstruction.isStrokeTransparent()) {
      paintBack = UiPaint.stroke(
        color: renderinstruction.strokeColor,
        strokeWidth: renderinstruction.strokeWidth,
        cap: renderinstruction.strokeCap,
        join: renderinstruction.strokeJoin,
        strokeDasharray: renderinstruction.strokeDashArray,
      );
    } else {
      paintBack = null;
    }
    textPaint = UiTextPaint();
    textPaint.setFontFamily(renderinstruction.fontFamily);
    textPaint.setFontStyle(renderinstruction.fontStyle);
    textPaint.setTextSize(renderinstruction.fontSize);
  }

  /// Creates a new polyline text shape painter with asynchronous initialization.
  ///
  /// Uses a task queue to ensure thread-safe creation and caches the result
  /// in the rendering instruction to avoid duplicate creation.
  static Future<ShapePainterPolylineText> create(RenderinstructionPolylineText renderinstruction) {
    return _taskQueue.add(() async {
      ShapePainterPolylineText? shapePainter = PainterFactory().getPainterForSerial(renderinstruction.serial) as ShapePainterPolylineText?;
      if (shapePainter != null) return shapePainter;
      shapePainter = ShapePainterPolylineText._(renderinstruction);
      PainterFactory().setPainterForSerial(renderinstruction.serial, shapePainter);
      return shapePainter;
    });
  }

  @override
  /// Renders text for a node.
  @override
  void renderNode(RenderInfo renderInfo, RenderContext renderContext, NodeProperties nodeProperties) {
    if (renderContext is! UiRenderContext) throw Exception("renderContext is not UiRenderContext ${renderContext.runtimeType}");
    if (renderInfo is! RenderInfoNode) throw Exception("renderInfo is not RenderInfoNode ${renderInfo.runtimeType}");

    LineSegmentPath? textPath = renderInfo.textPath;
    if (textPath != null && textPath.segments.isNotEmpty) {
      _drawAlongPath(renderInfo.caption!, textPath, renderContext, 0);
      return;
    }

    MappointRelative relative = nodeProperties.getCoordinatesAbsolute().offset(renderContext.reference).offset(0, renderinstruction.dy);
    if (paintBack != null) {
      ParagraphEntry entry = ParagraphCacheMgr().getEntry(renderInfo.caption!, textPaint, paintBack!, renderinstruction.getMaxTextWidth());
      renderContext.canvas.drawTextRotated(entry.paragraph, renderInfo.rotateRadians, relative);
    }
    if (paintFront != null) {
      ParagraphEntry entry = ParagraphCacheMgr().getEntry(renderInfo.caption!, textPaint, paintFront!, renderinstruction.getMaxTextWidth());
      renderContext.canvas.drawTextRotated(entry.paragraph, renderInfo.rotateRadians, relative);
    }
  }

  /// Renders text along a way.
  @override
  void renderWay(RenderInfo renderInfo, RenderContext renderContext, WayProperties wayProperties) {
    if (renderContext is! UiRenderContext) throw Exception("renderContext is not UiRenderContext ${renderContext.runtimeType}");
    if (renderInfo is! RenderInfoWay) throw Exception("renderInfo is not RenderInfoWay ${renderInfo.runtimeType}");

    LineSegmentPath? lineSegmentPath = wayProperties.calculateStringPath(renderinstruction.dy);
    if (lineSegmentPath == null || lineSegmentPath.segments.isEmpty) {
      return;
    }

    MapSize textSize = renderinstruction.getEstimatedTextBoundary(renderInfo.caption!, renderinstruction.strokeWidth);
    for (LineSegmentPath textPath in lineSegmentPath.textPaths(textSize.width, renderinstruction.repeatStart, renderinstruction.repeatGap, repeat: renderinstruction.repeat)) {
      _drawAlongPath(renderInfo.caption!, textPath.last.x < textPath.first.x ? textPath.reversed() : textPath, renderContext, renderContext.rotationRadian);
    }
  }

  /// Letters [text] along [path] (absolute pixels, already oriented left to
  /// right), one glyph at a time, each rotated to the local direction of the
  /// curve — the way mapsforge-java's drawTextOnPath renders street and river
  /// names. The text is centred on the path and may overhang a short path
  /// (see [LineSegmentPath.pointAt]). Halos are drawn first so they never
  /// cover a neighbouring glyph's fill.
  void _drawAlongPath(String text, LineSegmentPath path, UiRenderContext renderContext, double extraRotation) {
    // Control and zero-width format characters (ZWSP, joiners, BOM, RTL marks)
    // have no measurable width; a paragraph of one would fail layout.
    final List<String> glyphs = text.runes.where((r) => r >= 32 && !(r >= 0x200B && r <= 0x200F) && r != 0xFEFF && r != 0x061C && !(r >= 0x202A && r <= 0x202E)).map((r) => String.fromCharCode(r)).toList();
    if (glyphs.isEmpty) return;
    final UiPaint? measurePaint = paintFront ?? paintBack;
    if (measurePaint == null) return;
    // A paragraph of only whitespace has no measurable line; give spaces a
    // fixed advance and skip drawing them.
    final double spaceWidth = renderinstruction.fontSize * 0.3;
    final List<double> widths = [
      for (String g in glyphs) g.trim().isEmpty ? spaceWidth : ParagraphCacheMgr().getEntry(g, textPaint, measurePaint, renderinstruction.getMaxTextWidth()).getWidth(),
    ];
    final double total = widths.fold(0, (a, b) => a + b);
    final double startOffset = (path.length() - total) / 2;

    for (UiPaint? paint in [paintBack, paintFront]) {
      if (paint == null) continue;
      double distance = startOffset;
      for (int i = 0; i < glyphs.length; i++) {
        double width = widths[i];
        if (glyphs[i].trim().isNotEmpty) {
          ParagraphEntry entry = ParagraphCacheMgr().getEntry(glyphs[i], textPaint, paint, renderinstruction.getMaxTextWidth());
          double theta = path.directionAt(distance + width / 2);
          renderContext.canvas.drawTextRotated(entry.paragraph, extraRotation + theta, path.pointAt(distance).offset(renderContext.reference));
        }
        distance += width;
      }
    }
  }
}
