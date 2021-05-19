import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter/core.dart';
import 'package:mapsforge_flutter/maps.dart';
import 'package:mapsforge_flutter/src/model/tile.dart';
import 'package:mapsforge_flutter/src/projection/projection.dart';
import 'package:mapsforge_flutter/src/projection/scalefactor.dart';

main() {
  test("Scalefactor", () {
    expect(Scalefactor.fromZoomlevel(4).scalefactor, 16);
    expect(Scalefactor.fromScalefactor(16).zoomlevel, 4);
  });

  test("MercatorProjection", () {
    int zoomLevel = 4; // 1, 2, 4, 8, 16 tiles per zoomlevel
    MercatorProjection projection = MercatorProjection.fromZoomlevel(zoomLevel);
    expect(projection.tileYToLatitude(0), Projection.LATITUDE_MAX);
    expect(projection.tileYToLatitude(7), 21.943045533438166);
    expect(projection.tileYToLatitude(8), 0);
    expect(projection.tileYToLatitude(15), -82.67628497834903);
    expect(projection.tileYToLatitude(16), Projection.LATITUDE_MIN);

    expect(projection.tileXToLongitude(0), -180);
    expect(projection.tileXToLongitude(7), -22.5);
    expect(projection.tileXToLongitude(8), 0);
    expect(projection.tileXToLongitude(15), 157.5);
    expect(projection.tileXToLongitude(16), 180);

    expect(projection.longitudeToTileX(7.4262), 8); // lat/lon: 43.7399/7.4262;
    expect(projection.latitudeToTileY(43.7399), 5);

    Tile upperLeft = Tile(4, 3, zoomLevel, 0);
    Tile lowerRight = Tile(6, 5, zoomLevel, 0);
    BoundingBox boundingBox = projection.boundingBoxOfTiles(upperLeft, lowerRight);
    expect(boundingBox.minLongitude, -90);
    expect(boundingBox.maxLongitude, -22.5);
    expect(boundingBox.minLatitude, 40.97989806962013);
    expect(boundingBox.maxLatitude, 74.01954331150228);
  });
}