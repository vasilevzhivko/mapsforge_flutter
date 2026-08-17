import 'package:mapsforge_flutter_renderer/ui.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter_core/model.dart';

class TileSet {
  final Mappoint center;

  final MapPosition mapPosition;

  final Map<Tile, TilePicture> images;

  /// [images] lets a new tileSet SHARE the map of a previous one (used for
  /// scale/rotation-only updates) so tiles still being produced for the old
  /// job remain visible after the update. Defaults to a fresh empty map.
  TileSet({required this.center, required this.mapPosition, Map<Tile, TilePicture>? images}) : images = images ?? {};

  Mappoint getCenter() => center;
}
