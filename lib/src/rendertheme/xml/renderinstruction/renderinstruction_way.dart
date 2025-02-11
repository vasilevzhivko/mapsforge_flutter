import 'package:mapsforge_flutter/src/rendertheme/shape/shape.dart';

import '../../rendercontext.dart';
import '../../wayproperties.dart';

/// A RenderInstruction is a basic graphical primitive to draw a map. It reads the
/// instructions from an xml file. It can be seen like a CSS-file for html.
abstract class RenderInstructionWay {
  RenderInstructionWay();

  /// prepares the renderinstruction for the given zoomLevel. Returns the
  /// new RenderInstruction or NULL if it would never draw anything
  Shape? prepareScale(int zoomLevel);
}
