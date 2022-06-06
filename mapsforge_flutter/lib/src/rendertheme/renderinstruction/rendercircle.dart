import 'package:flutter/material.dart';
import 'package:mapsforge_flutter/core.dart';
import 'package:mapsforge_flutter/src/datastore/pointofinterest.dart';
import 'package:mapsforge_flutter/src/renderer/paintmixin.dart';
import 'package:mapsforge_flutter/src/renderer/polylinecontainer.dart';
import 'package:mapsforge_flutter/src/rendertheme/xml/xmlutils.dart';
import 'package:xml/xml.dart';

import '../rendercallback.dart';
import '../rendercontext.dart';
import 'renderinstruction.dart';

/**
 * Represents a round area on the map.
 */
class RenderCircle extends RenderInstruction with PaintMixin {
  final int level;
  double? radius;
  final Map<int, double> renderRadiusScaled;
  bool scaleRadius = false;

  RenderCircle(this.level)
      : renderRadiusScaled = new Map(),
        super() {
    initPaintMixin();
    this.setFillColor(Colors.transparent);
    this.setStrokeColor(Colors.transparent);
  }

  @override
  void dispose() {
    mixinDispose();
  }

  void parse(DisplayModel displayModel, XmlElement rootElement,
      List<RenderInstruction> initPendings) {
    rootElement.attributes.forEach((element) {
      String name = element.name.toString();
      String value = element.value;

      if (RenderInstruction.RADIUS == name || RenderInstruction.R == name) {
        this.radius = XmlUtils.parseNonNegativeFloat(name, value) *
            displayModel.getScaleFactor();
      } else if (RenderInstruction.CAT == name) {
        this.category = value;
      } else if (RenderInstruction.FILL == name) {
        this.setFillColorFromNumber(XmlUtils.getColor(value, this));
      } else if (RenderInstruction.SCALE_RADIUS == name) {
        this.scaleRadius = value == "true";
      } else if (RenderInstruction.STROKE == name) {
        this.setStrokeColorFromNumber(XmlUtils.getColor(value, this));
      } else if (RenderInstruction.STROKE_WIDTH == name) {
        this.setStrokeWidth(XmlUtils.parseNonNegativeFloat(name, value) *
            displayModel.getScaleFactor());
      } else {
        throw Exception("circle probs");
      }
    });

    XmlUtils.checkMandatoryAttribute(
        rootElement.name.toString(), RenderInstruction.RADIUS, this.radius);
  }

  double getRenderRadius(int zoomLevel) {
    double? radius = renderRadiusScaled[zoomLevel];
    radius ??= this.radius;
    return radius!;
  }

  @override
  void renderNode(RenderCallback renderCallback,
      final RenderContext renderContext, PointOfInterest poi) {
    renderCallback.renderPointOfInterestCircle(
        renderContext,
        getRenderRadius(renderContext.job.tile.zoomLevel),
        getFillPaint(renderContext.job.tile.zoomLevel),
        getStrokePaint(renderContext.job.tile.zoomLevel),
        this.level,
        poi);
  }

  @override
  void renderWay(RenderCallback renderCallback,
      final RenderContext renderContext, PolylineContainer way) {
    // do nothing
  }

  @override
  void scaleStrokeWidth(double scaleFactor, int zoomLevel) {
    if (this.scaleRadius) {
      this.renderRadiusScaled[zoomLevel] = this.radius! * scaleFactor;
      scaleMixinStrokeWidth(scaleFactor, zoomLevel);
    }
  }

  @override
  void scaleTextSize(double scaleFactor, int zoomLevel) {
    // do nothing
  }

  @override
  Future<RenderCircle> initResources(SymbolCache? symbolCache) {
    return Future.value(this);
  }
}
