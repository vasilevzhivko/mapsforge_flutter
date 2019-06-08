import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:mapsforge_flutter/core.dart';

import 'mapmodelhelper.dart';

class Showmap extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return ShowmapState();
  }
}

/////////////////////////////////////////////////////////////////////////////

class ShowmapState extends State<Showmap> {
  Timer timer;

  MapModel mapModel;

  @override
  void initState() {
    super.initState();
    MapModelHelper.prepareMapModel().then((mapModel) {
      setState(() {
        this.mapModel = mapModel;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapsforge map'),
      ),
      body: mapModel == null
          ? Center(
              child: CircularProgressIndicator(),
            )
          : _buildMapModel(mapModel),
    );
  }

  Widget _buildMapModel(MapModel mapModel) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            RaisedButton(
              child: Text("Set Location"),
              onPressed: () {
                mapModel.setMapViewPosition(48.0901926, 16.308939);
              },
            ),
            RaisedButton(
              child: Text("run around"),
              onPressed: () {
                if (timer != null) return;
                timer = Timer.periodic(Duration(seconds: 1), (timer) {
                  mapModel.setLeftUpper(mapModel.mapViewPosition.leftUpper.x + 10, mapModel.mapViewPosition.leftUpper.y + 10);
                });
              },
            ),
            RaisedButton(
              child: Text("stop"),
              onPressed: () {
                timer.cancel();
                timer = null;
              },
            ),
            RaisedButton(
              child: Text("Zoom in"),
              onPressed: () {
                mapModel.zoomIn();
              },
            ),
            RaisedButton(
              child: Text("Zoom out"),
              onPressed: () {
                mapModel.zoomOut();
              },
            ),
            StreamBuilder(
              stream: mapModel.observePosition,
              builder: (BuildContext context, AsyncSnapshot<MapViewPosition> snapshot) {
                if (!snapshot.hasData) return Container();
                return Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text("Zoom ${snapshot.data?.zoomLevel ?? ""}"),
                );
              },
            ),
            StreamBuilder(
              stream: mapModel.observeTap,
              builder: (BuildContext context, AsyncSnapshot<TapEvent> snapshot) {
                if (!snapshot.hasData) return Container();
                TapEvent event = snapshot.data;
                return Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text("Tapped ${event.latitude.toStringAsFixed(6)} / ${event.longitude.toStringAsFixed(6)}"),
                );
              },
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.green)),
              child: FlutterMapView(
                mapModel: mapModel,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
