import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapsforge_flutter/core.dart';

class DefaultContextMenu extends StatefulWidget {
  /// The dimensions of the map as device-independent screen pixels
  final Dimension screen;

  /// The event when the context menu have been requested.
  final TapEvent event;

  final ViewModel viewModel;

  /// The current position of the map. Note that the map could move even if the contextmenu is shown.
  /// This means the x/y coordinates of the [event] may not be accurate anymore. The lat/lon
  /// position also represents the CURRENT position and not the position when the tap event occured.
  final MapViewPosition mapViewPosition;

  DefaultContextMenu(
      {required this.screen,
      required this.event,
      required this.viewModel,
      required this.mapViewPosition});

  @override
  State<StatefulWidget> createState() {
    return DefaultContextMenuState();
  }
}

/////////////////////////////////////////////////////////////////////////////

class DefaultContextMenuState extends State {
  double outerRadius = 20;
  double width = 4;
  double padding = 16;
  Color borderColor = Colors.green;
  Color backgroundColor = const Color(0xc3FFFFFF);

  @override
  DefaultContextMenu get widget => super.widget as DefaultContextMenu;

  @override
  Widget build(BuildContext context) {
    setValues(context);
    Radius outer = Radius.circular(outerRadius);
    // x and y of the event stays the same but we want our contextmenu to move with the map so calculate the
    // newest x/y coordinates based on the current position
    // double x = widget.event.x;
    // double y = widget.event.y;

    //widget.mapViewPosition.calculateBoundingBox(widget.screen);

    Mappoint center = widget.mapViewPosition.getCenter();

    /// distance from the center
    Mappoint mappoint = widget.event.mappoint;
    double diffX = mappoint.x - center.x;
    double diffY = mappoint.y - center.y;
    //print("tap ${widget.event} $diffX / $diffY");

    diffX = diffX / widget.viewModel.viewScaleFactor;
    diffY = diffY / widget.viewModel.viewScaleFactor;

    if (widget.viewModel.mapViewPosition?.rotation != 0) {
      double hyp = sqrt(diffX * diffX + diffY * diffY);
      double rad = atan2(diffY, diffX);
      double rot = widget.viewModel.mapViewPosition!.rotationRadian;
      diffX = cos(rot + rad) * hyp;
      diffY = sin(rot + rad) * hyp;

      // print(
      //     "diff: $diffX/$diffY @ ${widget.viewModel.mapViewPosition!.rotation}($rad) from ${(details.localFocalPoint.dx - _startLocalFocalPoint!.dx) * widget.viewModel.viewScaleFactor}/${(details.localFocalPoint.dy - _startLocalFocalPoint!.dy) * widget.viewModel.viewScaleFactor}");
    }

    double halfWidth = widget.screen.width / 2;
    double halfHeight = widget.screen.height / 2;

    diffX += halfWidth;
    diffY += halfHeight;
    return Positioned(
      left: diffX <= halfWidth ? diffX : null,
      top: diffY <= halfHeight ? diffY : null,
      right: diffX > halfWidth ? widget.screen.width - diffX : null,
      bottom: diffY > halfHeight ? widget.screen.height - diffY : null,
      child: Container(
        //margin: EdgeInsets.only(left: x, top: y),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft:
                diffX <= halfWidth && diffY <= halfHeight ? Radius.zero : outer,
            topRight:
                diffX > halfWidth && diffY <= halfHeight ? Radius.zero : outer,
            bottomLeft:
                diffX <= halfWidth && diffY > halfHeight ? Radius.zero : outer,
            bottomRight:
                diffX > halfWidth && diffY > halfHeight ? Radius.zero : outer,
          ),
          color: backgroundColor,
          border: Border.all(color: borderColor, width: width),
        ),
        //padding: EdgeInsets.symmetric(vertical: padding, horizontal: padding),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: buildColumns(context)
                .map((e) => Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                    child: e))
                .toList(),
          ),
        ),
      ),
    );
  }

  void setValues(BuildContext context) {
    backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    borderColor = Theme.of(context).primaryColor;
  }

  List<Widget> buildColumns(BuildContext context) {
    return [
      InkWell(
        onTap: () {
          widget.viewModel.clearTapEvent();
        },
        onLongPress: () {
          Clipboard.setData(new ClipboardData(
              text:
                  "${widget.event.latitude.toStringAsFixed(6)} / ${widget.event.longitude.toStringAsFixed(6)}"));
        },
        child: Container(
          //decoration: BoxDecoration(border: Border.all()),
          // make sure the tap-area is a bit larger
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            //mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${widget.event.latitude.toStringAsFixed(6)} / ${widget.event.longitude.toStringAsFixed(6)}",
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 10),
              // todo move the close icon to the right side
              const Icon(Icons.close, size: 20),
            ],
          ),
        ),
      ),
    ];
  }
}
